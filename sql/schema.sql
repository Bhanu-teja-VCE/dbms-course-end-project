-- ============================================================================
-- Bank Loan Management System: EMI Processing, Repayment Tracking, and Risk Assessment
-- Database Management Systems — Course Project (B.Tech CSE)
-- Database Engine : MySQL 8.0+ (InnoDB Storage Engine)
-- Character Set   : utf8mb4 (Unicode Support)
-- Collation       : utf8mb4_unicode_ci
-- Execution       : mysql -u <username> -p < schema.sql
-- ============================================================================
-- WHY MySQL 8.0 & InnoDB?
-- 1. Full CHECK Constraint enforcement: MySQL 8.0+ parses AND strictly enforces
--    CHECK constraints (unlike MySQL 5.7 which parsed but ignored them).
-- 2. InnoDB Storage Engine: Provides ACID-compliant transactions, robust row-level
--    locking, foreign key constraint enforcement, and crash recovery.
-- 3. High Precision Arithmetic: Uses standard DECIMAL types for monetary and
--    interest computations to prevent IEEE 754 floating-point rounding errors.
-- ============================================================================

DROP DATABASE IF EXISTS `bank_loan_db`;
CREATE DATABASE `bank_loan_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `bank_loan_db`;

-- ============================================================================
-- 1. APPLICANT TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Represents individual borrowers registered in the banking system.
-- Stores official Indian KYC identifiers (PAN card, Aadhaar card).
--
-- KEY CHOICES:
-- - `applicant_id`: Surrogate integer primary key with AUTO_INCREMENT for
--   efficient B-Tree index traversal and joining performance.
-- - `email`, `pan_no`, `aadhaar_no`: Alternate candidate keys enforced via UNIQUE
--   constraints to guarantee deduplication and one-to-one customer mapping.
-- - `credit_score`: Enforced via CHECK constraint within the standard CIBIL/RBI
--   bureau scoring range [300, 900].
-- - `annual_income`: Enforced non-negative to maintain realistic financial profiles.
-- ============================================================================

CREATE TABLE `APPLICANT` (
    `applicant_id`      INT             AUTO_INCREMENT,
    `name`              VARCHAR(100)    NOT NULL,
    `email`             VARCHAR(150)    NOT NULL,
    `phone`             VARCHAR(15)     NOT NULL,
    `address`           TEXT            NOT NULL,
    `dob`               DATE            NOT NULL,
    `pan_no`            VARCHAR(10)     NOT NULL,
    `aadhaar_no`        VARCHAR(12)     NOT NULL,
    `annual_income`     DECIMAL(12, 2)  NOT NULL,
    `credit_score`      INT             NOT NULL,
    `employment_type`   ENUM('SALARIED', 'SELF_EMPLOYED', 'BUSINESS', 'RETIRED', 'STUDENT') NOT NULL,
    `employer_name`     VARCHAR(150)    DEFAULT NULL,
    `created_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Primary Key Constraint
    CONSTRAINT `pk_applicant` 
        PRIMARY KEY (`applicant_id`),

    -- Unique Identification Constraints (KYC Deduplication)
    CONSTRAINT `uq_applicant_email` 
        UNIQUE (`email`),
    CONSTRAINT `uq_applicant_pan` 
        UNIQUE (`pan_no`),
    CONSTRAINT `uq_applicant_aadhaar` 
        UNIQUE (`aadhaar_no`),

    -- Domain & Business Rule Constraints
    CONSTRAINT `chk_applicant_income` 
        CHECK (`annual_income` >= 0),
    CONSTRAINT `chk_applicant_credit_score` 
        CHECK (`credit_score` BETWEEN 300 AND 900),
    CONSTRAINT `chk_applicant_pan_len` 
        CHECK (CHAR_LENGTH(`pan_no`) = 10),
    CONSTRAINT `chk_applicant_aadhaar_len` 
        CHECK (CHAR_LENGTH(`aadhaar_no`) = 12)
) ENGINE=InnoDB COMMENT='Registered loan applicants and KYC financial profile';


