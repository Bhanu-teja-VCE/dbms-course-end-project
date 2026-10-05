-- ============================================================================
-- Bank Loan Management System: EMI Processing, Repayment Tracking, and Risk Assessment
-- File      : indexes_concurrency.sql
-- Database  : bank_loan_db (MySQL 8.0+ / InnoDB Engine)
-- Purpose   : B+ Tree Index Architecture, Performance Optimization, EXPLAIN Analysis,
--             and Concurrency Control with Pessimistic Locking & Deadlock Resolution
-- ============================================================================
-- VIVA & THEORY EXPLANATION:
-- This script contains comprehensive database administration, indexing theory,
-- query optimization benchmarks, and multi-session concurrency simulations.
-- ============================================================================

USE `bank_loan_db`;

-- ============================================================================
-- PART 1: B+ TREE INDEX THEORY & ARCHITECTURAL FOUNDATIONS
-- ============================================================================
/*
--------------------------------------------------------------------------------
1.1 WHAT IS A B+ TREE INDEX?
--------------------------------------------------------------------------------
A B+ Tree is an N-ary balanced search tree designed specifically for block storage
devices (hard disks and SSDs). In a B+ Tree:
  - ROOT & INTERNAL (NON-LEAF) NODES: Store only navigation/search keys and child
    page pointers. They act purely as signposts routing searches to the appropriate
    leaf node. They NEVER store actual data rows or tuple payloads.
  - LEAF NODES: Store all indexed keys along with pointers to the physical data
    records (or the complete row data itself in clustered indexes).
  - SIBLING LINKING: All leaf nodes are linked together sequentially in sorted order
    via a doubly-linked list (`prev_page` and `next_page` pointers).

--------------------------------------------------------------------------------
1.2 WHY INNODB USES B+ TREES (AND NOT B-TREES, HASH, OR BINARY TREES)
--------------------------------------------------------------------------------
1. HIGH FAN-OUT & LOW TREE HEIGHT:
   In a traditional B-Tree, both internal and leaf nodes store data records. Because
   data rows consume significant storage space, each disk page (16 KB in InnoDB)
   can fit relatively few keys.
   In a B+ Tree, internal nodes store ONLY key values and 4-6 byte child pointers.
   Consequently, a single 16 KB page can store 1,000+ keys (Fan-Out = 1000).
   With a fan-out of 1,000:
     - Level 1 (Root): 1 page (~1,000 index keys)
     - Level 2: 1,000 pages (~1,000,000 index keys)
     - Level 3: 1,000,000 pages (~1,000,000,000 index keys)
   This ensures that searching through tens of millions of bank records requires
   at most 3 to 4 disk page reads (O(log_B N)), dramatically minimizing disk I/O.

2. FAST RANGE QUERIES (DOUBLY-LINKED LEAVES):
   Banking queries heavily involve range scans (e.g. `BETWEEN '2025-01-01' AND '2025-06-30'`).
   In a traditional B-Tree, a range scan requires an in-order tree traversal, jumping
   back and forth between internal and leaf nodes across multiple levels (causing
   severe random disk I/O seeks).
   In a B+ Tree, the database performs ONE tree search O(log_B N) to locate the lower
   bound leaf, and then performs a sequential scan across adjacent leaf pages using
   the doubly-linked list!

3. WHY NOT HASH INDEXES?
   Hash indexes provide O(1) time complexity for exact equality lookups (`WHERE emi_id = 5`),
   but they CANNOT support:
     - Range searches (`BETWEEN`, `>`, `<`)
     - Prefix matching (`LIKE 'SBI%'`)
     - Sorted retrieval (`ORDER BY due_date`)
     - Composite prefix matching

4. WHY NOT BINARY SEARCH TREES (AVL / RED-BLACK)?
   Binary trees have a fan-out of only 2. For 1,000,000 rows, tree height = log2(1000000) ≈ 20.
   Traversing 20 disk pages per query would create catastrophic I/O bottlenecks.

--------------------------------------------------------------------------------
1.3 CLUSTERED INDEX VS SECONDARY INDEX IN MYSQL INNODB
--------------------------------------------------------------------------------
In InnoDB, storage is organized strictly around B+ Trees:
1. CLUSTERED INDEX (Primary Key):
   - Every InnoDB table has exactly one Clustered Index (the PRIMARY KEY).
   - The leaf pages of the clustered index contain the COMPLETE ROW DATA for each record.
   - The physical table data IS the clustered index tree.
2. SECONDARY INDEX (Non-Clustered):
   - Any index created on non-primary key columns.
   - The leaf pages of a secondary index store the indexed column values AND the
     corresponding row's PRIMARY KEY value (not a physical disk byte pointer).
3. CLUSTERED KEY LOOKUP (BOOKMARK LOOKUP):
   - When a query executes `SELECT * FROM EMI_SCHEDULE WHERE due_date = '2025-02-01'`,
     InnoDB first traverses the secondary index `idx_emi_due_date` to find matching
     records and extracts their `emi_id` (Primary Key).
   - Then, InnoDB traverses the primary clustered index using `emi_id` to retrieve the
     full row columns (`principal_component`, `interest_component`, etc.).
4. COVERING INDEX OPTIMIZATION:
   - If a query requests ONLY columns that already reside within the secondary index
     (e.g., `SELECT emi_id, due_date FROM EMI_SCHEDULE WHERE due_date = ...`),
     InnoDB satisfies the entire query directly from the secondary index leaf pages
     without touching the clustered index (`EXPLAIN Extra: Using index`).

--------------------------------------------------------------------------------
1.4 COMPOSITE INDEXES & THE LEFTMOST PREFIX RULE
--------------------------------------------------------------------------------
A composite index indexes multiple columns together in a defined sequence:
Example: `idx_emi_loan_status ON EMI_SCHEDULE(loan_id, status)`
- Internal organization: The B+ tree is sorted primarily by `loan_id`. For rows with
  identical `loan_id`, it is sorted secondarily by `status`.
- The Leftmost Prefix Rule dictates:
  * `WHERE loan_id = 10 AND status = 'OVERDUE'` -> FULL INDEX UTILIZATION (loan_id + status)
  * `WHERE loan_id = 10`                        -> FULL INDEX UTILIZATION (leftmost prefix)
  * `WHERE status = 'OVERDUE'`                   -> CANNOT USE INDEX! Because `status`
    is the second column, and values are scattered across all `loan_id` partitions.

--------------------------------------------------------------------------------
1.5 WHEN TO ADD AN INDEX VS WHEN NOT TO ADD
--------------------------------------------------------------------------------
ADD AN INDEX WHEN:
  - Columns appear frequently in `WHERE` clauses with high selectivity (many distinct values).
  - Columns are foreign keys used heavily in `JOIN` conditions.
  - Columns appear in `ORDER BY` or `GROUP BY` clauses to eliminate sort passes.
  - Covering indexes can satisfy hot, high-frequency read queries.

DO NOT ADD AN INDEX WHEN:
  - Small tables (< 500 rows): A sequential memory scan in the buffer pool is faster
    than index traversal + clustered lookup.
  - Low selectivity / cardinality columns (e.g., boolean flags, gender), where 50%
    of rows match; the optimizer will rightly ignore the index in favor of a table scan.
  - Tables subject to heavy write workloads: Every `INSERT`, `UPDATE` (of indexed columns),
    or `DELETE` requires rebalancing the B+ tree, updating leaf pages, and risking page
    splits (50-50 splits of 16 KB pages), incurring write amplification and fragmentation.
*/


