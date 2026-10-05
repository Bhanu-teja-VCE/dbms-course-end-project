-- ============================================================================
-- Bank Loan Management System: EMI Processing, Repayment Tracking, and Risk Assessment
-- File      : procedures_triggers.sql
-- Database  : bank_loan_db (MySQL 8.0+ / InnoDB Engine)
-- Purpose   : Stored Procedures, Triggers, Cursor Iteration & Transaction Management
-- ============================================================================
-- VIVA DEFENSE GUIDE:
-- 1. WHY STORED PROCEDURES?
--    - Encapsulation: Business rules (amortization schedule math, repayment processing)
--      run inside the database engine, eliminating multiple client-server network roundtrips.
--    - Security & Privileges: Direct table modifications can be revoked from client apps;
--      users are only granted EXECUTE privileges on vetted procedures.
--    - Performance: SQL execution plans are compiled and cached in MySQL's statement cache.
--
-- 2. WHY ACID TRANSACTIONS HERE?
--    - In banking, atomic execution is mandatory. When an EMI is repaid:
--      (a) Cash must be credited in REPAYMENT,
--      (b) Installment status in EMI_SCHEDULE must change to PAID,
--      (c) Late fees must be computed,
--      (d) Loan closure must be evaluated.
--      If a network failure or constraint error occurs midway, START TRANSACTION + ROLLBACK
--      guarantees that partial data never corrupts the ledger (Atomicity & Consistency).
--
-- 3. WHY PESSIMISTIC LOCKING (`SELECT ... FOR UPDATE`)?
--    - Prevents race conditions / double payments if two channels (e.g. mobile UPI and
--      net-banking webhook) attempt to settle the identical EMI installment simultaneously.
--
-- 4. WHY BEFORE vs AFTER TRIGGERS?
--    - `BEFORE UPDATE`: Directly inspects and modifies `NEW.status` in-memory prior to writing
--      to disk, avoiding expensive secondary UPDATE calls.
--    - `AFTER UPDATE`: Reacts to confirmed state changes to cascade audit records or classify
--      bad loans (NPAs) across other tables (`LOAN`, `DEFAULT_LOG`, `LOAN_AUDIT`).
-- ============================================================================

USE `bank_loan_db`;

-- Drop existing routines and triggers to guarantee a clean, idempotent reload
DROP PROCEDURE IF EXISTS `generate_emi_schedule`;
DROP PROCEDURE IF EXISTS `process_repayment`;
DROP PROCEDURE IF EXISTS `mark_overdue_emis`;
DROP PROCEDURE IF EXISTS `get_loan_summary`;

DROP TRIGGER IF EXISTS `trg_mark_overdue`;
DROP TRIGGER IF EXISTS `trg_check_default`;
DROP TRIGGER IF EXISTS `trg_loan_audit`;

DELIMITER $$

