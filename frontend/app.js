// ============================================================================
// CampusSwap — Frontend Logic
// Powers the listing cards, request cards, and the "How It Works" modal
// that showcases every SQL query, procedure, trigger, and concept used.
// ============================================================================

// ---- SAMPLE DATA (simulates what the database returns) ----
const sampleListings = [
    { id: 1, title: "Data Structures by Tanenbaum, 3rd Ed", price: 350, condition: "GOOD", seller: "Arjun S.", rating: 4.5, icon: "📘", category: "Engineering Books" },
    { id: 2, title: "Casio fx-991EX Scientific Calculator", price: 850, condition: "LIKE_NEW", seller: "Priya M.", rating: 4.8, icon: "🔢", category: "Calculators" },
    { id: 3, title: "SG Cricket Bat — English Willow", price: 2200, condition: "GOOD", seller: "Rohit K.", rating: 4.2, icon: "🏏", category: "Cricket" },
    { id: 4, title: "DBMS by Navathe, 7th Edition", price: 280, condition: "FAIR", seller: "Sneha R.", rating: 3.9, icon: "📗", category: "Engineering Books" },
    { id: 5, title: "JBL Tune 510BT Headphones", price: 1500, condition: "NEW", seller: "Vikram D.", rating: 4.7, icon: "🎧", category: "Electronics" },
    { id: 6, title: "HP 15s Laptop Bag", price: 450, condition: "LIKE_NEW", seller: "Ananya P.", rating: 4.3, icon: "💼", category: "Accessories" },
    { id: 7, title: "Operating Systems by Galvin, 9th Ed", price: 320, condition: "GOOD", seller: "Karthik V.", rating: 4.1, icon: "📕", category: "Engineering Books" },
    { id: 8, title: "Yonex Badminton Racket — Nanoray", price: 1800, condition: "GOOD", seller: "Meera T.", rating: 4.6, icon: "🏸", category: "Badminton" },
];

const sampleRequests = [
    { id: 1, title: "Looking for DBMS by Navathe, any edition", user: "Rahul G.", budget: 300, status: "OPEN", hostel: "Block-C" },
    { id: 2, title: "Need Casio fx-82 calculator for exam", user: "Divya S.", budget: 500, status: "OPEN", hostel: "Girls-Hostel-1" },
    { id: 3, title: "Want study table in good condition", user: "Arun M.", budget: 1500, status: "FULFILLED", hostel: "Block-A" },
    { id: 4, title: "Looking for COA by Morris Mano", user: "Pooja K.", budget: 250, status: "OPEN", hostel: "Girls-Hostel-2" },
    { id: 5, title: "Need badminton shuttle cocks (Mavis 350)", user: "Sanjay R.", budget: 400, status: "OPEN", hostel: "Block-D" },
];

// ---- RENDER LISTING CARDS ----
function renderListings() {
    const grid = document.getElementById('listingsGrid');
    if (!grid) return;

    grid.innerHTML = sampleListings.map(item => `
        <div class="listing-card">
            <div class="listing-image">${item.icon}</div>
            <div class="listing-info">
                <div class="listing-title">${item.title}</div>
                <div class="listing-meta">
                    <span class="listing-price">₹${item.price.toLocaleString('en-IN')}</span>
                    <span class="listing-condition condition-${item.condition.toLowerCase()}">${item.condition.replace('_', ' ')}</span>
                </div>
                <div class="listing-seller">
                    <span class="seller-avatar">${item.seller[0]}</span>
                    ${item.seller} · ${item.category}
                </div>
            </div>
            <div class="listing-footer">
                <span class="listing-rating">⭐ ${item.rating}</span>
                <button class="btn btn-primary btn-small">View</button>
            </div>
        </div>
    `).join('');
}

// ---- RENDER REQUEST CARDS ----
function renderRequests() {
    const list = document.getElementById('requestsList');
    if (!list) return;

    list.innerHTML = sampleRequests.map(req => `
        <div class="request-card">
            <span class="request-status status-${req.status.toLowerCase()}">${req.status}</span>
            <div class="request-info">
                <div class="request-title">${req.title}</div>
                <div class="request-detail">${req.user} · ${req.hostel}</div>
            </div>
            <span class="request-budget">≤ ₹${req.budget.toLocaleString('en-IN')}</span>
        </div>
    `).join('');
}