-- ============================================================================
-- 2. LOAN_PRODUCT TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Master catalog of loan offerings (SBI-style retail and commercial schemes).
-- Defines base interest rate, permissible borrowing limits, tenure boundaries,
-- and fee structures.
--
-- KEY CHOICES:
-- - `product_type`: Categorized by standardized credit portfolios (HOME, PERSONAL,
--   VEHICLE, EDUCATION, BUSINESS, GOLD, AGRICULTURE).
-- - `interest_rate`: Annual base interest percentage (e.g., 8.50% p.a.). Must be > 0.
-- - Boundary Checks: Table-level CHECK constraints verify `max_amount >= min_amount`
--   and `max_tenure_months >= min_tenure_months` to guarantee logical interval ranges.
-- - `processing_fee_pct` & `penalty_rate_pct`: Percentage fees capped in [0, 100].
-- ============================================================================

CREATE TABLE `LOAN_PRODUCT` (
    `product_id`            INT             AUTO_INCREMENT,
    `name`                  VARCHAR(100)    NOT NULL,
    `product_type`          ENUM('HOME', 'PERSONAL', 'VEHICLE', 'EDUCATION', 'BUSINESS', 'GOLD', 'AGRICULTURE') NOT NULL,
    `interest_rate`         DECIMAL(5, 2)   NOT NULL,
    `min_amount`            DECIMAL(12, 2)  NOT NULL,
    `max_amount`            DECIMAL(12, 2)  NOT NULL,
    `min_tenure_months`     INT             NOT NULL,
    `max_tenure_months`     INT             NOT NULL,
    `processing_fee_pct`    DECIMAL(4, 2)   NOT NULL DEFAULT 0.00,
    `penalty_rate_pct`      DECIMAL(4, 2)   NOT NULL DEFAULT 0.00,
    `description`           TEXT            DEFAULT NULL,

    -- Primary Key Constraint
    CONSTRAINT `pk_loan_product` 
        PRIMARY KEY (`product_id`),

    -- Domain & Range Validation Constraints
    CONSTRAINT `chk_lp_interest_rate` 
        CHECK (`interest_rate` > 0),
    CONSTRAINT `chk_lp_min_amount` 
        CHECK (`min_amount` > 0),
    CONSTRAINT `chk_lp_amount_range` 
        CHECK (`max_amount` >= `min_amount`),
    CONSTRAINT `chk_lp_min_tenure` 
        CHECK (`min_tenure_months` > 0),
    CONSTRAINT `chk_lp_tenure_range` 
        CHECK (`max_tenure_months` >= `min_tenure_months`),
    CONSTRAINT `chk_lp_processing_fee` 
        CHECK (`processing_fee_pct` >= 0 AND `processing_fee_pct` <= 100),
    CONSTRAINT `chk_lp_penalty_rate` 
        CHECK (`penalty_rate_pct` >= 0 AND `penalty_rate_pct` <= 100)
) ENGINE=InnoDB COMMENT='Loan catalog defining terms, interest rates, and tenure limits';


-- ============================================================================
-- 3. GUARANTOR TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Co-signers or financial guarantors who provide secondary repayment security.
-- Often mandatory for high-value loans (Education, High-Ticket Personal, Business).
--
-- KEY CHOICES:
-- - `guarantor_id`: Surrogate primary key.
-- - `pan_no`: Standard 10-character PAN string for tax/KYC tracking.
-- - `annual_income`: Must be >= 0 to assess guarantor creditworthiness.
-- - `relationship`: Qualitative bond to the applicant (e.g., FATHER, SPOUSE, FRIEND).
-- ============================================================================

CREATE TABLE `GUARANTOR` (
    `guarantor_id`      INT             AUTO_INCREMENT,
    `name`              VARCHAR(100)    NOT NULL,
    `phone`             VARCHAR(15)     NOT NULL,
    `pan_no`            VARCHAR(10)     NOT NULL,
    `relationship`      VARCHAR(50)     NOT NULL,
    `annual_income`     DECIMAL(12, 2)  NOT NULL,
    `address`           TEXT            NOT NULL,

    -- Primary Key Constraint
    CONSTRAINT `pk_guarantor` 
        PRIMARY KEY (`guarantor_id`),

    -- Domain Constraints
    CONSTRAINT `chk_guarantor_income` 
        CHECK (`annual_income` >= 0),
    CONSTRAINT `chk_guarantor_pan_len` 
        CHECK (CHAR_LENGTH(`pan_no`) = 10)
) ENGINE=InnoDB COMMENT='Guarantors co-signing loan obligations';


