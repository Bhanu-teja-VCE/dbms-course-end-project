-- -----------------------------------------------------------------------------
-- CampusSwap - STAGE 7: Indexes and Concurrency Control
-- -----------------------------------------------------------------------------
USE campusswap;

-- =============================================================================
-- PART A: B+ Tree Indexes
-- =============================================================================

/*
WHAT IS A B+ TREE INDEX?
A B+ tree index is a balanced tree data structure used by databases to quickly 
locate data without scanning every row. In a B+ tree:
- Leaf nodes store the actual index keys and pointers to the corresponding table rows.
- Internal (non-leaf) nodes act as signposts guiding the search to the correct leaf.

WHY INNODB USES B+ TREES BY DEFAULT:
InnoDB uses B+ trees because they offer predictable, logarithmic search times (O(log n)).
They are highly optimized for disk I/O, allowing range queries (like BETWEEN, >, <) 
to be executed very efficiently since leaf nodes are linked in a sorted sequence.

WHEN TO ADD AN INDEX:
- On columns frequently used in WHERE clauses (e.g., searching by category).
- On columns used in JOIN conditions (e.g., foreign keys).
- On columns used for sorting (ORDER BY) or grouping (GROUP BY).
- On columns where exact matches or prefix searches (LIKE 'prefix%') are common.

WHEN NOT TO ADD AN INDEX:
- On very small tables (a full table scan might be faster than reading the index).
- On columns with very few distinct values (low cardinality, e.g., gender, boolean flags).
- On tables with heavy write operations (INSERT/UPDATE/DELETE), as indexes must be maintained.
*/

-- -----------------------------------------------------------------------------
-- 2. EXPLAIN ON QUERIES BEFORE ADDING INDEXES
-- -----------------------------------------------------------------------------
/*
Before indexing, MySQL has to read every single row in the table to find matches.
This is called a FULL TABLE SCAN (type=ALL in the EXPLAIN output). 
With thousands of listings, this becomes a performance bottleneck.
*/

-- Query A: Search listings by title (LIKE with prefix)
EXPLAIN SELECT * FROM LISTING WHERE title LIKE 'Data%';

-- Query B: Filter listings by category and status
EXPLAIN SELECT * FROM LISTING WHERE category_id = 3 AND status = 'ACTIVE';

-- -----------------------------------------------------------------------------
-- 3. CREATE THE INDEXES
-- -----------------------------------------------------------------------------
/*
idx_listing_title is a single-column index. It helps with exact matches and 
prefix searches (like our 'Data%' query).

idx_listing_cat_status is a COMPOSITE index (multiple columns). 
Because of the "Leftmost Prefix Rule", this index will speed up queries that filter:
- By category_id alone
- By category_id AND status together
It will NOT help queries that filter by status alone, as status is not the leftmost column.
*/
CREATE INDEX idx_listing_title ON LISTING(title);
CREATE INDEX idx_listing_cat_status ON LISTING(category_id, status);

-- -----------------------------------------------------------------------------
-- 4. EXPLAIN ON THE SAME QUERIES AFTER ADDING INDEXES
-- -----------------------------------------------------------------------------
/*
After adding the indexes, if we run the EXPLAIN queries again, we will see:
- The 'type' changes from 'ALL' (full scan) to 'ref' or 'range'.
- The 'possible_keys' and 'key' columns will show our new indexes.
- The 'rows' scanned drops dramatically, meaning MySQL does much less work.
*/
EXPLAIN SELECT * FROM LISTING WHERE title LIKE 'Data%';
EXPLAIN SELECT * FROM LISTING WHERE category_id = 3 AND status = 'ACTIVE';

-- -----------------------------------------------------------------------------
-- 5. MORE USEFUL INDEXES FOR CAMPUSSWAP
-- -----------------------------------------------------------------------------

-- Speeds up finding all orders placed by a specific student (buyer)
CREATE INDEX idx_orders_buyer ON ORDERS(buyer_id);