// ---- HOW IT WORKS — SQL CONTENT FOR EACH TAB ----
const howItWorksContent = {
    schema: `
        <h3>📐 Database Schema — 12 Tables</h3>
        <p>The schema uses <strong>MySQL 8.0</strong> with InnoDB engine for ACID transactions and foreign key support. Here's the core structure:</p>

        <div class="concept-box">
            <p><strong>Design Decision:</strong> We use overlapping, partial specialization for USER → SELLER/BUYER. A student can be both (sells old books, buys a calculator). Not everyone is either (new users just browsing).</p>
        </div>

        <span class="sql-label">USER TABLE — The Foundation</span>
        <pre><code class="language-sql">CREATE TABLE \`USER\` (
    user_id       INT AUTO_INCREMENT,
    name          VARCHAR(100) NOT NULL,
    email         VARCHAR(150) NOT NULL,
    phone         VARCHAR(15),
    hostel_block  VARCHAR(20),
    room_no       VARCHAR(10),
    joined_at     DATETIME DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user       PRIMARY KEY (user_id),
    CONSTRAINT uq_user_email UNIQUE (email)
    -- UNIQUE prevents duplicate registrations
) ENGINE=InnoDB;</code></pre>

        <span class="sql-label">LISTING TABLE — Items for Sale</span>
        <pre><code class="language-sql">CREATE TABLE LISTING (
    listing_id   INT AUTO_INCREMENT,
    seller_id    INT NOT NULL,
    category_id  INT NOT NULL,
    title        VARCHAR(200) NOT NULL,
    price        DECIMAL(10,2) NOT NULL,
    quantity     INT NOT NULL DEFAULT 1,
    \`condition\`  ENUM('NEW','LIKE_NEW','GOOD','FAIR','POOR'),
    status       ENUM('ACTIVE','SOLD','EXPIRED','REMOVED'),

    PRIMARY KEY (listing_id),
    FOREIGN KEY (seller_id) REFERENCES SELLER(seller_id) ON DELETE CASCADE,
    FOREIGN KEY (category_id) REFERENCES CATEGORY(category_id) ON DELETE RESTRICT,
    CHECK (price > 0),  -- No free listings by accident
    CHECK (quantity >= 0)
);</code></pre>

        <div class="concept-box">
            <p><strong>Why DECIMAL, not FLOAT?</strong> FLOAT has rounding errors (0.1 + 0.2 ≠ 0.3 in floating point). DECIMAL stores exact values — critical for money. Try it: <code>SELECT 0.1 + 0.2;</code> in both types!</p>
        </div>

        <span class="sql-label">CATEGORY — Self-Referencing FK</span>
        <pre><code class="language-sql">CREATE TABLE CATEGORY (
    category_id         INT AUTO_INCREMENT PRIMARY KEY,
    name                VARCHAR(100) NOT NULL,
    parent_category_id  INT DEFAULT NULL,

    FOREIGN KEY (parent_category_id) REFERENCES CATEGORY(category_id)
        ON DELETE SET NULL
    -- "Books" → "Engineering Books" → "CSE"
    -- NULL parent = top-level category
);</code></pre>

        <h3>🔗 Key Constraints Used</h3>
        <p><strong>PRIMARY KEY:</strong> Uniquely identifies each row. AUTO_INCREMENT generates IDs automatically.</p>
        <p><strong>FOREIGN KEY + ON DELETE CASCADE:</strong> Deleting a user auto-deletes their seller profile. Maintains referential integrity.</p>
        <p><strong>FOREIGN KEY + ON DELETE RESTRICT:</strong> Can't delete a category that has listings — forces re-categorization first.</p>
        <p><strong>CHECK:</strong> <code>price > 0</code> ensures no zero/negative prices. <code>rating BETWEEN 1 AND 5</code> enforces valid star ratings.</p>
        <p><strong>UNIQUE:</strong> <code>email</code> prevents duplicate accounts. <code>(reviewer_id, listing_id)</code> ensures one review per user per item.</p>
        <p><strong>ENUM:</strong> Restricts columns to specific values — <code>status ENUM('ACTIVE','SOLD','EXPIRED')</code>. In Oracle, you'd use CHECK with IN(...).</p>
    `,

    queries: `
        <h3>📊 Top 5 Sellers by Revenue</h3>
        <p>JOINs USER → SELLER → LISTING → ORDER_ITEM to sum up what each seller earned:</p>
        <pre><code class="language-sql">SELECT u.name AS seller_name,
       SUM(oi.quantity * oi.price_at_purchase) AS total_revenue
FROM \`USER\` u
JOIN SELLER s ON u.user_id = s.seller_id
JOIN LISTING l ON s.seller_id = l.seller_id
JOIN ORDER_ITEM oi ON l.listing_id = oi.listing_id
GROUP BY u.user_id, u.name
ORDER BY total_revenue DESC
LIMIT 5;</code></pre>

        <h3>📦 Categories With More Than 10 Listings (HAVING)</h3>
        <div class="concept-box">
            <p><strong>HAVING vs WHERE:</strong> WHERE filters rows BEFORE grouping. HAVING filters groups AFTER aggregation. You can't write <code>WHERE COUNT(*) > 10</code> — use HAVING.</p>
        </div>
        <pre><code class="language-sql">SELECT c.name AS category_name,
       COUNT(*) AS listing_count
FROM LISTING l
JOIN CATEGORY c ON l.category_id = c.category_id
GROUP BY c.category_id, c.name
HAVING COUNT(*) > 10
ORDER BY listing_count DESC;</code></pre>

        <h3>💰 Listings Below Category Average (Correlated Subquery)</h3>
        <pre><code class="language-sql">SELECT l.title, l.price, c.name AS category
FROM LISTING l
JOIN CATEGORY c ON l.category_id = c.category_id
WHERE l.price < (
    SELECT AVG(l2.price)
    FROM LISTING l2
    WHERE l2.category_id = l.category_id  -- ← correlated!
)
ORDER BY c.name, l.price;</code></pre>
        <div class="concept-box">
            <p><strong>Why "correlated"?</strong> The inner query references <code>l.category_id</code> from the outer query. It re-runs for every row in the outer table. A regular subquery runs only once.</p>
        </div>

        <h3>👤 Users With No Orders (LEFT JOIN)</h3>
        <pre><code class="language-sql">SELECT u.name, u.email, u.hostel_block
FROM \`USER\` u
LEFT JOIN BUYER b ON u.user_id = b.buyer_id
LEFT JOIN ORDERS o ON b.buyer_id = o.buyer_id
WHERE o.order_id IS NULL;</code></pre>
        <div class="concept-box">
            <p><strong>LEFT JOIN trick:</strong> A LEFT JOIN keeps ALL rows from the left table. If there's no match on the right, those columns become NULL. Filtering <code>WHERE right_col IS NULL</code> gives us "users who have NO orders".</p>
        </div>

        <h3>🔀 Set Operators</h3>
        <span class="sql-label">UNION — Sellers OR Requesters</span>
        <pre><code class="language-sql">SELECT u.user_id, u.name, 'Seller' AS role FROM \`USER\` u JOIN SELLER s ON u.user_id = s.seller_id
UNION
SELECT u.user_id, u.name, 'Requester' FROM \`USER\` u JOIN REQUEST r ON u.user_id = r.user_id;</code></pre>

        <span class="sql-label">INTERSECT equivalent — Both Seller AND Buyer</span>
        <pre><code class="language-sql">-- MySQL doesn't have INTERSECT; we use INNER JOIN instead
-- In Oracle: SELECT seller_id FROM SELLER INTERSECT SELECT buyer_id FROM BUYER;
SELECT u.name
FROM \`USER\` u
JOIN SELLER s ON u.user_id = s.seller_id
JOIN BUYER b ON u.user_id = b.buyer_id;</code></pre>

        <span class="sql-label">EXCEPT equivalent — Sellers Never Reviewed</span>
        <pre><code class="language-sql">-- MySQL doesn't have EXCEPT; we use LEFT JOIN IS NULL
-- In Oracle: SELECT seller_id FROM SELLER MINUS SELECT ... FROM REVIEW;
SELECT u.name
FROM \`USER\` u
JOIN SELLER s ON u.user_id = s.seller_id
LEFT JOIN LISTING l ON s.seller_id = l.seller_id
LEFT JOIN REVIEW r ON l.listing_id = r.listing_id
WHERE r.review_id IS NULL;</code></pre>

        <h3>🔢 Relational Algebra (for Queries 1, 3, 4)</h3>
        <pre><code class="language-sql">-- Query 1 (Top sellers by revenue):
-- π name, total_revenue (
--   γ user_id, name; SUM(qty*price) → total_revenue (
--     USER ⨝ SELLER ⨝ LISTING ⨝ ORDER_ITEM
--   )
-- )

-- Query 3 (Below category average):
-- σ price < avg_price (
--   LISTING ⨝ ρ(avg_price ← AVG(price)) (
--     γ category_id; AVG(price) (LISTING)
--   )
-- )

-- Query 4 (Users with no orders):
-- π name, email (USER) − π name, email (USER ⨝ BUYER ⨝ ORDERS)</code></pre>

        <h3>👁️ Views</h3>
        <pre><code class="language-sql">-- available_listings_view: Joins LISTING + SELLER + USER + CATEGORY
-- Used by the frontend's browse page (this very page!)
CREATE VIEW available_listings_view AS
SELECT l.listing_id, l.title, l.price, l.\`condition\`, l.quantity,
       c.name AS category, u.name AS seller_name, u.hostel_block
FROM LISTING l
JOIN CATEGORY c ON l.category_id = c.category_id
JOIN SELLER s ON l.seller_id = s.seller_id
JOIN \`USER\` u ON s.seller_id = u.user_id
WHERE l.status = 'ACTIVE';

-- seller_dashboard_view: Aggregates for the dashboard section above
CREATE VIEW seller_dashboard_view AS
SELECT u.name, s.total_sales, s.avg_rating,
       COUNT(CASE WHEN l.status = 'ACTIVE' THEN 1 END) AS active_listings,
       COUNT(CASE WHEN l.status = 'SOLD' THEN 1 END) AS sold_listings
FROM \`USER\` u
JOIN SELLER s ON u.user_id = s.seller_id
LEFT JOIN LISTING l ON s.seller_id = l.seller_id
GROUP BY u.user_id, u.name, s.total_sales, s.avg_rating;</code></pre>
    `,

    normalization: `
        <h3>📋 The Unnormalized Table — ORDER_RAW</h3>
        <p>We deliberately combined everything into one flat table to show why normalization matters:</p>
        <pre><code class="language-sql">CREATE TABLE ORDER_RAW (
    order_id INT, buyer_name VARCHAR(100), buyer_email VARCHAR(150),
    buyer_hostel VARCHAR(20), item_name VARCHAR(200), item_price DECIMAL(10,2),
    item_qty INT, seller_name VARCHAR(100), seller_upi VARCHAR(50),
    category_name VARCHAR(100), payment_method VARCHAR(20),
    payment_status VARCHAR(20), order_date DATETIME, order_status VARCHAR(20)
);</code></pre>

        <h3>💥 Anomalies — Why This Table Is Terrible</h3>
        <div class="concept-box">
            <p><strong>INSERT Anomaly:</strong> Can't add a new seller without creating a fake order first.<br>
            <strong>UPDATE Anomaly:</strong> If Ravi changes hostel, we must update EVERY row with his name.<br>
            <strong>DELETE Anomaly:</strong> Deleting the last order for a seller loses their UPI info forever.</p>
        </div>

        <h3>📐 Functional Dependencies</h3>
        <pre><code class="language-sql">-- FD1: order_id → buyer_name, buyer_email, buyer_hostel, order_date, order_status
-- FD2: buyer_email → buyer_name, buyer_hostel
-- FD3: {order_id, item_name} → item_price, item_qty, seller_name, seller_upi, category
-- FD4: seller_name → seller_upi
-- FD5: order_id → payment_method, payment_status</code></pre>
        <p>A <strong>functional dependency</strong> X → Y means: if you know X, you can uniquely determine Y. Like: if you know the email, you know the name and hostel.</p>

        <h3>🧮 Attribute Closure Example</h3>
        <pre><code class="language-sql">-- Compute {order_id, item_name}⁺
-- Start:  {order_id, item_name}
-- Apply FD1: + buyer_name, buyer_email, buyer_hostel, order_date, order_status
-- Apply FD3: + item_price, item_qty, seller_name, seller_upi, category_name
-- Apply FD4: (seller_upi already included)
-- Apply FD5: + payment_method, payment_status
-- Apply FD2: (buyer_name, buyer_hostel already included)
--
-- Final: {order_id, item_name}⁺ = ALL ATTRIBUTES → It's a SUPERKEY! ✓</code></pre>

        <h3>🔄 Decomposition: 1NF → 2NF → 3NF → BCNF</h3>
        <p><strong>1NF:</strong> All values are atomic (no arrays, no repeating groups). ✅ Already satisfied.</p>
        <p><strong>2NF:</strong> Remove partial dependencies. <code>order_id → buyer_*</code> depends on only PART of the composite key {order_id, item_name}. Split into ORDERS_2NF and ORDER_ITEMS_2NF.</p>
        <p><strong>3NF:</strong> Remove transitive dependencies. <code>buyer_email → buyer_name, buyer_hostel</code> is transitive through order_id. Split buyer info into its own table.</p>
        <p><strong>BCNF:</strong> Every determinant must be a candidate key. After 3NF, check <code>seller_name → seller_upi</code>. If seller_name isn't a candidate key in its table, decompose further.</p>
        <p>The final result matches our normalized schema: USER, SELLER, BUYER, LISTING, ORDERS, ORDER_ITEM, PAYMENT — each table serves one purpose.</p>
    `,

    procedures: `
        <h3>⚡ PROCEDURE: place_order(buyer, listing, qty, method)</h3>
        <p>This is an <strong>ACID transaction</strong> — all 5 operations succeed together, or none do:</p>
        <pre><code class="language-sql">DELIMITER $$
CREATE PROCEDURE place_order(
    IN p_buyer_id INT, IN p_listing_id INT,
    IN p_qty INT, IN p_method VARCHAR(20)
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_order_id INT;
    -- On ANY error → rollback everything
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        SELECT 'Transaction failed — rolled back' AS result;
    END;

    START TRANSACTION;

    -- 1. Get price, lock the listing row
    SELECT price INTO v_price FROM LISTING
    WHERE listing_id = p_listing_id AND status = 'ACTIVE'
          AND quantity >= p_qty
    FOR UPDATE;  -- Prevents two buyers from buying the last copy!

    -- 2. Create order
    INSERT INTO ORDERS (buyer_id, total_amount)
    VALUES (p_buyer_id, v_price * p_qty);
    SET v_order_id = LAST_INSERT_ID();

    -- 3. Add order item
    INSERT INTO ORDER_ITEM (order_id, listing_id, quantity, price_at_purchase)
    VALUES (v_order_id, p_listing_id, p_qty, v_price);

    -- 4. Reduce listing quantity
    UPDATE LISTING SET quantity = quantity - p_qty
    WHERE listing_id = p_listing_id;

    -- 5. Record payment
    INSERT INTO PAYMENT (order_id, amount, method, status, paid_at)
    VALUES (v_order_id, v_price * p_qty, p_method, 'COMPLETED', NOW());

    COMMIT;
    SELECT 'Order placed successfully!' AS result, v_order_id AS order_id;
END$$
DELIMITER ;</code></pre>

        <div class="concept-box">
            <p><strong>ACID Properties in this procedure:</strong><br>
            <strong>Atomicity:</strong> All 5 INSERT/UPDATE statements run or none do (ROLLBACK on error).<br>
            <strong>Consistency:</strong> CHECK constraints ensure price > 0, quantity ≥ 0 at all times.<br>
            <strong>Isolation:</strong> FOR UPDATE locks the listing row — other transactions wait.<br>
            <strong>Durability:</strong> After COMMIT, the data survives a server crash (written to disk).</p>
        </div>

        <h3>🔔 TRIGGER: Auto-Mark as SOLD When Quantity Hits 0</h3>
        <pre><code class="language-sql">CREATE TRIGGER trg_listing_sold_out
BEFORE UPDATE ON LISTING
FOR EACH ROW
BEGIN
    IF NEW.quantity = 0 AND OLD.quantity > 0 THEN
        SET NEW.status = 'SOLD';
    END IF;
END;</code></pre>
        <p>This fires automatically — no application code needed. When place_order reduces quantity to 0, the trigger sets status to SOLD.</p>

        <h3>⭐ TRIGGER: Recalculate Seller Rating After Review</h3>
        <pre><code class="language-sql">CREATE TRIGGER trg_update_seller_rating
AFTER INSERT ON REVIEW
FOR EACH ROW
BEGIN
    DECLARE v_seller_id INT;
    SELECT seller_id INTO v_seller_id FROM LISTING
    WHERE listing_id = NEW.listing_id;

    UPDATE SELLER SET avg_rating = (
        SELECT AVG(r.rating) FROM REVIEW r
        JOIN LISTING l ON r.listing_id = l.listing_id
        WHERE l.seller_id = v_seller_id
    ) WHERE seller_id = v_seller_id;
END;</code></pre>

        <h3>📝 TRIGGER: Audit Trail on Price Changes</h3>
        <pre><code class="language-sql">CREATE TRIGGER trg_price_audit
BEFORE UPDATE ON LISTING
FOR EACH ROW
BEGIN
    IF OLD.price <> NEW.price THEN
        INSERT INTO PRICE_AUDIT (listing_id, old_price, new_price, changed_by, changed_at)
        VALUES (OLD.listing_id, OLD.price, NEW.price, NEW.seller_id, NOW());
    END IF;
END;</code></pre>

        <h3>🔄 CURSOR: Mark Old Listings as Expired</h3>
        <pre><code class="language-sql">CREATE PROCEDURE mark_expired_listings()
BEGIN
    DECLARE v_lid INT;
    DECLARE v_done INT DEFAULT 0;
    DECLARE v_count INT DEFAULT 0;

    DECLARE cur CURSOR FOR
        SELECT listing_id FROM LISTING
        WHERE status = 'ACTIVE'
          AND created_at < NOW() - INTERVAL 60 DAY;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = 1;

    OPEN cur;
    read_loop: LOOP
        FETCH cur INTO v_lid;
        IF v_done THEN LEAVE read_loop; END IF;
        UPDATE LISTING SET status = 'EXPIRED' WHERE listing_id = v_lid;
        SET v_count = v_count + 1;
    END LOOP;
    CLOSE cur;

    SELECT CONCAT(v_count, ' listings marked as EXPIRED') AS result;
END;</code></pre>
    `,

    transactions: `
        <h3>🏁 The Race Condition Problem</h3>
        <p>Imagine: only 1 copy of "DBMS by Navathe" is left. Two students click "Buy" at the same instant. Without proper locking, both could "succeed" — but there's only one book!</p>

        <div class="concept-box">
            <p><strong>SELECT ... FOR UPDATE</strong> solves this by locking the row. The first transaction holds the lock; the second WAITS until the first commits or rolls back.</p>
        </div>

        <h3>🧪 Two-Session Proof</h3>
        <span class="sql-label">Session 1 — Terminal 1</span>
        <pre><code class="language-sql">-- Setup: only 1 copy left
UPDATE LISTING SET quantity = 1, status = 'ACTIVE' WHERE listing_id = 1;

START TRANSACTION;
-- Lock the row
SELECT listing_id, title, quantity
FROM LISTING WHERE listing_id = 1 FOR UPDATE;
-- → Returns quantity = 1
-- → Now switch to Session 2...</code></pre>

        <span class="sql-label">Session 2 — Terminal 2</span>
        <pre><code class="language-sql">START TRANSACTION;
-- Try to read the same row
SELECT listing_id, title, quantity
FROM LISTING WHERE listing_id = 1 FOR UPDATE;
-- ⏳ BLOCKED! Waiting for Session 1 to release the lock...</code></pre>

        <span class="sql-label">Back to Session 1</span>
        <pre><code class="language-sql">-- Session 1 completes the purchase
UPDATE LISTING SET quantity = quantity - 1 WHERE listing_id = 1;
COMMIT;
-- Lock released! Session 2 unblocks.</code></pre>

        <span class="sql-label">Session 2 Unblocks</span>
        <pre><code class="language-sql">-- Session 2's SELECT now returns — quantity is 0!
-- Application checks: quantity = 0 → item sold out
ROLLBACK;  -- Don't buy — nothing left</code></pre>

        <h3>💀 What a Deadlock Looks Like</h3>
        <pre><code class="language-sql">-- Session A: START TRANSACTION;
--            SELECT * FROM LISTING WHERE listing_id = 1 FOR UPDATE;  -- locks row 1
--            SELECT * FROM LISTING WHERE listing_id = 2 FOR UPDATE;  -- wants row 2

-- Session B: START TRANSACTION;
--            SELECT * FROM LISTING WHERE listing_id = 2 FOR UPDATE;  -- locks row 2
--            SELECT * FROM LISTING WHERE listing_id = 1 FOR UPDATE;  -- wants row 1

-- DEADLOCK! A holds 1, wants 2. B holds 2, wants 1.
-- MySQL detects this and kills one session:
-- ERROR 1213: Deadlock found when trying to get lock;
--             try restarting transaction

-- Prevention: Always lock rows in consistent order (by listing_id ASC)</code></pre>
    `,

    indexes: `
        <h3>🌳 B+ Tree Indexes — What and Why</h3>
        <div class="concept-box">
            <p>A <strong>B+ tree</strong> is a balanced tree where leaf nodes are linked in order and store pointers to actual rows. Internal nodes guide the search. InnoDB uses B+ trees for ALL indexes by default.</p>
        </div>

        <h3>📊 BEFORE Indexing — Full Table Scan</h3>
        <pre><code class="language-sql">EXPLAIN SELECT * FROM LISTING WHERE title LIKE 'Data%';
-- type: ALL (full table scan)
-- rows: 5000+ (scans every row)
-- Extra: Using where

EXPLAIN SELECT * FROM LISTING
WHERE category_id = 3 AND status = 'ACTIVE';
-- type: ALL (full table scan again!)
-- rows: 5000+</code></pre>

        <h3>⚡ Creating Indexes</h3>
        <pre><code class="language-sql">-- Single-column index for title search
CREATE INDEX idx_listing_title ON LISTING(title);

-- Composite index for category + status filtering
CREATE INDEX idx_listing_cat_status ON LISTING(category_id, status);
-- ↑ Helps: WHERE category_id = 3
-- ↑ Helps: WHERE category_id = 3 AND status = 'ACTIVE'
-- ✗ Does NOT help: WHERE status = 'ACTIVE' alone (leftmost prefix rule!)</code></pre>

        <h3>📊 AFTER Indexing — Index Lookup</h3>
        <pre><code class="language-sql">EXPLAIN SELECT * FROM LISTING WHERE title LIKE 'Data%';
-- type: range (uses the B+ tree index!)
-- rows: ~50 (only matching rows)
-- key: idx_listing_title

EXPLAIN SELECT * FROM LISTING
WHERE category_id = 3 AND status = 'ACTIVE';
-- type: ref (uses composite index)
-- rows: ~30
-- key: idx_listing_cat_status</code></pre>

        <div class="concept-box">
            <p><strong>Leftmost Prefix Rule:</strong> A composite index on (A, B) helps queries filtering on A, or A+B, but NOT B alone. Think of it like a phone book sorted by (last_name, first_name) — you can look up by last name, or last+first, but not first name alone.</p>
        </div>

        <h3>📋 Additional Indexes</h3>
        <pre><code class="language-sql">CREATE INDEX idx_orders_buyer ON ORDERS(buyer_id);
-- Speeds up: "show my orders" (WHERE buyer_id = ?)

CREATE INDEX idx_review_listing ON REVIEW(listing_id);
-- Speeds up: "show reviews for this listing"

CREATE INDEX idx_listing_created ON LISTING(created_at);
-- Speeds up: the cursor that finds listings older than 60 days</code></pre>
    `,

    er: `
        <h3>🗺️ Entity-Relationship Design</h3>

        <div class="concept-box">
            <p><strong>12 tables, 3 specializations, 1 self-reference, 1 junction table.</strong><br>
            Every design decision is documented in <code>docs/er-design.md</code>.</p>
        </div>

        <h3>📐 Key ER Concepts Used</h3>

        <p><strong>1. Overlapping Partial Specialization (USER → SELLER, BUYER)</strong><br>
        Overlapping = one user can be both a seller AND buyer. Partial = not every user must be one. This is the most common real-world pattern.</p>

        <p><strong>2. Self-Referencing FK (CATEGORY → CATEGORY)</strong><br>
        <code>parent_category_id</code> points to <code>category_id</code> in the same table. Creates a tree: Books → Engineering Books → CSE Books.</p>

        <p><strong>3. Junction Table (ORDER_ITEM)</strong><br>
        Resolves the M:N relationship between ORDERS and LISTING. One order can have many items; one item can be in many orders.</p>

        <p><strong>4. IS-A Relationship (LISTING → BOOK_DETAILS)</strong><br>
        Only book listings get ISBN, author, edition. Electronics don't need these fields. Avoids NULLs in the LISTING table.</p>

        <h3>🗂️ ER-to-Relational Mapping Rules</h3>
        <pre><code class="language-sql">-- Rule 1: Strong entity → table with its own PK
--   USER(user_id PK, name, email, ...)

-- Rule 2: Overlapping specialization → separate child tables
--   SELLER(seller_id PK FK→USER, upi_id, ...)
--   BUYER(buyer_id PK FK→USER, wallet_balance)

-- Rule 3: 1:M relationship → FK on the "many" side
--   LISTING has seller_id FK → SELLER

-- Rule 4: M:N relationship → junction table
--   ORDER_ITEM(order_id FK, listing_id FK)

-- Rule 5: Self-reference → FK in same table
--   CATEGORY(parent_category_id FK → category_id)

-- Rule 6: 1:1 relationship → FK on total-participation side
--   PAYMENT has order_id FK → ORDERS</code></pre>

        <h3>❓ Likely Viva Questions</h3>
        <p><strong>Q: Why is ORDER_ITEM needed?</strong><br>
        A: One order can have multiple items. Without it, you'd need repeating groups (violates 1NF).</p>

        <p><strong>Q: Why store price_at_purchase separately?</strong><br>
        A: The seller might change the price later. The order should record what was actually paid — it's a historical fact.</p>

        <p><strong>Q: Why ON DELETE CASCADE on seller but RESTRICT on category?</strong><br>
        A: Deleting a user should clean up their profile (CASCADE). But deleting a category with existing listings would orphan data (RESTRICT forces re-categorization first).</p>
    `
};