-- ============================================================================
-- 1. PROCEDURE: generate_emi_schedule(p_loan_id INT)
-- ============================================================================
-- PURPOSE:
--   Computes standard reducing-balance EMI and generates all installment records
--   in `EMI_SCHEDULE` for a given sanctioned loan.
--
-- MATHEMATICAL FORMULATION:
--   EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
--   where:
--     P = Principal Loan Amount (`principal_amount`)
--     r = Monthly Interest Rate = (Annual Interest Rate % / 12) / 100
--     n = Tenure in Months (`tenure_months`)
--
-- AMORTIZATION SCHEDULE LOGIC:
--   For each monthly installment i from 1 to n:
--     Interest Component   = ROUND(Remaining Balance * r, 2)
--     Principal Component  = EMI - Interest Component
--     Balance After        = Remaining Balance - Principal Component
--   LAST INSTALLMENT ADJUSTMENT:
--     In the final month (i = n), cumulative rounding of fractions of a paisa can
--     leave a small positive/negative residual. To guarantee an exact zero closing
--     balance, Principal Component is set directly to Remaining Balance, and
--     the final EMI is adjusted as (Principal Component + Interest Component).
--
-- TRANSACTION CONTROL:
--   Wrapped in an ACID transaction with SQLEXCEPTION handler. If an error occurs,
--   all inserted installments are rolled back cleanly.
-- ============================================================================
CREATE PROCEDURE `generate_emi_schedule`(
    IN p_loan_id INT
)
proc_label: BEGIN
    -- Financial calculation variables
    DECLARE v_principal         DECIMAL(12, 2);
    DECLARE v_annual_rate       DECIMAL(5, 2);
    DECLARE v_tenure            INT;
    DECLARE v_disb_date         DATE;
    DECLARE v_status            VARCHAR(20);
    DECLARE v_monthly_rate      DOUBLE;
    DECLARE v_factor            DOUBLE;
    DECLARE v_emi_calc          DOUBLE;
    DECLARE v_emi_amount        DECIMAL(10, 2);
    
    -- Amortization loop variables
    DECLARE v_remaining_balance DECIMAL(12, 2);
    DECLARE v_interest_comp     DECIMAL(10, 2);
    DECLARE v_principal_comp    DECIMAL(10, 2);
    DECLARE v_balance_after     DECIMAL(12, 2);
    DECLARE v_installment_emi   DECIMAL(10, 2);
    DECLARE v_due_date          DATE;
    DECLARE v_installment_no    INT DEFAULT 1;
    DECLARE v_total_payable     DECIMAL(12, 2) DEFAULT 0.00;
    
    -- Safety validation variables
    DECLARE v_loan_exists       INT DEFAULT 0;
    DECLARE v_paid_count        INT DEFAULT 0;

    -- Error handler: Rollback on any SQL exception
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Step 1: Validate Loan Existence and fetch details
    SELECT COUNT(*) INTO v_loan_exists 
    FROM `LOAN` 
    WHERE `loan_id` = p_loan_id;

    IF v_loan_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Loan record does not exist for provided loan_id.';
    END IF;

    SELECT `principal_amount`, `interest_rate`, `tenure_months`, `disbursement_date`, `status`
    INTO v_principal, v_annual_rate, v_tenure, v_disb_date, v_status
    FROM `LOAN`
    WHERE `loan_id` = p_loan_id;

    -- Step 2: Validate Loan Lifecycle State
    IF v_status IN ('CLOSED', 'REJECTED', 'DEFAULTED') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Cannot generate EMI schedule for CLOSED, REJECTED, or DEFAULTED loans.';
    END IF;

    -- Check if any installments have already been serviced (cannot regenerate a live repayment history)
    SELECT COUNT(*) INTO v_paid_count
    FROM `EMI_SCHEDULE`
    WHERE `loan_id` = p_loan_id AND `status` = 'PAID';

    IF v_paid_count > 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Repayments have already been recorded for this loan. Schedule cannot be regenerated.';
    END IF;

    -- Fallback: If disbursement date is NULL, default to today's date
    IF v_disb_date IS NULL THEN
        SET v_disb_date = CURDATE();
    END IF;

    -- Step 3: Compute Equated Monthly Installment (EMI) using Reducing Balance Formula
    -- r = annual_rate / 12 / 100
    SET v_monthly_rate = (v_annual_rate / 12.0) / 100.0;
    -- factor = (1 + r)^n
    SET v_factor = POW(1.0 + v_monthly_rate, v_tenure);
    -- EMI = P * r * factor / (factor - 1)
    SET v_emi_calc = (v_principal * v_monthly_rate * v_factor) / (v_factor - 1.0);
    SET v_emi_amount = ROUND(v_emi_calc, 2);

    -- Step 4: Execute Schedule Generation Inside an ACID Transaction
    START TRANSACTION;

        -- Remove any existing unserviced schedule entries for clean recreation
        DELETE FROM `EMI_SCHEDULE` WHERE `loan_id` = p_loan_id;

        SET v_remaining_balance = v_principal;
        SET v_installment_no = 1;

        -- WHILE Loop generating each monthly installment
        WHILE v_installment_no <= v_tenure DO
            -- Installment due date falls on the same calendar day each successive month
            SET v_due_date = DATE_ADD(v_disb_date, INTERVAL v_installment_no MONTH);
            
            -- Interest Component = remaining balance * monthly interest rate
            SET v_interest_comp = ROUND(v_remaining_balance * v_monthly_rate, 2);

            -- Check if this is the final installment
            IF v_installment_no = v_tenure THEN
                -- Terminal adjustment to prevent floating point penny accumulation
                SET v_principal_comp = v_remaining_balance;
                SET v_installment_emi = v_principal_comp + v_interest_comp;
                SET v_balance_after = 0.00;
            ELSE
                SET v_principal_comp = v_emi_amount - v_interest_comp;
                SET v_installment_emi = v_emi_amount;
                SET v_balance_after = v_remaining_balance - v_principal_comp;
            END IF;

            -- Insert the installment schedule record
            INSERT INTO `EMI_SCHEDULE` (
                `loan_id`,
                `installment_no`,
                `due_date`,
                `principal_component`,
                `interest_component`,
                `emi_amount`,
                `balance_after`,
                `status`,
                `paid_date`,
                `penalty_amount`
            ) VALUES (
                p_loan_id,
                v_installment_no,
                v_due_date,
                v_principal_comp,
                v_interest_comp,
                v_installment_emi,
                v_balance_after,
                'PENDING',
                NULL,
                0.00
            );

            -- Accumulate total committed repayment obligations
            SET v_total_payable = v_total_payable + v_installment_emi;
            SET v_remaining_balance = v_balance_after;
            SET v_installment_no = v_installment_no + 1;
        END WHILE;

        -- Step 5: Synchronize Header Contract in LOAN Table
        UPDATE `LOAN`
        SET `emi_amount`        = v_emi_amount,
            `total_payable`     = v_total_payable,
            `disbursement_date` = v_disb_date,
            `maturity_date`     = DATE_ADD(v_disb_date, INTERVAL v_tenure MONTH),
            `status`            = IF(`status` IN ('PENDING', 'APPROVED'), 'ACTIVE', `status`)
        WHERE `loan_id` = p_loan_id;

    COMMIT;

    -- Return execution feedback
    SELECT 
        p_loan_id AS `loan_id`,
        v_principal AS `principal_amount`,
        v_annual_rate AS `interest_rate_pct`,
        v_tenure AS `tenure_months`,
        v_emi_amount AS `monthly_emi`,
        v_total_payable AS `total_payable`,
        DATE_ADD(v_disb_date, INTERVAL v_tenure MONTH) AS `maturity_date`,
        'EMI Schedule Generated Successfully' AS `message`;