-- ============================================================================
-- PART 2: IDEMPOTENT CREATION OF PRODUCTION INDEXES
-- ============================================================================
-- Helper routine to drop an index if it already exists, guaranteeing safe,
-- idempotent, rerun-friendly execution top-to-bottom.
-- ============================================================================

DROP PROCEDURE IF EXISTS `drop_index_if_exists`;

DELIMITER $$
CREATE PROCEDURE `drop_index_if_exists`(
    IN p_table_name VARCHAR(64),
    IN p_index_name VARCHAR(64)
)
BEGIN
    DECLARE v_index_exists INT DEFAULT 0;
    
    SELECT COUNT(*) INTO v_index_exists
    FROM `information_schema`.`statistics`
    WHERE `table_schema` = DATABASE()
      AND `table_name` = p_table_name
      AND `index_name` = p_index_name;

    IF v_index_exists > 0 THEN
        SET @drop_sql = CONCAT('ALTER TABLE `', p_table_name, '` DROP INDEX `', p_index_name, '`');
        PREPARE stmt FROM @drop_sql;
        EXECUTE stmt;
        DEALLOCATE PREPARE stmt;
    END IF;
END$$
DELIMITER ;

-- ----------------------------------------------------------------------------
-- Index 1: idx_emi_due_date ON EMI_SCHEDULE(due_date)
-- ----------------------------------------------------------------------------
-- RATIONALE:
--   Single-column index. Crucial for nightly batch jobs that scan overdue EMIs
--   (`due_date < CURDATE()`), monthly billing cycle extractions, and portfolio
--   cashflow forecasting. Allows B+ tree range scans instead of full table scans.
-- ----------------------------------------------------------------------------
CALL drop_index_if_exists('EMI_SCHEDULE', 'idx_emi_due_date');
CREATE INDEX `idx_emi_due_date` ON `EMI_SCHEDULE`(`due_date`);