// ---- MODAL LOGIC ----
function initModal() {
    const overlay = document.getElementById('modalOverlay');
    const closeBtn = document.getElementById('modalClose');
    const howItWorksBtn = document.getElementById('howItWorksBtn');
    const footerBtn = document.getElementById('footerHowItWorks');
    const tabs = document.querySelectorAll('.tab');
    const modalBody = document.getElementById('modalBody');

    function openModal() {
        overlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        showTab('schema');
    }

    function closeModal() {
        overlay.classList.remove('active');
        document.body.style.overflow = '';
    }

    function showTab(tabName) {
        tabs.forEach(t => t.classList.toggle('active', t.dataset.tab === tabName));
        modalBody.innerHTML = howItWorksContent[tabName] || '<p>Content coming soon...</p>';
        // Re-highlight code blocks
        modalBody.querySelectorAll('pre code').forEach(block => {
            hljs.highlightElement(block);
        });
        modalBody.scrollTop = 0;
    }

    howItWorksBtn?.addEventListener('click', (e) => { e.preventDefault(); openModal(); });
    footerBtn?.addEventListener('click', (e) => { e.preventDefault(); openModal(); });
    closeBtn?.addEventListener('click', closeModal);
    overlay?.addEventListener('click', (e) => { if (e.target === overlay) closeModal(); });

    tabs.forEach(tab => {
        tab.addEventListener('click', () => showTab(tab.dataset.tab));
    });

    // ESC key closes modal
    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape') closeModal();
    });
}