END proc_label$$


-- ============================================================================
-- 2. PROCEDURE: process_repayment(...)
-- ============================================================================
-- PURPOSE:
--   Executes a financial repayment against a scheduled EMI installment under ACID
--   guarantees with pessimistic row-level locking.
--
-- BUSINESS RULES:
--   1. Validates that the EMI installment exists and has not already been marked 'PAID'.
--   2. Enforces Pessimistic Locking (`SELECT ... FOR UPDATE`) to guarantee mutual
--      exclusion and completely eliminate the double-payment concurrency hazard.
--   3. Calculates accrued late fee / penalty if payment date > due date, using
--      the product's `penalty_rate_pct` (SBI standard late payment fee).
--   4. Computes prior partial payments made against the installment.
--   5. Updates installment status:
--      - If (amount_paid + previously_paid) >= total_due: status = 'PAID'
--      - Otherwise: status = 'PARTIALLY_PAID'
--   6. Inserts immutable audit entry into `REPAYMENT` ledger.
--   7. Checks if ALL installments for the loan have reached 'PAID'. If so, automatically
--      transitions `LOAN.status` to 'CLOSED' and records audit trail.
--   8. If any step fails, triggers ROLLBACK to preserve ledger integrity.
-- ============================================================================
CREATE PROCEDURE `process_repayment`(
    IN p_emi_id   INT,
    IN p_amount   DECIMAL(12, 2),
    IN p_mode     VARCHAR(20),
    IN p_ref      VARCHAR(50)
)
proc_label: BEGIN
    -- Stored procedure variables
    DECLARE v_emi_id            INT;
    DECLARE v_loan_id           INT;
    DECLARE v_inst_no           INT;
    DECLARE v_due_date          DATE;
    DECLARE v_emi_amount        DECIMAL(10, 2);
    DECLARE v_current_penalty   DECIMAL(10, 2);
    DECLARE v_current_status    VARCHAR(20);
    DECLARE v_penalty_rate_pct  DECIMAL(4, 2);
    
    DECLARE v_late_fee          DECIMAL(10, 2) DEFAULT 0.00;
    DECLARE v_already_paid      DECIMAL(12, 2) DEFAULT 0.00;
    DECLARE v_total_due         DECIMAL(12, 2) DEFAULT 0.00;
    DECLARE v_new_status        VARCHAR(20);
    DECLARE v_unpaid_emis       INT DEFAULT 0;
    DECLARE v_payment_date      DATE;

    -- Error handler: Rollback on any failure and raise original error
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    -- Input Validation
    IF p_amount <= 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Repayment amount must be strictly greater than zero.';
    END IF;

    IF p_mode NOT IN ('CASH', 'CHEQUE', 'NEFT', 'UPI', 'AUTO_DEBIT') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Invalid payment mode. Allowed: CASH, CHEQUE, NEFT, UPI, AUTO_DEBIT.';
    END IF;

    SET v_payment_date = CURDATE();

    -- ACID Transaction Boundary
    START TRANSACTION;

        -- Step 1: Pessimistic Row Lock (SELECT ... FOR UPDATE)
        -- Prevents concurrent transactions from reading or modifying the same EMI simultaneously
        SELECT 
            es.`emi_id`, 
            es.`loan_id`, 
            es.`installment_no`, 
            es.`due_date`, 
            es.`emi_amount`, 
            es.`penalty_amount`, 
            es.`status`,
            lp.`penalty_rate_pct`
        INTO 
            v_emi_id, 
            v_loan_id, 
            v_inst_no, 
            v_due_date, 
            v_emi_amount, 
            v_current_penalty, 
            v_current_status,
            v_penalty_rate_pct
        FROM `EMI_SCHEDULE` es
        JOIN `LOAN` l ON es.`loan_id` = l.`loan_id`
        JOIN `LOAN_PRODUCT` lp ON l.`product_id` = lp.`product_id`
        WHERE es.`emi_id` = p_emi_id
        FOR UPDATE;

        -- Step 2: Validate Record State
        IF v_emi_id IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: Specified EMI schedule installment was not found.';
        END IF;

        IF v_current_status = 'PAID' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Error: This EMI installment has already been fully paid.';
        END IF;

        -- Step 3: Compute Late Fee / Delay Penalty if overdue
        IF v_payment_date > v_due_date THEN
            -- Late fee calculated as a percentage of the overdue installment amount
            SET v_late_fee = ROUND(v_emi_amount * (v_penalty_rate_pct / 100.0), 2);
        ELSE
            SET v_late_fee = 0.00;
        END IF;

        -- Step 4: Calculate Previous Payments made towards this specific installment
        SELECT COALESCE(SUM(`amount_paid`), 0.00) INTO v_already_paid
        FROM `REPAYMENT`
        WHERE `emi_id` = p_emi_id;

        -- Total net requirement to clear installment
        SET v_total_due = (v_emi_amount + v_current_penalty + v_late_fee) - v_already_paid;

        -- Determine status transition
        IF (p_amount + v_already_paid) >= (v_emi_amount + v_current_penalty + v_late_fee) THEN
            SET v_new_status = 'PAID';
        ELSE
            SET v_new_status = 'PARTIALLY_PAID';
        END IF;

        -- Step 5: Insert Record into REPAYMENT Ledger
        INSERT INTO `REPAYMENT` (
            `emi_id`,
            `loan_id`,
            `amount_paid`,
            `payment_date`,
            `payment_mode`,
            `transaction_ref`,
            `late_fee`,
            `remarks`
        ) VALUES (
            p_emi_id,
            v_loan_id,
            p_amount,
            NOW(),
            p_mode,
            p_ref,
            v_late_fee,
            CONCAT('Payment of INR ', p_amount, ' for Installment #', v_inst_no, ' [Status: ', v_new_status, ']')
        );

        -- Step 6: Update Installment in EMI_SCHEDULE
        UPDATE `EMI_SCHEDULE`
        SET `status`         = v_new_status,
            `paid_date`      = IF(v_new_status = 'PAID', v_payment_date, `paid_date`),
            `penalty_amount` = `penalty_amount` + v_late_fee
        WHERE `emi_id` = p_emi_id;

        -- Step 7: Check if Entire Loan is Fully Settled
        SELECT COUNT(*) INTO v_unpaid_emis
        FROM `EMI_SCHEDULE`
        WHERE `loan_id` = v_loan_id AND `status` != 'PAID';

        IF v_unpaid_emis = 0 THEN
            -- Close the loan account
            UPDATE `LOAN`
            SET `status`  = 'CLOSED',
                `remarks` = CONCAT(COALESCE(`remarks`, ''), ' [Loan fully satisfied and closed on ', v_payment_date, ']')
            WHERE `loan_id` = v_loan_id;
        END IF;

    COMMIT;

    -- Return execution summary
    SELECT 
        p_emi_id AS `emi_id`,
        v_loan_id AS `loan_id`,
        v_inst_no AS `installment_no`,
        p_amount AS `amount_paid`,
        v_late_fee AS `late_fee_assessed`,
        v_new_status AS `installment_status`,
        IF(v_unpaid_emis = 0, 'CLOSED', 'ACTIVE') AS `loan_status`,
        'Repayment Processed Successfully' AS `message`;