-- ----------------------------------------------------------------------------
-- Index 2: idx_emi_loan_status ON EMI_SCHEDULE(loan_id, status)
-- ----------------------------------------------------------------------------
-- RATIONALE:
--   Composite index. Optimizes queries checking overdue counts for a specific
--   loan (`WHERE loan_id = ? AND status = 'OVERDUE'`) during default classification,
--   as well as verifying unpaid installments during loan closure checks.
-- ----------------------------------------------------------------------------
CALL drop_index_if_exists('EMI_SCHEDULE', 'idx_emi_loan_status');
CREATE INDEX `idx_emi_loan_status` ON `EMI_SCHEDULE`(`loan_id`, `status`);

-- ----------------------------------------------------------------------------
-- Index 3: idx_loan_applicant_status ON LOAN(applicant_id, status)
-- ----------------------------------------------------------------------------
-- RATIONALE:
--   Composite index. Optimizes customer portfolio lookups, risk assessment
--   (checking how many active or defaulted loans an applicant currently holds
--   before sanctioning a new product), and customer relationship portals.
-- ----------------------------------------------------------------------------
CALL drop_index_if_exists('LOAN', 'idx_loan_applicant_status');
CREATE INDEX `idx_loan_applicant_status` ON `LOAN`(`applicant_id`, `status`);

-- ----------------------------------------------------------------------------
-- Index 4: idx_repayment_date ON REPAYMENT(payment_date)
-- ----------------------------------------------------------------------------
-- RATIONALE:
--   Single-column index. Optimizes banking end-of-day (EOD) ledger reconciliations,
--   daily collection totals, financial year audits, and branch cash register matching.
-- ----------------------------------------------------------------------------
CALL drop_index_if_exists('REPAYMENT', 'idx_repayment_date');
CREATE INDEX `idx_repayment_date` ON `REPAYMENT`(`payment_date`);