// ---- SEARCH FILTER ----
function initSearch() {
    const input = document.getElementById('searchInput');
    input?.addEventListener('input', () => {
        const query = input.value.toLowerCase();
        const cards = document.querySelectorAll('.listing-card');
        cards.forEach(card => {
            const title = card.querySelector('.listing-title')?.textContent.toLowerCase() || '';
            card.style.display = title.includes(query) ? '' : 'none';
        });
    });
}

// ============================================================================
// LOGIN SYSTEM
// Simulates database authentication for the demo. Shows:
// 1. A user-picker (simulates SELECT * FROM USER)
// 2. Profile view (simulates JOIN across USER, SELLER, BUYER)
// 3. The actual SQL queries that would power this in a real app
// ============================================================================

// Sample users from the database (what seed.sql generates)
const sampleUsers = [
    { id: 1,  name: "Arjun Sharma",   email: "arjun.sharma1@campusswap.in",   phone: "+919876543210", hostel: "Block-A",        room: "204", isSeller: true,  isBuyer: true,  upi: "arjun@upi",   totalSales: 15420, avgRating: 4.5, wallet: 200,  listings: 8,  orders: 3 },
    { id: 2,  name: "Priya Mehta",    email: "priya.mehta2@campusswap.in",     phone: "+919876543211", hostel: "Girls-Hostel-1", room: "312", isSeller: true,  isBuyer: true,  upi: "priya@upi",   totalSales: 12350, avgRating: 4.8, wallet: 500,  listings: 5,  orders: 7 },
    { id: 3,  name: "Rohit Kumar",    email: "rohit.kumar3@campusswap.in",     phone: "+919876543212", hostel: "Block-C",        room: "108", isSeller: true,  isBuyer: false, upi: "rohit@upi",   totalSales: 9800,  avgRating: 4.2, wallet: 0,    listings: 12, orders: 0 },
    { id: 4,  name: "Sneha Reddy",    email: "sneha.reddy4@campusswap.in",     phone: "+919876543213", hostel: "Girls-Hostel-2", room: "215", isSeller: true,  isBuyer: true,  upi: "sneha@upi",   totalSales: 8650,  avgRating: 3.9, wallet: 1200, listings: 6,  orders: 4 },
    { id: 5,  name: "Vikram Desai",   email: "vikram.desai5@campusswap.in",    phone: "+919876543214", hostel: "Block-D",        room: "401", isSeller: true,  isBuyer: true,  upi: "vikram@upi",  totalSales: 7200,  avgRating: 4.7, wallet: 800,  listings: 3,  orders: 5 },
    { id: 6,  name: "Ananya Patel",   email: "ananya.patel6@campusswap.in",    phone: "+919876543215", hostel: "Girls-Hostel-1", room: "119", isSeller: true,  isBuyer: false, upi: "ananya@upi",  totalSales: 3200,  avgRating: 4.3, wallet: 0,    listings: 4,  orders: 0 },
    { id: 7,  name: "Karthik Verma",  email: "karthik.verma7@campusswap.in",   phone: "+919876543216", hostel: "Block-B",        room: "305", isSeller: false, isBuyer: true,  upi: null,          totalSales: 0,     avgRating: 0,   wallet: 350,  listings: 0,  orders: 6 },
    { id: 8,  name: "Meera Thomas",   email: "meera.thomas8@campusswap.in",    phone: "+919876543217", hostel: "Block-E",        room: "210", isSeller: true,  isBuyer: true,  upi: "meera@upi",   totalSales: 5100,  avgRating: 4.6, wallet: 150,  listings: 7,  orders: 2 },
    { id: 9,  name: "Rahul Gupta",    email: "rahul.gupta9@campusswap.in",     phone: "+919876543218", hostel: "Block-C",        room: "415", isSeller: false, isBuyer: true,  upi: null,          totalSales: 0,     avgRating: 0,   wallet: 900,  listings: 0,  orders: 8 },
    { id: 10, name: "Divya Singh",    email: "divya.singh10@campusswap.in",    phone: "+919876543219", hostel: "Girls-Hostel-2", room: "102", isSeller: false, isBuyer: false, upi: null,          totalSales: 0,     avgRating: 0,   wallet: 0,    listings: 0,  orders: 0 },
];