END proc_label$$


-- ============================================================================
-- 3. TRIGGER: trg_mark_overdue
-- ============================================================================
-- PURPOSE:
--   Runs BEFORE UPDATE on `EMI_SCHEDULE`. If the due date has elapsed
--   (`due_date < CURDATE()`) and the status is still 'PENDING', automatically
--   transitions the status to 'OVERDUE'.
--
-- VIVA NOTE:
--   Why BEFORE UPDATE?
--   A BEFORE trigger directly mutates the row buffer in-memory (`SET NEW.status = ...`)
--   before the row is committed to disk. This completely avoids executing an extra
--   SQL UPDATE statement, eliminating recursive trigger overhead.
-- ============================================================================
CREATE TRIGGER `trg_mark_overdue`
BEFORE UPDATE ON `EMI_SCHEDULE`
FOR EACH ROW
BEGIN
    -- If due date is in the past and payment has not been received, mark overdue
    IF NEW.`due_date` < CURDATE() AND NEW.`status` = 'PENDING' THEN
        SET NEW.`status` = 'OVERDUE';
    END IF;
END$$


-- ============================================================================
-- 4. TRIGGER: trg_check_default
-- ============================================================================
-- PURPOSE:
--   Runs AFTER UPDATE on `EMI_SCHEDULE`. Evaluates whether the loan has accumulated
--   >= 3 overdue installments (standard RBI Non-Performing Asset / NPA criterion).
--   If threshold is met:
--     1. Updates `LOAN.status` to 'DEFAULTED'.
--     2. Inserts an escalation case into `DEFAULT_LOG`.
--
-- CASCADING TRIGGER ARCHITECTURE:
--   When `trg_check_default` executes `UPDATE LOAN SET status = 'DEFAULTED'`, it
--   automatically fires `trg_loan_audit` (AFTER UPDATE ON LOAN). This cleanly
--   demonstrates cascading trigger propagation in relational databases!
-- ============================================================================
CREATE TRIGGER `trg_check_default`
AFTER UPDATE ON `EMI_SCHEDULE`
FOR EACH ROW
BEGIN
    DECLARE v_overdue_count         INT DEFAULT 0;
    DECLARE v_total_outstanding     DECIMAL(12, 2) DEFAULT 0.00;
    DECLARE v_loan_status           VARCHAR(20);
    DECLARE v_already_logged        INT DEFAULT 0;

    -- Only evaluate when installment is classified as OVERDUE
    IF NEW.`status` = 'OVERDUE' THEN
        -- Count total overdue installments accumulated on this loan contract
        SELECT COUNT(*) INTO v_overdue_count
        FROM `EMI_SCHEDULE`
        WHERE `loan_id` = NEW.`loan_id` AND `status` = 'OVERDUE';

        -- RBI NPA Criterion: 3 or more overdue installments
        IF v_overdue_count >= 3 THEN
            SELECT `status` INTO v_loan_status
            FROM `LOAN`
            WHERE `loan_id` = NEW.`loan_id`;

            -- Only transition if loan is not already DEFAULTED, CLOSED, or REJECTED
            IF v_loan_status NOT IN ('DEFAULTED', 'CLOSED', 'REJECTED') THEN
                -- Compute aggregate outstanding exposure (unpaid principal + interest + penalties)
                SELECT COALESCE(SUM(`emi_amount` + `penalty_amount`), 0.00) INTO v_total_outstanding
                FROM `EMI_SCHEDULE`
                WHERE `loan_id` = NEW.`loan_id` AND `status` != 'PAID';

                -- 1. Update master loan status (fires trg_loan_audit!)
                UPDATE `LOAN`
                SET `status`  = 'DEFAULTED',
                    `remarks` = CONCAT(COALESCE(`remarks`, ''), ' [DEFAULTED: Overdue count reached ', v_overdue_count, ' on ', CURDATE(), ']')
                WHERE `loan_id` = NEW.`loan_id`;

                -- 2. Log NPA incident into DEFAULT_LOG if an active unresolved record does not exist
                SELECT COUNT(*) INTO v_already_logged
                FROM `DEFAULT_LOG`
                WHERE `loan_id` = NEW.`loan_id` AND `resolved` = FALSE;

                IF v_already_logged = 0 THEN
                    INSERT INTO `DEFAULT_LOG` (
                        `loan_id`,
                        `default_date`,
                        `outstanding_amount`,
                        `months_overdue`,
                        `action_taken`,
                        `resolved`,
                        `resolution_date`,
                        `remarks`
                    ) VALUES (
                        NEW.`loan_id`,
                        CURDATE(),
                        v_total_outstanding,
                        v_overdue_count,
                        'NOTICE_SENT',
                        FALSE,
                        NULL,
                        CONCAT('Automated default classification: ', v_overdue_count, ' installments overdue. RBI 90-day NPA classification triggered. Dispatched statutory recovery notice.')
                    );
                END IF;
            END IF;
        END IF;
    END IF;