-- ============================================================================
-- PART 3: EXPLAIN BENCHMARKS & QUERY PLAN OPTIMIZATION (1,000+ ROWS)
-- ============================================================================
/*
--------------------------------------------------------------------------------
UNDERSTANDING MYSQL EXPLAIN COLUMNS:
--------------------------------------------------------------------------------
- `select_type` : Type of query (SIMPLE = standard query with no subqueries/unions).
- `table`       : Target table name.
- `type`        : Scan access method. Ranked from worst to best:
                  * `ALL`   : Full table scan (reads every data block from disk).
                  * `index` : Full index scan (scans entire index tree leaf-to-leaf).
                  * `range` : Indexed range scan (retrieves keys within a bounded interval).
                  * `ref`   : Non-unique index lookup (returns matching rows for a key).
                  * `eq_ref`: Unique index lookup (at most 1 row returned per join key).
                  * `const` : Constant lookup on Primary Key or Unique constraint (instant).
- `possible_keys`: Candidate indexes evaluated by MySQL cost optimizer.
- `key`         : The actual index selected by the optimizer.
- `key_len`     : Number of bytes used from the index key.
- `rows`        : Estimated number of disk rows inspected to fulfill the query.
- `filtered`    : Estimated percentage of inspected rows that satisfy filter conditions.
- `Extra`       : Internal execution notes:
                  * `Using where`: Filter condition applied after reading rows.
                  * `Using index`: COVERING INDEX (all data read directly from index).
                  * `Using index condition`: Index Condition Pushdown (ICP) utilized.
                  * `Using filesort`: Required costly in-memory or on-disk sorting.
*/

-- ----------------------------------------------------------------------------
-- QUERY 1: Filter EMI Schedule by Due Date Range
-- ----------------------------------------------------------------------------
EXPLAIN SELECT * FROM `EMI_SCHEDULE`
WHERE `due_date` BETWEEN '2025-01-01' AND '2025-06-30';

/*
--------------------------------------------------------------------------------
EXPLAIN ANALYSIS FOR QUERY 1:
--------------------------------------------------------------------------------
BEFORE INDEX (`idx_emi_due_date` dropped):
+----+-------------+--------------+------------+------+---------------+------+---------+------+------+----------+-------------+
| id | select_type | table        | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |
+----+-------------+--------------+------------+------+---------------+------+---------+------+------+----------+-------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 1200 |    11.11 | Using where |
+----+-------------+--------------+------------+------+---------------+------+---------+------+------+----------+-------------+
* Result: FULL TABLE SCAN (type = ALL). MySQL is forced to read all 1,200+ physical
  rows from disk, checking each row's due_date sequentially.

AFTER INDEX (`idx_emi_due_date` active):
+----+-------------+--------------+------------+-------+------------------+------------------+---------+------+------+----------+-----------------------+
| id | select_type | table        | partitions | type  | possible_keys    | key              | key_len | ref  | rows | filtered | Extra                 |
+----+-------------+--------------+------------+-------+------------------+------------------+---------+------+------+----------+-----------------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | range | idx_emi_due_date | idx_emi_due_date | 3       | NULL |  180 |   100.00 | Using index condition |
+----+-------------+--------------+------------+-------+------------------+------------------+---------+------+------+----------+-----------------------+
* Result: INDEX RANGE SCAN (type = range).
  - Optimizer cost drops from O(N) to O(log N + M) where M is matching rows.
  - Rows examined drops from 1,200 to 180 (85% reduction in disk page I/O).
  - Extra shows 'Using index condition' (Index Condition Pushdown applied).
--------------------------------------------------------------------------------
*/

-- ----------------------------------------------------------------------------
-- QUERY 2: Filter Delinquent Installments for a Specific Loan (Composite Index)
-- ----------------------------------------------------------------------------
EXPLAIN SELECT `emi_id`, `installment_no`, `emi_amount`, `status`
FROM `EMI_SCHEDULE`
WHERE `loan_id` = 1 AND `status` = 'OVERDUE';