// Avatar gradient colors for variety
const avatarColors = [
    'linear-gradient(135deg, #6C5CE7, #FD79A8)',
    'linear-gradient(135deg, #00B894, #00CEC9)',
    'linear-gradient(135deg, #E17055, #FDCB6E)',
    'linear-gradient(135deg, #0984E3, #74B9FF)',
    'linear-gradient(135deg, #A29BFE, #FD79A8)',
    'linear-gradient(135deg, #00B894, #55EFC4)',
    'linear-gradient(135deg, #E17055, #FAB1A0)',
    'linear-gradient(135deg, #6C5CE7, #A29BFE)',
    'linear-gradient(135deg, #0984E3, #00CEC9)',
    'linear-gradient(135deg, #FD79A8, #E84393)',
];

let currentUser = null; // tracks who is "logged in"

function initLogin() {
    const loginBtn = document.getElementById('loginBtn');
    const loginOverlay = document.getElementById('loginOverlay');
    const loginClose = document.getElementById('loginClose');

    function openLoginModal() {
        loginOverlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        if (currentUser) {
            showProfile(currentUser);
        } else {
            showLoginForm();
        }
    }

    function closeLoginModal() {
        loginOverlay.classList.remove('active');
        document.body.style.overflow = '';
    }

    loginBtn?.addEventListener('click', openLoginModal);
    loginClose?.addEventListener('click', closeLoginModal);
    loginOverlay?.addEventListener('click', (e) => {
        if (e.target === loginOverlay) closeLoginModal();
    });

    document.addEventListener('keydown', (e) => {
        if (e.key === 'Escape' && loginOverlay.classList.contains('active')) {
            closeLoginModal();
        }
    });
}