END$$


-- ============================================================================
-- 5. TRIGGER: trg_loan_audit
-- ============================================================================
-- PURPOSE:
--   Runs AFTER UPDATE on `LOAN`. Detects any lifecycle state transitions
--   (e.g., PENDING -> APPROVED -> ACTIVE -> CLOSED / DEFAULTED) and records
--   an immutable before-and-after audit row in `LOAN_AUDIT`.
--
-- COMPLIANCE RELEVANCE:
--   Meets RBI IT Risk Governance and Sarbanes-Oxley (SOX) compliance mandates
--   requiring an unalterable forensic record of every credit portfolio state change.
-- ============================================================================
CREATE TRIGGER `trg_loan_audit`
AFTER UPDATE ON `LOAN`
FOR EACH ROW
BEGIN
    -- Log whenever the loan lifecycle status changes
    IF OLD.`status` != NEW.`status` THEN
        INSERT INTO `LOAN_AUDIT` (
            `loan_id`,
            `field_changed`,
            `old_value`,
            `new_value`,
            `changed_at`,
            `changed_by`
        ) VALUES (
            NEW.`loan_id`,
            'status',
            OLD.`status`,
            NEW.`status`,
            NOW(),
            COALESCE(SUBSTRING_INDEX(USER(), '@', 1), 'SYSTEM')
        );
    END IF;

    -- Also audit interest rate revisions if modified by bank treasury
    IF OLD.`interest_rate` != NEW.`interest_rate` THEN
        INSERT INTO `LOAN_AUDIT` (
            `loan_id`,
            `field_changed`,
            `old_value`,
            `new_value`,
            `changed_at`,
            `changed_by`
        ) VALUES (
            NEW.`loan_id`,
            'interest_rate',
            CAST(OLD.`interest_rate` AS CHAR),
            CAST(NEW.`interest_rate` AS CHAR),
            NOW(),
            COALESCE(SUBSTRING_INDEX(USER(), '@', 1), 'SYSTEM')
        );
    END IF;
END$$