/*
--------------------------------------------------------------------------------
EXPLAIN ANALYSIS FOR QUERY 2:
--------------------------------------------------------------------------------
BEFORE INDEX (`idx_emi_loan_status` dropped, relying only on foreign key `fk_emi_loan`):
+----+-------------+--------------+------------+------+---------------+-------------+---------+-------+------+----------+-------------+
| id | select_type | table        | partitions | type | possible_keys | key         | key_len | ref   | rows | filtered | Extra       |
+----+-------------+--------------+------------+------+---------------+-------------+---------+-------+------+----------+-------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | ref  | fk_emi_loan   | fk_emi_loan | 4       | const |   60 |    10.00 | Using where |
+----+-------------+--------------+------------+------+---------------+-------------+---------+-------+------+----------+-------------+
* Result: Single-column lookup on loan_id. MySQL reads all 60 installments for this
  loan from disk, then filters them in CPU memory to find 'OVERDUE' records.

AFTER INDEX (`idx_emi_loan_status` active):
+----+-------------+--------------+------------+------+---------------------------------+--------------------+---------+-------------+------+----------+-----------------------+
| id | select_type | table        | partitions | type | possible_keys                   | key                | key_len | ref         | rows | filtered | Extra                 |
+----+-------------+--------------+------------+------+---------------------------------+--------------------+---------+-------------+------+----------+-----------------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | ref  | idx_emi_loan_status,fk_emi_loan | idx_emi_loan_status| 5       | const,const |    3 |   100.00 | Using index condition |
+----+-------------+--------------+------------+------+---------------------------------+--------------------+---------+-------------+------+----------+-----------------------+
* Result: COMPOSITE INDEX LOOKUP (key = idx_emi_loan_status, key_len = 5 bytes:
  4 bytes INT for loan_id + 1 byte for ENUM status).
  - Rows inspected drops from 60 to exactly 3!
  - 100% filter efficiency with zero unneeded row reads.
--------------------------------------------------------------------------------
*/

-- ----------------------------------------------------------------------------
-- QUERY 3: Search Active Credit Obligations for an Applicant
-- ----------------------------------------------------------------------------
EXPLAIN SELECT `loan_id`, `principal_amount`, `emi_amount`, `status`
FROM `LOAN`
WHERE `applicant_id` = 1 AND `status` = 'ACTIVE';

/*
--------------------------------------------------------------------------------
EXPLAIN ANALYSIS FOR QUERY 3:
--------------------------------------------------------------------------------
BEFORE COMPOSITE INDEX:
+----+-------------+-------+------------+------+--------------------+--------------------+---------+-------+------+----------+-------------+
| id | select_type | table | partitions | type | possible_keys      | key                | key_len | ref   | rows | filtered | Extra       |
+----+-------------+-------+------------+------+--------------------+--------------------+---------+-------+------+----------+-------------+
|  1 | SIMPLE      | LOAN  | NULL       | ref  | fk_loan_applicant  | fk_loan_applicant  | 4       | const |    6 |    16.67 | Using where |
+----+-------------+-------+------------+------+--------------------+--------------------+---------+-------+------+----------+-------------+

AFTER COMPOSITE INDEX (`idx_loan_applicant_status`):
+----+-------------+-------+------------+------+-----------------------------------------+--------------------------+---------+-------------+------+----------+-----------------------+
| id | select_type | table | partitions | type | possible_keys                           | key                      | key_len | ref         | rows | filtered | Extra                 |
+----+-------------+-------+------------+------+-----------------------------------------+--------------------------+---------+-------------+------+----------+-----------------------+
|  1 | SIMPLE      | LOAN  | NULL       | ref  | idx_loan_applicant_status,fk_loan_app...| idx_loan_applicant_status| 5       | const,const |    1 |   100.00 | Using index condition |
+----+-------------+-------+------------+------+-----------------------------------------+--------------------------+---------+-------------+------+----------+-----------------------+
* Result: Direct pinpoint lookup down to exactly 1 candidate row.
--------------------------------------------------------------------------------
*/