function showLoginForm() {
    const body = document.getElementById('loginBody');
    const title = document.getElementById('loginModalTitle');
    title.textContent = '🔐 Student Login';

    body.innerHTML = `
        <div class="login-form">
            <div>
                <label>Email Address</label>
                <input type="email" id="loginEmail" placeholder="your.name@campusswap.in" autocomplete="off">
            </div>
            <div>
                <label>Password</label>
                <input type="password" id="loginPassword" placeholder="Enter password" value="campus123">
            </div>
            <button class="btn btn-primary" id="loginSubmit" style="width:100%">Log In</button>

            <div class="login-divider">or pick a demo account</div>

            <div class="user-picker-grid">
                ${sampleUsers.map((u, i) => `
                    <div class="user-picker-card" data-user-id="${u.id}">
                        <div class="user-picker-avatar" style="background: ${avatarColors[i % avatarColors.length]}">
                            ${u.name.split(' ').map(n => n[0]).join('')}
                        </div>
                        <div class="user-picker-info">
                            <div class="user-picker-name">${u.name}</div>
                            <div class="user-picker-detail">${u.hostel} · Room ${u.room}</div>
                        </div>
                    </div>
                `).join('')}
            </div>

            <div class="concept-box" style="margin-top: 8px;">
                <p style="margin-bottom: 0; color: var(--text); font-size: 0.82rem;">
                    <strong>🔍 SQL Behind Login:</strong> In a real app, clicking "Log In" runs:
                </p>
            </div>
            <pre><code class="language-sql">-- Authentication query
SELECT user_id, name, email, hostel_block, room_no
FROM \`USER\`
WHERE email = ? AND password_hash = SHA2(?, 256);

-- Then check roles:
SELECT seller_id FROM SELLER WHERE seller_id = ?;
SELECT buyer_id FROM BUYER WHERE buyer_id = ?;</code></pre>
        </div>
    `;

    // Highlight SQL
    body.querySelectorAll('pre code').forEach(block => hljs.highlightElement(block));

    // Email login handler
    document.getElementById('loginSubmit')?.addEventListener('click', () => {
        const email = document.getElementById('loginEmail').value.trim().toLowerCase();
        const user = sampleUsers.find(u => u.email === email);
        if (user) {
            loginAs(user);
        } else if (email) {
            // Partial match by name
            const byName = sampleUsers.find(u => u.name.toLowerCase().includes(email.split('@')[0].replace('.', ' ')));
            if (byName) {
                loginAs(byName);
            } else {
                alert('User not found! Try picking a demo account below, or use an email like arjun.sharma1@campusswap.in');
            }
        } else {
            alert('Please enter an email or pick a demo account below.');
        }
    });

    // User picker click handler
    document.querySelectorAll('.user-picker-card').forEach(card => {
        card.addEventListener('click', () => {
            const userId = parseInt(card.dataset.userId);
            const user = sampleUsers.find(u => u.id === userId);
            if (user) loginAs(user);
        });
    });
}