-- ============================================================================
-- 6. PROCEDURE: mark_overdue_emis()
-- ============================================================================
-- PURPOSE:
--   Scheduled nightly batch job. Scans all installments in `EMI_SCHEDULE` where
--   `due_date < CURDATE()` and `status = 'PENDING'`, updating them to 'OVERDUE'.
--
-- TECHNICAL DESIGN:
--   Uses a relational CURSOR with a CONTINUE HANDLER FOR NOT FOUND to process
--   rows sequentially. Each individual row update activates `trg_mark_overdue`
--   and `trg_check_default`, ensuring real-time NPA evaluation during batch runs.
--
-- VIVA DEFENSE:
--   "Why use a cursor when `UPDATE EMI_SCHEDULE SET status='OVERDUE' WHERE...` exists?"
--   Answer: In high-scale banking architectures, a single massive batch UPDATE locks
--   thousands of rows simultaneously, escalating to page/table locks. Iterating
--   via a cursor allows row-by-row locking, granular exception handling, per-row
--   event dispatching, and trigger activation without locking the entire table.
-- ============================================================================
CREATE PROCEDURE `mark_overdue_emis`()
proc_label: BEGIN
    -- Cursor variables
    DECLARE v_done              INT DEFAULT FALSE;
    DECLARE v_emi_id            INT;
    DECLARE v_due_date          DATE;
    DECLARE v_processed_count   INT DEFAULT 0;

    -- Cursor declaration
    DECLARE cur_overdue CURSOR FOR
        SELECT `emi_id`, `due_date`
        FROM `EMI_SCHEDULE`
        WHERE `status` = 'PENDING'
          AND `due_date` < CURDATE();

    -- Continue handler for cursor completion
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    OPEN cur_overdue;

    overdue_loop: LOOP
        FETCH cur_overdue INTO v_emi_id, v_due_date;
        IF v_done THEN
            LEAVE overdue_loop;
        END IF;

        -- Updating the row activates trg_mark_overdue and trg_check_default
        UPDATE `EMI_SCHEDULE`
        SET `status` = 'OVERDUE'
        WHERE `emi_id` = v_emi_id;

        SET v_processed_count = v_processed_count + 1;
    END LOOP overdue_loop;

    CLOSE cur_overdue;

    SELECT CONCAT('Batch Overdue Job Complete. Successfully scanned and marked ', v_processed_count, ' installment(s) as OVERDUE.') AS `batch_status`;
END proc_label$$


-- ============================================================================
-- 7. PROCEDURE: get_loan_summary(p_loan_id INT)
-- ============================================================================
-- PURPOSE:
--   Comprehensive 360-degree loan inquiry procedure. Retrieves borrower details,
--   aggregate financial progress, total repaid, outstanding balance, next due EMI,
--   and delinquent installment count.
-- ============================================================================
CREATE PROCEDURE `get_loan_summary`(
    IN p_loan_id INT
)
proc_label: BEGIN
    DECLARE v_loan_exists           INT DEFAULT 0;
    DECLARE v_total_paid            DECIMAL(12, 2) DEFAULT 0.00;
    DECLARE v_total_outstanding     DECIMAL(12, 2) DEFAULT 0.00;
    DECLARE v_overdue_count         INT DEFAULT 0;
    DECLARE v_paid_count            INT DEFAULT 0;
    DECLARE v_total_emis            INT DEFAULT 0;
    DECLARE v_next_due_date         DATE DEFAULT NULL;
    DECLARE v_next_due_amount       DECIMAL(10, 2) DEFAULT 0.00;

    -- Validate Loan Existence
    SELECT COUNT(*) INTO v_loan_exists 
    FROM `LOAN` 
    WHERE `loan_id` = p_loan_id;

    IF v_loan_exists = 0 THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Error: Requested loan_id does not exist.';
    END IF;

    -- 1. Total principal and interest repaid from the transaction ledger
    SELECT COALESCE(SUM(`amount_paid`), 0.00) INTO v_total_paid
    FROM `REPAYMENT`
    WHERE `loan_id` = p_loan_id;

    -- 2. Aggregate installment counts
    SELECT 
        COUNT(*),
        COALESCE(SUM(CASE WHEN `status` = 'OVERDUE' THEN 1 ELSE 0 END), 0),
        COALESCE(SUM(CASE WHEN `status` = 'PAID' THEN 1 ELSE 0 END), 0)
    INTO 
        v_total_emis, 
        v_overdue_count, 
        v_paid_count
    FROM `EMI_SCHEDULE`
    WHERE `loan_id` = p_loan_id;

    -- 3. Total outstanding obligations across all pending, overdue, and partial installments
    SELECT COALESCE(SUM(`emi_amount` + `penalty_amount`), 0.00) INTO v_total_outstanding
    FROM `EMI_SCHEDULE`
    WHERE `loan_id` = p_loan_id AND `status` != 'PAID';

    -- 4. Next upcoming unpaid EMI details
    SELECT `due_date`, (`emi_amount` + `penalty_amount`)
    INTO v_next_due_date, v_next_due_amount
    FROM `EMI_SCHEDULE`
    WHERE `loan_id` = p_loan_id AND `status` IN ('PENDING', 'OVERDUE', 'PARTIALLY_PAID')
    ORDER BY `due_date` ASC
    LIMIT 1;

    -- 5. Return Master Summary Result Set
    SELECT 
        l.`loan_id`,
        a.`name` AS `applicant_name`,
        a.`pan_no` AS `applicant_pan`,
        lp.`name` AS `product_name`,
        lp.`product_type`,
        l.`principal_amount`,
        l.`interest_rate` AS `annual_interest_rate_pct`,
        l.`tenure_months`,
        l.`emi_amount` AS `monthly_emi`,
        l.`total_payable`,
        v_total_paid AS `total_paid`,
        v_total_outstanding AS `total_outstanding`,
        v_total_emis AS `total_installments`,
        v_paid_count AS `paid_installments`,
        v_overdue_count AS `overdue_count`,
        (v_total_emis - v_paid_count) AS `remaining_installments`,
        v_next_due_date AS `next_due_date`,
        v_next_due_amount AS `next_due_amount`,
        l.`status` AS `loan_status`,
        l.`disbursement_date`,
        l.`maturity_date`
    FROM `LOAN` l
    JOIN `APPLICANT` a ON l.`applicant_id` = a.`applicant_id`
    JOIN `LOAN_PRODUCT` lp ON l.`product_id` = lp.`product_id`
    WHERE l.`loan_id` = p_loan_id;

