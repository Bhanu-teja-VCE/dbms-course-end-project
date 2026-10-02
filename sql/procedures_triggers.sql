USE campusswap;

-- ==========================================
-- STAGE 6: PROCEDURES, TRIGGERS, TRANSACTIONS
-- ==========================================

DELIMITER $$

-- ============================================================================
-- 1. PROCEDURE: place_order
-- Demonstrates an ACID Transaction
-- ============================================================================
-- Atomicity: Either all steps (insert order, update listing, insert payment) succeed, or none do.
-- Consistency: The database remains in a valid state (e.g., listing quantity doesn't go below 0).
-- Isolation: Concurrent executions won't interfere with each other (MySQL handles row locks on updated rows).
-- Durability: Once COMMIT is reached, the transaction is saved permanently even if a crash occurs right after.
-- ============================================================================
DROP PROCEDURE IF EXISTS place_order$$
CREATE PROCEDURE place_order(IN p_buyer_id INT, IN p_listing_id INT, IN p_qty INT, IN p_method VARCHAR(20))
BEGIN
    -- Variables for internal logic
    DECLARE v_buyer_exists INT DEFAULT 0;
    DECLARE v_listing_status VARCHAR(20);
    DECLARE v_listing_qty INT;
    DECLARE v_listing_price DECIMAL(10,2);
    DECLARE v_seller_id INT;
    DECLARE v_order_id INT;
    DECLARE v_total_amount DECIMAL(10,2);
    
    -- a. DECLARE EXIT HANDLER FOR SQLEXCEPTION to ROLLBACK on any failure
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        -- If any error occurs, undo all changes made in this transaction
        ROLLBACK;
        SELECT 'Transaction Failed. Rolled back changes.' AS Status;
    END;

    -- b. START TRANSACTION
    START TRANSACTION;

    -- c. Check if buyer exists in BUYER table, if not signal error
    SELECT COUNT(*) INTO v_buyer_exists FROM BUYER WHERE buyer_id = p_buyer_id;
    IF v_buyer_exists = 0 THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Buyer does not exist.';
    END IF;

    -- d. Check if listing exists, is ACTIVE, and has sufficient quantity
    SELECT status, quantity, price, seller_id 
    INTO v_listing_status, v_listing_qty, v_listing_price, v_seller_id
    FROM LISTING 
    WHERE listing_id = p_listing_id;

    IF v_listing_status IS NULL OR v_listing_status != 'ACTIVE' THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Listing is not ACTIVE or does not exist.';
    END IF;

    IF v_listing_qty < p_qty THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Insufficient listing quantity.';
    END IF;

    -- e. Calculate total amount
    SET v_total_amount = v_listing_price * p_qty;

    -- f. INSERT into ORDERS
    INSERT INTO ORDERS (buyer_id, order_date, total_amount, status)
    VALUES (p_buyer_id, NOW(), v_total_amount, 'CONFIRMED');

    -- g. Get LAST_INSERT_ID() for the new order_id
    SET v_order_id = LAST_INSERT_ID();

    -- h. INSERT into ORDER_ITEM
    INSERT INTO ORDER_ITEM (order_id, listing_id, quantity, price_at_purchase)
    VALUES (v_order_id, p_listing_id, p_qty, v_listing_price);

    -- i. UPDATE LISTING (Decrement quantity)
    UPDATE LISTING 
    SET quantity = quantity - p_qty
    WHERE listing_id = p_listing_id;

    -- j. INSERT into PAYMENT
    INSERT INTO PAYMENT (order_id, amount, method, status, paid_at)
    VALUES (v_order_id, v_total_amount, p_method, 'COMPLETED', NOW());

    -- k. UPDATE SELLER total_sales
    UPDATE SELLER 
    SET total_sales = IFNULL(total_sales, 0) + v_total_amount
    WHERE seller_id = v_seller_id;

    -- l. COMMIT the transaction (make it Durable)
    COMMIT;
    
    SELECT 'Transaction Successful. Order placed.' AS Status, v_order_id AS Order_ID;
END$$


-- ============================================================================
-- 2. TRIGGER: trg_listing_sold_out
-- Automatically updates listing status to 'SOLD' when quantity hits 0.
-- Explanation: Triggers run automatically on database events (INSERT, UPDATE, DELETE).
-- This keeps business logic in the DB layer, so application code doesn't have 
-- to explicitly check and update the status every time quantity changes.
-- ============================================================================
DROP TRIGGER IF EXISTS trg_listing_sold_out$$
-- Note: MySQL requires a BEFORE UPDATE trigger if we are modifying the row being updated.
-- An AFTER UPDATE trigger on the same table would cause recursive loop errors in MySQL.
CREATE TRIGGER trg_listing_sold_out
BEFORE UPDATE ON LISTING
FOR EACH ROW
BEGIN
    IF NEW.quantity = 0 AND OLD.quantity > 0 THEN
        SET NEW.status = 'SOLD';
    END IF;
END$$


-- ============================================================================
-- 3. TRIGGER: trg_update_seller_rating
-- Recalculates the seller's avg_rating when a new review is added.
-- ============================================================================
DROP TRIGGER IF EXISTS trg_update_seller_rating$$
CREATE TRIGGER trg_update_seller_rating
AFTER INSERT ON REVIEW
FOR EACH ROW
BEGIN
    DECLARE v_seller_id INT;
    
    -- Get seller_id from the listing being reviewed
    SELECT seller_id INTO v_seller_id 
    FROM LISTING 
    WHERE listing_id = NEW.listing_id;
    
    -- Recalculate the seller's avg_rating
    UPDATE SELLER 
    SET avg_rating = (
        SELECT AVG(rating) 
        FROM REVIEW r
        JOIN LISTING l ON r.listing_id = l.listing_id
        WHERE l.seller_id = v_seller_id
    )
    WHERE seller_id = v_seller_id;
END$$


-- ============================================================================
-- 4. TRIGGER: trg_price_audit
-- Records an audit log when a listing price is changed.
-- ============================================================================
DROP TRIGGER IF EXISTS trg_price_audit$$
CREATE TRIGGER trg_price_audit
BEFORE UPDATE ON LISTING
FOR EACH ROW
BEGIN
    -- Only fire when the price actually changes
    IF OLD.price <> NEW.price THEN
        INSERT INTO PRICE_AUDIT (listing_id, old_price, new_price, changed_by, changed_at)
        VALUES (OLD.listing_id, OLD.price, NEW.price, NEW.seller_id, NOW());
    END IF;
END$$


-- ============================================================================
-- 5. PROCEDURE: get_seller_report
-- Generates a single result set summary for a given seller.
-- ============================================================================
DROP PROCEDURE IF EXISTS get_seller_report$$
CREATE PROCEDURE get_seller_report(IN p_seller_id INT)
BEGIN
    SELECT 
        u.name AS seller_name,
        COUNT(l.listing_id) AS total_listings,
        SUM(CASE WHEN l.status = 'ACTIVE' THEN 1 ELSE 0 END) AS active_listings,
        SUM(CASE WHEN l.status = 'SOLD' THEN 1 ELSE 0 END) AS sold_listings,
        IFNULL(s.total_sales, 0) AS total_revenue,
        IFNULL(s.avg_rating, 0) AS average_rating,
        MAX(l.created_at) AS latest_listing_date
    FROM `USER` u
    JOIN SELLER s ON u.user_id = s.seller_id
    LEFT JOIN LISTING l ON s.seller_id = l.seller_id
    WHERE u.user_id = p_seller_id
    GROUP BY u.user_id, u.name, s.total_sales, s.avg_rating;
END$$


-- ============================================================================
-- 6. PROCEDURE: mark_expired_listings
-- Demonstrates iterating over a result set using a CURSOR.
-- ============================================================================
DROP PROCEDURE IF EXISTS mark_expired_listings$$
CREATE PROCEDURE mark_expired_listings()
BEGIN
    -- Explanation: A cursor is used to loop through a set of rows returned by a query,
    -- allowing us to process each row individually in procedural logic.
    -- While a single UPDATE statement is usually more efficient, cursors are useful
    -- when complex per-row business logic is required (demonstrated here for syllabus).
    
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_listing_id INT;
    DECLARE v_count INT DEFAULT 0;
    
    -- Declare the cursor for active listings older than 60 days
    DECLARE cur_listings CURSOR FOR 
        SELECT listing_id FROM LISTING 
        WHERE status = 'ACTIVE' AND created_at < NOW() - INTERVAL 60 DAY;
        
    -- DECLARE CONTINUE HANDLER FOR NOT FOUND to exit loop
    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;
    
    OPEN cur_listings;
    
    read_loop: LOOP
        FETCH cur_listings INTO v_listing_id;
        
        -- If no more rows, exit loop
        IF v_done THEN
            LEAVE read_loop;
        END IF;
        
        -- Update the specific row
        UPDATE LISTING 
        SET status = 'EXPIRED' 
        WHERE listing_id = v_listing_id;
        
        SET v_count = v_count + 1;
    END LOOP;
    
    CLOSE cur_listings;
    
    SELECT CONCAT(v_count, ' listings marked as expired') AS Result;
END$$

DELIMITER ;


-- ============================================================================
-- 7. TEST CALLS
-- ============================================================================

-- Test place_order: buy listing 1, qty 1, pay by UPI
-- CALL place_order(1, 1, 1, 'UPI');
-- Expected: new row in ORDERS, ORDER_ITEM, PAYMENT; listing qty decremented

-- Test place_order with invalid listing (should fail gracefully)
-- CALL place_order(1, 99999, 1, 'UPI');
-- Expected: error message, no changes

-- Test get_seller_report
-- CALL get_seller_report(1);
-- Expected: seller 1's dashboard data

-- Test mark_expired_listings
-- CALL mark_expired_listings();
-- Expected: count of expired listings