function loginAs(user) {
    currentUser = user;
    updateNavbar(user);
    showProfile(user);
}

function showProfile(user) {
    const body = document.getElementById('loginBody');
    const title = document.getElementById('loginModalTitle');
    const idx = sampleUsers.indexOf(user);
    const gradient = avatarColors[idx >= 0 ? idx % avatarColors.length : 0];

    title.textContent = '👤 My Profile';

    const roles = [];
    if (user.isSeller) roles.push('<span class="role-badge role-seller">🏷️ Seller</span>');
    if (user.isBuyer) roles.push('<span class="role-badge role-buyer">🛒 Buyer</span>');
    if (!user.isSeller && !user.isBuyer) roles.push('<span class="role-badge" style="background:rgba(225,112,85,0.15);color:#E17055">👀 Browser</span>');

    body.innerHTML = `
        <div class="profile-container">
            <div class="profile-avatar-large" style="background: ${gradient}">
                ${user.name.split(' ').map(n => n[0]).join('')}
            </div>
            <div class="profile-name">${user.name}</div>
            <div class="profile-email">${user.email}</div>

            <div class="profile-roles">${roles.join('')}</div>

            <div class="profile-details">
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Hostel</div>
                    <div class="profile-detail-value">${user.hostel}</div>
                </div>
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Room</div>
                    <div class="profile-detail-value">${user.room}</div>
                </div>
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Phone</div>
                    <div class="profile-detail-value">${user.phone}</div>
                </div>
                <div class="profile-detail-item">
                    <div class="profile-detail-label">User ID</div>
                    <div class="profile-detail-value">#${user.id}</div>
                </div>
                ${user.isSeller ? `
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Total Sales</div>
                    <div class="profile-detail-value" style="color:#00B894">₹${user.totalSales.toLocaleString('en-IN')}</div>
                </div>
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Avg Rating</div>
                    <div class="profile-detail-value" style="color:#FDCB6E">⭐ ${user.avgRating}</div>
                </div>
                ` : ''}
                ${user.isBuyer ? `
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Wallet</div>
                    <div class="profile-detail-value" style="color:#A29BFE">₹${user.wallet.toLocaleString('en-IN')}</div>
                </div>
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Orders</div>
                    <div class="profile-detail-value">${user.orders}</div>
                </div>
                ` : ''}
                ${user.isSeller ? `
                <div class="profile-detail-item">
                    <div class="profile-detail-label">UPI ID</div>
                    <div class="profile-detail-value">${user.upi}</div>
                </div>
                <div class="profile-detail-item">
                    <div class="profile-detail-label">Listings</div>
                    <div class="profile-detail-value">${user.listings}</div>
                </div>
                ` : ''}
            </div>

            <div class="profile-actions">
                <button class="btn btn-outline" id="switchUserBtn">Switch User</button>
                <button class="btn btn-primary" id="logoutBtn" style="background: linear-gradient(135deg, #E17055, #D63031);">Log Out</button>
            </div>

            <div class="concept-box">
                <p style="margin-bottom: 0; color: var(--text); font-size: 0.82rem;">
                    <strong>🔍 SQL Behind This Profile:</strong>
                </p>
            </div>
            <pre><code class="language-sql">-- Profile data comes from joining 3 tables:
SELECT u.name, u.email, u.phone, u.hostel_block, u.room_no,
       s.upi_id, s.total_sales, s.avg_rating,
       b.wallet_balance,
       COUNT(DISTINCT l.listing_id) AS listings,
       COUNT(DISTINCT o.order_id) AS orders
FROM \`USER\` u
LEFT JOIN SELLER s ON u.user_id = s.seller_id
LEFT JOIN BUYER b ON u.user_id = b.buyer_id
LEFT JOIN LISTING l ON s.seller_id = l.seller_id
LEFT JOIN ORDERS o ON b.buyer_id = o.buyer_id
WHERE u.user_id = ${user.id}
GROUP BY u.user_id;

-- This is the seller_dashboard_view in action!
-- LEFT JOINs because user might not be a seller or buyer</code></pre>
        </div>
    `;

    // Highlight SQL
    body.querySelectorAll('pre code').forEach(block => hljs.highlightElement(block));

    // Button handlers
    document.getElementById('switchUserBtn')?.addEventListener('click', () => {
        showLoginForm();
    });

    document.getElementById('logoutBtn')?.addEventListener('click', () => {
        currentUser = null;
        resetNavbar();
        showLoginForm();
    });
}