END proc_label$$

DELIMITER ;


-- ============================================================================
-- VERIFICATION & TEST CALL SUITE
-- ============================================================================
-- The following SQL block inserts foundational test data (if not already seeded)
-- and executes test calls covering all stored procedures and triggers.
-- ============================================================================

-- Step A: Insert Seed Test Records if absent
INSERT INTO `APPLICANT` (`applicant_id`, `name`, `email`, `phone`, `address`, `dob`, `pan_no`, `aadhaar_no`, `annual_income`, `credit_score`, `employment_type`, `employer_name`)
VALUES (1, 'Rohan Verma', 'rohan.verma@example.com', '+919876543210', 'Flat 402, Shivalik Heights, MG Road, Bengaluru, Karnataka', '1992-05-15', 'ABCDE1234F', '123456789012', 1200000.00, 780, 'SALARIED', 'Infosys Ltd')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

INSERT INTO `LOAN_PRODUCT` (`product_id`, `name`, `product_type`, `interest_rate`, `min_amount`, `max_amount`, `min_tenure_months`, `max_tenure_months`, `processing_fee_pct`, `penalty_rate_pct`, `description`)
VALUES (1, 'SBI Express Personal Loan', 'PERSONAL', 10.50, 25000.00, 2000000.00, 6, 60, 1.50, 2.00, 'SBI retail pre-approved instant personal loan scheme')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

INSERT INTO `GUARANTOR` (`guarantor_id`, `name`, `phone`, `pan_no`, `relationship`, `annual_income`, `address`)
VALUES (1, 'Sunil Verma', '+919876500001', 'FGHIJ5678K', 'FATHER', 1500000.00, 'House 12, Civil Lines, Kanpur, Uttar Pradesh')
ON DUPLICATE KEY UPDATE `name` = VALUES(`name`);

-- Insert a sanctioned test loan: Principal = INR 1,00,000, 10.50% interest, 12 months tenure
INSERT INTO `LOAN` (`loan_id`, `applicant_id`, `product_id`, `guarantor_id`, `principal_amount`, `interest_rate`, `tenure_months`, `emi_amount`, `total_payable`, `disbursement_date`, `maturity_date`, `status`, `approved_by`, `remarks`)
VALUES (1, 1, 1, 1, 100000.00, 10.50, 12, 8814.86, 105778.32, '2025-01-01', '2026-01-01', 'APPROVED', 'BRANCH_MANAGER_01', 'Sanctioned via automated credit bureau scoring')
ON DUPLICATE KEY UPDATE `status` = 'APPROVED';

-- Step B: TEST CALL 1 — Generate EMI Schedule
-- Formula Calculation Verification:
--   P = 100,000, r = 10.5 / 12 / 100 = 0.00875, n = 12
--   (1+r)^12 = 1.11020345
--   EMI = 100000 * 0.00875 * 1.11020345 / (1.11020345 - 1) = INR 8,814.86
CALL generate_emi_schedule(1);

/*
EXPECTED OUTPUT (generate_emi_schedule):
+---------+------------------+-------------------+---------------+-------------+---------------+---------------+---------------------------------------+
| loan_id | principal_amount | interest_rate_pct | tenure_months | monthly_emi | total_payable | maturity_date | message                               |
+---------+------------------+-------------------+---------------+-------------+---------------+---------------+---------------------------------------+
|       1 |        100000.00 |             10.50 |            12 |     8814.86 |     105778.32 | 2026-01-01    | EMI Schedule Generated Successfully   |
+---------+------------------+-------------------+---------------+-------------+---------------+---------------+---------------------------------------+
*/

-- Step C: TEST CALL 2 — Inspect Loan Summary
CALL get_loan_summary(1);

/*
EXPECTED OUTPUT (get_loan_summary):
+---------+----------------+---------------+--------------------------+--------------+------------------+---------------------------+---------------+-------------+---------------+------------+-------------------+--------------------+-------------------+---------------+-----------------------+---------------+-----------------+-------------+-------------------+---------------+
| loan_id | applicant_name | applicant_pan | product_name             | product_type | principal_amount | annual_interest_rate_pct  | tenure_months | monthly_emi | total_payable | total_paid | total_outstanding | total_installments | paid_installments | overdue_count | remaining_installments| next_due_date | next_due_amount | loan_status | disbursement_date | maturity_date |
+---------+----------------+---------------+--------------------------+--------------+------------------+---------------------------+---------------+-------------+---------------+------------+-------------------+--------------------+-------------------+---------------+-----------------------+---------------+-----------------+-------------+-------------------+---------------+
|       1 | Rohan Verma    | ABCDE1234F    | SBI Express Personal Loan| PERSONAL     |        100000.00 |                     10.50 |            12 |     8814.86 |     105778.32 |       0.00 |         105778.32 |                 12 |                 0 |             0 |                    12 | 2025-02-01    |         8814.86 | ACTIVE      | 2025-01-01        | 2026-01-01    |
+---------+----------------+---------------+--------------------------+--------------+------------------+---------------------------+---------------+-------------+---------------+------------+-------------------+--------------------+-------------------+---------------+-----------------------+---------------+-----------------+-------------+-------------------+---------------+
*/