-- ============================================================================
-- 4. LOAN TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Core transactional entity connecting APPLICANT, LOAN_PRODUCT, and optional
-- GUARANTOR. Captures the sanctioned loan contract terms and lifecycle state.
--
-- REFERENTIAL INTEGRITY ACTIONS:
-- - `ON DELETE RESTRICT` for `APPLICANT`: Prevents accidental deletion of a customer
--   who has an existing loan contract. Safeguards banking audit records.
-- - `ON DELETE RESTRICT` for `LOAN_PRODUCT`: Disallows deletion of active product
--   categories that have live or historical loan commitments.
-- - `ON DELETE SET NULL` for `GUARANTOR`: If a guarantor profile is removed or
--   unlinked, the loan contract remains valid with guarantor_id set to NULL.
--
-- FINANCIAL SANITY CONSTRAINTS:
-- - `principal_amount > 0`
-- - `interest_rate > 0`
-- - `tenure_months > 0`
-- - `emi_amount > 0`
-- - `total_payable >= principal_amount` (Guarantees interest cannot be negative).
-- ============================================================================

CREATE TABLE `LOAN` (
    `loan_id`           INT             AUTO_INCREMENT,
    `applicant_id`      INT             NOT NULL,
    `product_id`        INT             NOT NULL,
    `guarantor_id`      INT             DEFAULT NULL,
    `principal_amount`  DECIMAL(12, 2)  NOT NULL,
    `interest_rate`     DECIMAL(5, 2)   NOT NULL,
    `tenure_months`     INT             NOT NULL,
    `emi_amount`        DECIMAL(10, 2)  NOT NULL,
    `total_payable`     DECIMAL(12, 2)  NOT NULL,
    `disbursement_date` DATE            DEFAULT NULL,
    `maturity_date`     DATE            DEFAULT NULL,
    `status`            ENUM('PENDING', 'APPROVED', 'ACTIVE', 'CLOSED', 'DEFAULTED', 'REJECTED') NOT NULL DEFAULT 'PENDING',
    `approved_by`       VARCHAR(100)    DEFAULT NULL,
    `remarks`           TEXT            DEFAULT NULL,
    `created_at`        DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,

    -- Primary Key Constraint
    CONSTRAINT `pk_loan` 
        PRIMARY KEY (`loan_id`),

    -- Foreign Key Constraints & Referential Actions
    CONSTRAINT `fk_loan_applicant` 
        FOREIGN KEY (`applicant_id`) 
        REFERENCES `APPLICANT`(`applicant_id`) 
        ON DELETE RESTRICT 
        ON UPDATE CASCADE,

    CONSTRAINT `fk_loan_product` 
        FOREIGN KEY (`product_id`) 
        REFERENCES `LOAN_PRODUCT`(`product_id`) 
        ON DELETE RESTRICT 
        ON UPDATE CASCADE,

    CONSTRAINT `fk_loan_guarantor` 
        FOREIGN KEY (`guarantor_id`) 
        REFERENCES `GUARANTOR`(`guarantor_id`) 
        ON DELETE SET NULL 
        ON UPDATE CASCADE,

    -- Financial Integrity Constraints
    CONSTRAINT `chk_loan_principal` 
        CHECK (`principal_amount` > 0),
    CONSTRAINT `chk_loan_interest` 
        CHECK (`interest_rate` > 0),
    CONSTRAINT `chk_loan_tenure` 
        CHECK (`tenure_months` > 0),
    CONSTRAINT `chk_loan_emi` 
        CHECK (`emi_amount` > 0),
    CONSTRAINT `chk_loan_total_payable` 
        CHECK (`total_payable` >= `principal_amount`)
) ENGINE=InnoDB COMMENT='Sanctioned loan contracts and lifecycle states';


-- ============================================================================
-- 5. EMI_SCHEDULE TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Amortization schedule generated upon loan sanctioning or disbursement.
-- Breaks down each monthly installment into principal component and interest
-- component using standard reducing balance amortization.
--
-- EMI FORMULA:
--   EMI = P * r * (1 + r)^n / ((1 + r)^n - 1)
--   where P = principal_amount, r = monthly interest rate (annual / 12 / 100),
--         n = tenure_months.
--
-- KEY INTEGRITY RULES:
-- - `UNIQUE(loan_id, installment_no)`: Prevents duplicate installment sequence
--   numbers for the same loan contract.
-- - `ON DELETE CASCADE` from `LOAN`: If a loan application is dropped or cleaned
--   up prior to booking, its associated calculated schedule is purged atomically.
-- - `balance_after >= 0`: The remaining principal balance can never be negative.
-- ============================================================================