-- Speeds up retrieving all reviews for a specific listing when viewing its page
CREATE INDEX idx_review_listing ON REVIEW(listing_id);

-- Speeds up queries sorting listings by newest first (common on home page)
CREATE INDEX idx_listing_created ON LISTING(created_at);


-- =============================================================================
-- PART B: Concurrency Control — Preventing Overselling
-- =============================================================================

/*
WHAT IS A RACE CONDITION?
A race condition occurs when multiple transactions try to read and modify the 
same data at exactly the same time, leading to inconsistent results.
In CampusSwap, if two students try to buy the last available textbook simultaneously,
both might see quantity=1, both proceed, and quantity becomes -1 (overselling).

WHAT DOES SELECT ... FOR UPDATE DO?
It places an exclusive (X) lock on the rows returned by the SELECT statement.
Other transactions trying to read those rows with FOR UPDATE (or modify them) 
will be blocked and forced to wait until the current transaction commits or rolls back.

WHAT IS A DEADLOCK?
A deadlock happens when two or more transactions hold locks and are waiting 
for each other to release locks, creating a circular dependency. Neither can proceed.
*/

-- -----------------------------------------------------------------------------
-- 7. SIMULATION: HOW "SELECT ... FOR UPDATE" PREVENTS OVERSELLING
-- -----------------------------------------------------------------------------
/*
To test this, you would open two separate MySQL terminal windows (sessions).
Follow the steps in order:
*/

-- Setup: Make sure listing 1 has exactly 1 quantity available
UPDATE LISTING SET quantity = 1, status = 'ACTIVE' WHERE listing_id = 1;

-- ===== SESSION 1 (Terminal 1) =====
-- START TRANSACTION;
-- -- Lock the row: no other transaction can modify it until we COMMIT
-- SELECT listing_id, title, quantity FROM LISTING WHERE listing_id = 1 FOR UPDATE;
-- -- Session 1 sees quantity = 1, proceeds to buy
-- -- (Simulate some processing time — switch to Session 2 now)

-- ===== SESSION 2 (Terminal 2) =====
-- START TRANSACTION;
-- -- Try to read the same row with FOR UPDATE
-- SELECT listing_id, title, quantity FROM LISTING WHERE listing_id = 1 FOR UPDATE;
-- -- ⏳ SESSION 2 BLOCKS HERE — it waits because Session 1 holds the lock

-- ===== BACK TO SESSION 1 (Terminal 1) =====
-- -- Session 1 completes the purchase
-- UPDATE LISTING SET quantity = quantity - 1 WHERE listing_id = 1;
-- COMMIT;
-- -- Session 1 releases the lock

-- ===== SESSION 2 UNBLOCKS (Terminal 2) =====
-- -- Now Session 2's SELECT FOR UPDATE returns — but quantity is now 0!
-- -- Session 2 checks quantity in its application code: it's 0, so the item is sold out.
-- -- Session 2 should ROLLBACK instead of buying
-- ROLLBACK;

-- -----------------------------------------------------------------------------
-- 8. DEADLOCK SCENARIO EXPLANATION
-- -----------------------------------------------------------------------------
/*
Deadlock scenario in CampusSwap (e.g., buying a bundle of items):
Session A: locks listing_id = 1, then tries to lock listing_id = 2
Session B: locks listing_id = 2, then tries to lock listing_id = 1

Both sessions wait forever. MySQL detects this circular wait graph and 
automatically kills one session (rolls it back) with the error:
"Deadlock found when trying to get lock; try restarting transaction"

Prevention Strategy:
Always acquire locks in a consistent, predefined order. For example, 
if buying multiple items, always lock the rows ordered by listing_id ASC.
*/

-- -----------------------------------------------------------------------------
-- 9. LOCK WAIT TIMEOUT
-- -----------------------------------------------------------------------------
-- How long will Session 2 wait for Session 1 before giving up?
SHOW VARIABLES LIKE 'innodb_lock_wait_timeout';
-- Default is usually 50 seconds. After this, the blocked transaction gets an error.