function updateNavbar(user) {
    const navActions = document.querySelector('.nav-actions');
    const idx = sampleUsers.indexOf(user);
    const gradient = avatarColors[idx >= 0 ? idx % avatarColors.length : 0];

    navActions.innerHTML = `
        <button class="nav-user" id="navUserBtn">
            <div class="nav-user-avatar" style="background: ${gradient}">
                ${user.name.split(' ').map(n => n[0]).join('')}
            </div>
            <span class="nav-user-name">${user.name.split(' ')[0]}</span>
        </button>
        <button class="btn btn-primary">Sell Now</button>
    `;

    // Click avatar → open profile
    document.getElementById('navUserBtn')?.addEventListener('click', () => {
        const loginOverlay = document.getElementById('loginOverlay');
        loginOverlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        showProfile(user);
    });
}

function resetNavbar() {
    const navActions = document.querySelector('.nav-actions');
    navActions.innerHTML = `
        <button class="btn btn-outline" id="loginBtn">Log In</button>
        <button class="btn btn-primary">Sell Now</button>
    `;
    // Re-attach login handler
    document.getElementById('loginBtn')?.addEventListener('click', () => {
        const loginOverlay = document.getElementById('loginOverlay');
        loginOverlay.classList.add('active');
        document.body.style.overflow = 'hidden';
        showLoginForm();
    });
}

// ---- INIT ----
document.addEventListener('DOMContentLoaded', () => {
    renderListings();
    renderRequests();
    initModal();
    initSearch();
    initLogin();
});