CREATE TABLE `EMI_SCHEDULE` (
    `emi_id`                INT             AUTO_INCREMENT,
    `loan_id`               INT             NOT NULL,
    `installment_no`        INT             NOT NULL,
    `due_date`              DATE            NOT NULL,
    `principal_component`   DECIMAL(10, 2)  NOT NULL,
    `interest_component`    DECIMAL(10, 2)  NOT NULL,
    `emi_amount`            DECIMAL(10, 2)  NOT NULL,
    `balance_after`         DECIMAL(12, 2)  NOT NULL,
    `status`                ENUM('PENDING', 'PAID', 'OVERDUE', 'PARTIALLY_PAID') NOT NULL DEFAULT 'PENDING',
    `paid_date`             DATE            DEFAULT NULL,
    `penalty_amount`        DECIMAL(10, 2)  NOT NULL DEFAULT 0.00,

    -- Primary Key Constraint
    CONSTRAINT `pk_emi_schedule` 
        PRIMARY KEY (`emi_id`),

    -- Composite Uniqueness: One unique installment sequence per loan
    CONSTRAINT `uq_loan_installment` 
        UNIQUE (`loan_id`, `installment_no`),

    -- Foreign Key Constraint & Referential Action
    CONSTRAINT `fk_emi_loan` 
        FOREIGN KEY (`loan_id`) 
        REFERENCES `LOAN`(`loan_id`) 
        ON DELETE CASCADE 
        ON UPDATE CASCADE,

    -- Integrity & Non-negativity Constraints
    CONSTRAINT `chk_emi_installment_no` 
        CHECK (`installment_no` > 0),
    CONSTRAINT `chk_emi_principal` 
        CHECK (`principal_component` >= 0),
    CONSTRAINT `chk_emi_interest` 
        CHECK (`interest_component` >= 0),
    CONSTRAINT `chk_emi_amount` 
        CHECK (`emi_amount` > 0),
    CONSTRAINT `chk_emi_balance` 
        CHECK (`balance_after` >= 0),
    CONSTRAINT `chk_emi_penalty` 
        CHECK (`penalty_amount` >= 0)
) ENGINE=InnoDB COMMENT='Monthly installment breakdown and amortization schedule';


-- ============================================================================
-- 6. REPAYMENT TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Records actual monetary transactions made by borrowers against specific EMIs.
--
-- KEY INTEGRITY RULES:
-- - `transaction_ref UNIQUE`: Prevents replay attacks and double-crediting
--   by enforcing global uniqueness of payment gateway / bank UTR references.
-- - `amount_paid CHECK (> 0)`: Every recorded payment must represent a positive cashflow.
-- - `late_fee CHECK (>= 0)`: Accrued delay penalty assessed during overdue clearance.
-- - `ON DELETE RESTRICT` on `emi_id` and `loan_id`: Under RBI banking compliance,
--   financial transaction records must never be deleted while parent loan/EMI
--   records exist. Maintains an unassailable financial ledger.
-- ============================================================================

CREATE TABLE `REPAYMENT` (
    `repayment_id`      INT             AUTO_INCREMENT,
    `emi_id`            INT             NOT NULL,
    `loan_id`           INT             NOT NULL,
    `amount_paid`       DECIMAL(10, 2)  NOT NULL,
    `payment_date`      DATETIME        NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `payment_mode`      ENUM('CASH', 'CHEQUE', 'NEFT', 'UPI', 'AUTO_DEBIT') NOT NULL,
    `transaction_ref`   VARCHAR(100)    NOT NULL,
    `late_fee`          DECIMAL(10, 2)  NOT NULL DEFAULT 0.00,
    `remarks`           VARCHAR(255)    DEFAULT NULL,

    -- Primary Key Constraint
    CONSTRAINT `pk_repayment` 
        PRIMARY KEY (`repayment_id`),

    -- Unique Financial Transaction Reference
    CONSTRAINT `uq_repayment_txn` 
        UNIQUE (`transaction_ref`),

    -- Foreign Key Constraints & Strict Retention Referential Actions
    CONSTRAINT `fk_repayment_emi` 
        FOREIGN KEY (`emi_id`) 
        REFERENCES `EMI_SCHEDULE`(`emi_id`) 
        ON DELETE RESTRICT 
        ON UPDATE CASCADE,

    CONSTRAINT `fk_repayment_loan` 
        FOREIGN KEY (`loan_id`) 
        REFERENCES `LOAN`(`loan_id`) 
        ON DELETE RESTRICT 
        ON UPDATE CASCADE,

    -- Financial Range Validations
    CONSTRAINT `chk_repayment_amount` 
        CHECK (`amount_paid` > 0),
    CONSTRAINT `chk_repayment_late_fee` 
        CHECK (`late_fee` >= 0)
) ENGINE=InnoDB COMMENT='Real-time repayment transactions and settlement ledger';