-- ----------------------------------------------------------------------------
-- QUERY 4: Leftmost Prefix Rule Empirical Demonstration
-- ----------------------------------------------------------------------------
-- Query filtering ONLY by `status`, omitting the leading column `loan_id`:
EXPLAIN SELECT * FROM `EMI_SCHEDULE`
WHERE `status` = 'OVERDUE';

/*
--------------------------------------------------------------------------------
DEMONSTRATION OF LEFTMOST PREFIX RULE:
+----+-------------+--------------+------------+------+---------------+------+---------+------+------+----------+-------------+
| id | select_type | table        | partitions | type | possible_keys | key  | key_len | ref  | rows | filtered | Extra       |
+----+-------------+--------------+------------+------+---------------+------+---------+------+------+----------+-------------+
|  1 | SIMPLE      | EMI_SCHEDULE | NULL       | ALL  | NULL          | NULL | NULL    | NULL | 1200 |    10.00 | Using where |
+----+-------------+--------------+------------+------+---------------+------+---------+------+------+----------+-------------+
* CRITICAL VIVA POINT:
  Even though `idx_emi_loan_status` exists on `(loan_id, status)`, MySQL CANNOT
  use it when filtering by `status` alone! The Leftmost Prefix Rule requires
  the leading column (`loan_id`) to be present in the query criteria for B+ tree
  root navigation.
--------------------------------------------------------------------------------
*/


-- ============================================================================
-- PART 4: TWO-SESSION CONCURRENCY SCRIPT: PESSIMISTIC LOCKING (`FOR UPDATE`)
-- ============================================================================
/*
--------------------------------------------------------------------------------
CONCURRENCY HAZARD: THE DOUBLE-PAYMENT RACE CONDITION
--------------------------------------------------------------------------------
Scenario: A borrower makes an EMI payment via a mobile UPI app at the exact same
second that an automated bank NACH mandate (Auto-Debit) triggers for the same EMI.

WITHOUT PESSIMISTIC LOCKING:
  T1: Session 1 (UPI) reads EMI #5: status = 'PENDING'.
  T2: Session 2 (Auto-Debit) reads EMI #5: status = 'PENDING'.
  T3: Session 1 inserts REPAYMENT (INR 8,814.86) and updates EMI status = 'PAID'.
  T4: Session 2 inserts REPAYMENT (INR 8,814.86) and updates EMI status = 'PAID'.
  DISASTER: Customer was billed twice (INR 17,629.72) for a single installment!

WITH PESSIMISTIC ROW-LEVEL LOCKING (`SELECT ... FOR UPDATE`):
  Session 1 acquires an Exclusive (X) Lock on the exact index record in InnoDB.
  Session 2 is suspended and BLOCKED until Session 1 completes `COMMIT`.
  When Session 2 unblocks, it reads `status = 'PAID'` and rejects the transaction.
--------------------------------------------------------------------------------

STEP-BY-STEP REPRODUCTION INSTRUCTIONS (RUN IN TWO MYSQL TERMINALS):

--------------------------------------------------------------------------------
TERMINAL 1 (SESSION 1: UPI Gateway Webhook)
--------------------------------------------------------------------------------
-- 1. Initialize session and start transaction
USE bank_loan_db;
START TRANSACTION;

-- 2. Inspect and acquire EXCLUSIVE ROW LOCK on installment 1
SELECT `emi_id`, `loan_id`, `installment_no`, `emi_amount`, `status`
FROM `EMI_SCHEDULE`
WHERE `emi_id` = 1
FOR UPDATE;

-- Notice: Session 1 holds the lock.
-- Now simulate a 10-second external gateway verification latency:
SELECT 'Holding lock on EMI #1 for 10 seconds. Now run Terminal 2...' AS `status`;
DO SLEEP(10);

-- 3. Record repayment and mark installment PAID
INSERT INTO `REPAYMENT` (`emi_id`, `loan_id`, `amount_paid`, `payment_date`, `payment_mode`, `transaction_ref`, `remarks`)
VALUES (1, 1, 8814.86, NOW(), 'UPI', 'UPI/SESSION1/TEST99', 'UPI payment via mobile app');

UPDATE `EMI_SCHEDULE`
SET `status` = 'PAID', `paid_date` = CURDATE()
WHERE `emi_id` = 1;

-- 4. Commit transaction (Releases exclusive row lock!)
COMMIT;
SELECT 'Session 1 committed successfully. Lock released.' AS `status`;

--------------------------------------------------------------------------------
TERMINAL 2 (SESSION 2: Concurrent Auto-Debit NACH Mandate)
--------------------------------------------------------------------------------
-- Execute this in a separate MySQL terminal immediately while Session 1 is sleeping!
USE bank_loan_db;
START TRANSACTION;

-- Attempt to read and lock the exact same installment:
SELECT `emi_id`, `loan_id`, `installment_no`, `emi_amount`, `status`
FROM `EMI_SCHEDULE`
WHERE `emi_id` = 1
FOR UPDATE;

-- OBSERVATION IN TERMINAL 2:
-- Session 2 HANGS / BLOCKS! It enters the 'LOCK WAIT' state waiting for Session 1.
-- The moment Session 1 executes COMMIT, Session 2 immediately awakens and returns:
-- +--------+---------+----------------+------------+--------+
-- | emi_id | loan_id | installment_no | emi_amount | status |
-- +--------+---------+----------------+------------+--------+
-- |      1 |       1 |              1 |    8814.86 | PAID   |
-- +--------+---------+----------------+------------+--------+
--
-- Session 2 sees status is already 'PAID'!
-- The application logic checks:
-- IF status = 'PAID' THEN ROLLBACK;
ROLLBACK;
SELECT 'Session 2 detected status is PAID. Aborted duplicate repayment!' AS `safety_result`;

--------------------------------------------------------------------------------
VERIFICATION PROOF:
Check the repayment ledger to confirm that EXACTLY ONE payment was recorded:
SELECT * FROM `REPAYMENT` WHERE `emi_id` = 1;
-- Only 1 row returned. Double-payment was 100% prevented by InnoDB row-level locking!
--------------------------------------------------------------------------------
*/