-- Step D: TEST CALL 3 — Process Repayment for Installment #1
-- Fetches first installment ID for Loan 1 and processes on-time repayment
SET @first_emi_id = (SELECT `emi_id` FROM `EMI_SCHEDULE` WHERE `loan_id` = 1 AND `installment_no` = 1);
CALL process_repayment(@first_emi_id, 8814.86, 'UPI', 'UPI/20250201/SBI99120');

/*
EXPECTED OUTPUT (process_repayment):
+--------+---------+----------------+-------------+--------------------+--------------------+-------------+----------------------------------+
| emi_id | loan_id | installment_no | amount_paid | late_fee_assessed  | installment_status | loan_status | message                          |
+--------+---------+----------------+-------------+--------------------+--------------------+-------------+----------------------------------+
|      1 |       1 |              1 |     8814.86 |               0.00 | PAID               | ACTIVE      | Repayment Processed Successfully |
+--------+---------+----------------+-------------+--------------------+--------------------+-------------+----------------------------------+
*/

-- Step E: TEST CALL 4 — Simulate Overdue Installments & Test Batch Job + Triggers
-- We simulate past due dates for installments 2, 3, and 4 to test trigger cascade
UPDATE `EMI_SCHEDULE`
SET `due_date` = DATE_SUB(CURDATE(), INTERVAL 60 DAY)
WHERE `loan_id` = 1 AND `installment_no` IN (2, 3, 4);

-- Execute cursor-driven batch overdue scanner
CALL mark_overdue_emis();

/*
EXPECTED OUTPUT (mark_overdue_emis):
+-------------------------------------------------------------------------------------------------+
| batch_status                                                                                    |
+-------------------------------------------------------------------------------------------------+
| Batch Overdue Job Complete. Successfully scanned and marked 3 installment(s) as OVERDUE.       |
+-------------------------------------------------------------------------------------------------+

OBSERVATION & TRIGGER VERIFICATION:
1. `mark_overdue_emis()` iterated over installments 2, 3, and 4.
2. `trg_mark_overdue` (BEFORE UPDATE) confirmed `due_date < CURDATE()` and kept/set status = 'OVERDUE'.
3. On the 3rd overdue installment, `trg_check_default` (AFTER UPDATE) detected count >= 3.
4. `trg_check_default` automatically executed `UPDATE LOAN SET status = 'DEFAULTED'`.
5. `trg_loan_audit` (AFTER UPDATE ON LOAN) automatically logged:
   old_value = 'ACTIVE' -> new_value = 'DEFAULTED'.
6. `trg_check_default` automatically inserted a row into `DEFAULT_LOG`.
*/

-- Step F: Query Verification of Automated Trigger Cascade
SELECT `loan_id`, `status`, `remarks` FROM `LOAN` WHERE `loan_id` = 1;
SELECT `default_id`, `loan_id`, `default_date`, `outstanding_amount`, `months_overdue`, `action_taken`, `resolved` FROM `DEFAULT_LOG` WHERE `loan_id` = 1;
SELECT `audit_id`, `loan_id`, `field_changed`, `old_value`, `new_value`, `changed_at`, `changed_by` FROM `LOAN_AUDIT` WHERE `loan_id` = 1;

/*
EXPECTED OUTPUT (Trigger Verification Queries):

1. LOAN status verification:
+---------+-----------+----------------------------------------------------------------------------------------------------------+
| loan_id | status    | remarks                                                                                                  |
+---------+-----------+----------------------------------------------------------------------------------------------------------+
|       1 | DEFAULTED | Sanctioned via automated credit bureau scoring [DEFAULTED: Overdue count reached 3 on 2026-10-05]        |
+---------+-----------+----------------------------------------------------------------------------------------------------------+

2. DEFAULT_LOG verification:
+------------+---------+--------------+--------------------+----------------+--------------+----------+
| default_id | loan_id | default_date | outstanding_amount | months_overdue | action_taken | resolved |
+------------+---------+--------------+--------------------+----------------+--------------+----------+
|          1 |       1 | 2026-10-05   |           96963.46 |              3 | NOTICE_SENT  |        0 |
+------------+---------+--------------+--------------------+----------------+--------------+----------+

3. LOAN_AUDIT verification:
+----------+---------+---------------+-----------+-----------+---------------------+------------+
| audit_id | loan_id | field_changed | old_value | new_value | changed_at          | changed_by |
+----------+---------+---------------+-----------+-----------+---------------------+------------+
|        1 |       1 | status        | APPROVED  | ACTIVE    | 2026-10-05 09:40:00 | SYSTEM     |
|        2 |       1 | status        | ACTIVE    | DEFAULTED | 2026-10-05 09:40:02 | SYSTEM     |
+----------+---------+---------------+-----------+-----------+---------------------+------------+
*/