-- ============================================================================
-- 7. DEFAULT_LOG TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Tracks Non-Performing Assets (NPAs) and persistent payment defaults.
-- In Indian banking regulations (RBI guidelines), an account overdue for > 90 days
-- transitions into an NPA.
--
-- KEY ATTRIBUTES:
-- - `months_overdue`: Number of consecutive overdue cycles (CHECK >= 1).
-- - `action_taken`: Formal bank recovery stage (NOTICE_SENT, LEGAL_ACTION,
--   RECOVERY_AGENT, WRITE_OFF, RESTRUCTURED).
-- - `resolved`: Boolean flag indicating whether default has been cured/settled.
-- - `ON DELETE RESTRICT`: Default history cannot be purged if the loan entity exists.
-- ============================================================================

CREATE TABLE `DEFAULT_LOG` (
    `default_id`            INT             AUTO_INCREMENT,
    `loan_id`               INT             NOT NULL,
    `default_date`          DATE            NOT NULL,
    `outstanding_amount`    DECIMAL(12, 2)  NOT NULL,
    `months_overdue`        INT             NOT NULL,
    `action_taken`          ENUM('NOTICE_SENT', 'LEGAL_ACTION', 'RECOVERY_AGENT', 'WRITE_OFF', 'RESTRUCTURED') NOT NULL DEFAULT 'NOTICE_SENT',
    `resolved`              BOOLEAN         NOT NULL DEFAULT FALSE,
    `resolution_date`       DATE            DEFAULT NULL,
    `remarks`               TEXT            DEFAULT NULL,

    -- Primary Key Constraint
    CONSTRAINT `pk_default_log` 
        PRIMARY KEY (`default_id`),

    -- Foreign Key Constraint
    CONSTRAINT `fk_default_loan` 
        FOREIGN KEY (`loan_id`) 
        REFERENCES `LOAN`(`loan_id`) 
        ON DELETE RESTRICT 
        ON UPDATE CASCADE,

    -- Domain Validations
    CONSTRAINT `chk_default_outstanding` 
        CHECK (`outstanding_amount` >= 0),
    CONSTRAINT `chk_default_months` 
        CHECK (`months_overdue` >= 1)
) ENGINE=InnoDB COMMENT='NPA monitoring and default escalation log';


-- ============================================================================
-- 8. LOAN_AUDIT TABLE
-- ============================================================================
-- DESIGN DECISION:
-- Immutable audit log capturing all state transitions, approvals, disbursements,
-- and interest rate adjustments made to loans.
--
-- KEY ATTRIBUTES:
-- - `field_changed`: The column or parameter modified (e.g., 'status', 'interest_rate').
-- - `old_value` / `new_value`: Historical before-and-after values for forensic analysis.
-- - `changed_at`: Timestamp automatically recorded upon change.
-- - `changed_by`: User or system actor triggering the change (DEFAULT 'SYSTEM').
-- - `ON DELETE CASCADE`: If a loan application is pruned during testing or staging,
--   its associated audit entries are removed in tandem.
-- ============================================================================

CREATE TABLE `LOAN_AUDIT` (
    `audit_id`          INT             AUTO_INCREMENT,
    `loan_id`           INT             NOT NULL,
    `field_changed`     VARCHAR(50)     NOT NULL,
    `old_value`         TEXT            DEFAULT NULL,
    `new_value`         TEXT            DEFAULT NULL,
    `changed_at`        TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    `changed_by`        VARCHAR(100)    NOT NULL DEFAULT 'SYSTEM',

    -- Primary Key Constraint
    CONSTRAINT `pk_loan_audit` 
        PRIMARY KEY (`audit_id`),

    -- Foreign Key Constraint
    CONSTRAINT `fk_audit_loan` 
        FOREIGN KEY (`loan_id`) 
        REFERENCES `LOAN`(`loan_id`) 
        ON DELETE CASCADE 
        ON UPDATE CASCADE
) ENGINE=InnoDB COMMENT='Audit trail capturing loan modifications and state transitions';

-- ============================================================================
-- SCHEMA CREATION COMPLETE
-- All 8 tables successfully defined with InnoDB, Primary Keys, Foreign Keys,
-- CHECK constraints, and UNIQUE constraints.
-- ============================================================================