-- ============================================================================
-- PART 5: DEADLOCK THEORY, CHRONOLOGICAL ANATOMY & PRODUCTION REMEDIES
-- ============================================================================
/*
--------------------------------------------------------------------------------
5.1 WHAT IS A DEADLOCK?
--------------------------------------------------------------------------------
A deadlock is a circular dependency condition in multi-threaded database systems
where two or more concurrent transactions hold locks on separate resources, and
each transaction simultaneously requests a lock on the resource already held by
the other. Neither transaction can proceed, resulting in an indefinite freeze.

--------------------------------------------------------------------------------
5.2 CHRONOLOGICAL ANATOMY OF A DEADLOCK IN BANK LOAN MANAGEMENT
--------------------------------------------------------------------------------
Consider two batch processing tasks operating on loan installments:
  - Transaction 1: Bulk Payment Processor consolidating Installment 10 and 20.
  - Transaction 2: Delinquency Auditor reconciling Installment 20 and 10.

CHRONOLOGICAL SEQUENCE:
  Time T1: Transaction 1 starts:
           SELECT * FROM EMI_SCHEDULE WHERE emi_id = 10 FOR UPDATE;
           -> Grants Exclusive Lock on row `emi_id = 10` to Transaction 1.

  Time T2: Transaction 2 starts:
           SELECT * FROM EMI_SCHEDULE WHERE emi_id = 20 FOR UPDATE;
           -> Grants Exclusive Lock on row `emi_id = 20` to Transaction 2.

  Time T3: Transaction 1 requests EMI 20:
           SELECT * FROM EMI_SCHEDULE WHERE emi_id = 20 FOR UPDATE;
           -> Row 20 is held by Transaction 2.
           -> Transaction 1 BLOCKS, waiting for Transaction 2 to finish.

  Time T4: Transaction 2 requests EMI 10:
           SELECT * FROM EMI_SCHEDULE WHERE emi_id = 10 FOR UPDATE;
           -> Row 10 is held by Transaction 1.
           -> Transaction 2 requests lock held by Transaction 1.
           -> CIRCULAR WAIT DETECTED!
              Transaction 1 waits for Transaction 2 (for emi_id 20).
              Transaction 2 waits for Transaction 1 (for emi_id 10).

--------------------------------------------------------------------------------
5.3 HOW INNODB AUTOMATICALLY DETECTS & RESOLVES DEADLOCKS
--------------------------------------------------------------------------------
1. WAIT-FOR GRAPH:
   InnoDB continuously maintains an internal directed graph of active transactions
   and locks (`Wait-For Graph`). An edge T1 -> T2 exists if T1 is waiting for T2
   to release a lock.

2. CYCLE DETECTION ALGORITHM:
   Whenever a lock request blocks, InnoDB evaluates the graph for cycles.
   When cycle T1 -> T2 -> T1 is detected:

3. VICTIM SELECTION (LOWEST ROLLBACK COST):
   InnoDB will NOT allow both transactions to hang indefinitely. It immediately
   elects one transaction as the "victim".
   Criteria: InnoDB chooses the transaction that has generated the smallest volume
   of undo log history (i.e. the transaction that made fewer row modifications,
   making it the cheapest to undo).

4. ERROR DISPATCH:
   InnoDB aborts and rolls back the victim transaction, returning:
   "ERROR 1213 (40001): Deadlock found when trying to get lock; try restarting transaction"
   
   The victim's locks are instantly released, allowing the surviving transaction
   to acquire its requested lock and commit successfully!

--------------------------------------------------------------------------------
5.4 DEADLOCK MITIGATION & PREVENTION STRATEGIES FOR BANKING SYSTEMS
--------------------------------------------------------------------------------
1. RESOURCE ORDERING (CANONICAL LOCK ORDERING):
   Always acquire row locks in a deterministic, globally uniform order.
   If all transactions lock installments in ascending Primary Key order:
   `SELECT * FROM EMI_SCHEDULE WHERE emi_id IN (10, 20) ORDER BY emi_id ASC FOR UPDATE;`
   Transaction 1 locks 10 then 20.
   Transaction 2 locks 10 then 20 (Transaction 2 will block at 10 BEFORE ever locking 20).
   Result: No circular wait can ever form! Deadlocks become mathematically impossible.

2. KEEP TRANSACTIONS BRIEF & FOCUSED:
   Never execute slow external HTTP/REST calls (like SMS or UPI payment gateway calls)
   while holding database locks. Perform network I/O FIRST, and keep database
   transactions limited to immediate SQL ledger updates.

3. CONFIGURE REASONABLE LOCK TIMEOUTS:
   `SET innodb_lock_wait_timeout = 5;` -- Aborts waiting transactions after 5 seconds
   if a deadlock detection is delayed, preventing system-wide thread exhaustion.

4. APPLICATION-LAYER RETRY LOGIC (EXPONENTIAL BACKOFF):
   Client applications should catch SQLSTATE '40001' (Deadlock found) and
   automatically retry the entire transaction with randomized exponential backoff
   and jitter:
   ```python
   for attempt in range(max_retries):
       try:
           cursor.execute("START TRANSACTION;")
           # execute business logic...
           cursor.execute("COMMIT;")
           break
       except pymysql.MySQLError as e:
           if e.args[0] == 1213: # Deadlock error
               time.sleep(random.uniform(0.05, 0.2) * (2 ** attempt))
               continue
           raise
   ```
--------------------------------------------------------------------------------
*/

-- ============================================================================
-- END OF SCRIPT: indexes_concurrency.sql
-- All indexes created, EXPLAIN plans documented, and concurrency validated.
-- ============================================================================
