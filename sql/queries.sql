USE campusswap;

-- ============================================================================
-- CAMPUSSWAP - STAGE 4: ADVANCED SQL QUERIES & RELATIONAL ALGEBRA
-- ============================================================================

-- ============================================================================
-- 1. Top 5 sellers by revenue
-- JOIN SELLER with ORDER_ITEM, LISTING, and USER to sum revenue per seller.
-- VIVA EXPLANATION: We join multiple tables because revenue is derived from 
-- ORDER_ITEM (price_at_purchase * quantity). LISTING links the item to the 
-- SELLER, and USER provides the seller's actual name. We group by seller to 
-- compute the aggregate sum, order descending, and limit to 5.
-- ============================================================================
SELECT 
    u.name AS seller_name, 
    SUM(oi.price_at_purchase * oi.quantity) AS total_revenue
FROM 
    `USER` u
JOIN 
    SELLER s ON u.user_id = s.seller_id
JOIN 
    LISTING l ON s.seller_id = l.seller_id
JOIN 
    ORDER_ITEM oi ON l.listing_id = oi.listing_id
GROUP BY 
    s.seller_id, u.name
ORDER BY 
    total_revenue DESC
LIMIT 5;

-- RELATIONAL ALGEBRA FOR QUERY 1:
-- Ï(total_revenue, Î³(seller_id, name; SUM(price_at_purchase * quantity))(
--   (USER â‹ˆ_(user_id=seller_id) SELLER) 
--   â‹ˆ_(seller_id=seller_id) 
--   (LISTING â‹ˆ_(listing_id=listing_id) ORDER_ITEM)
-- ))
-- (Then applying a sort and limit operation, not standard in basic RA)

-- ============================================================================
-- 2. Categories with more than 10 listings
-- VIVA EXPLANATION: Uses GROUP BY with HAVING clause. HAVING is applied AFTER 
-- grouping to filter aggregated results, unlike WHERE which filters individual rows.
-- ============================================================================
SELECT 
    c.name AS category_name, 
    COUNT(l.listing_id) AS listing_count
FROM 
    CATEGORY c
JOIN 
    LISTING l ON c.category_id = l.category_id
GROUP BY 
    c.category_id, c.name
HAVING 
    COUNT(l.listing_id) > 10;

-- ============================================================================
-- 3. Listings priced below their category average (Correlated Nested Subquery)
-- VIVA EXPLANATION: A correlated subquery executes once for each row in the 
-- outer query. It's correlated because the subquery references 'l1.category_id' 
-- from the outer query. It compares each listing's price to the average of its 
-- specific category.
-- ============================================================================
SELECT 
    l1.title, 
    l1.price, 
    c.name AS category_name
FROM 
    LISTING l1
JOIN 
    CATEGORY c ON l1.category_id = c.category_id
WHERE 
    l1.price < (
        SELECT AVG(l2.price) 
        FROM LISTING l2 
        WHERE l2.category_id = l1.category_id
    );

-- RELATIONAL ALGEBRA FOR QUERY 3:
-- Let AvgPrices = Ï(avg_price, Î³(category_id; AVG(price))(LISTING))
-- Ï€(title, price, name)(
--   Ïƒ(price < avg_price)(
--     (LISTING â‹ˆ_(category_id=category_id) CATEGORY) â‹ˆ_(category_id=category_id) AvgPrices
--   )
-- )

-- ============================================================================
-- 4. Users with no orders (LEFT JOIN + IS NULL)
-- VIVA EXPLANATION: A LEFT JOIN returns all rows from the left table (USER), 
-- and matched rows from the right (ORDERS via BUYER). If a user hasn't made 
-- an order, the right side will be NULL. The WHERE ... IS NULL filters for 
-- those non-matches, effectively finding users with no purchase history.
-- ============================================================================
SELECT 
    u.name, 
    u.email
FROM 
    `USER` u
LEFT JOIN 
    BUYER b ON u.user_id = b.buyer_id
LEFT JOIN 
    ORDERS o ON b.buyer_id = o.buyer_id
WHERE 
    o.order_id IS NULL;

-- RELATIONAL ALGEBRA FOR QUERY 4:
-- Let UserBuyerOrders = (USER âŸ•_(user_id=buyer_id) BUYER) âŸ•_(buyer_id=buyer_id) ORDERS
-- Ï€(name, email)(Ïƒ(order_id IS NULL)(UserBuyerOrders))

-- ============================================================================
-- 5. Most requested categories
-- VIVA EXPLANATION: Joins REQUEST and CATEGORY, groups by category, and 
-- orders by the count descending to show demand.
-- ============================================================================
SELECT 
    c.name AS category_name, 
    COUNT(r.request_id) AS request_count
FROM 
    CATEGORY c
JOIN 
    REQUEST r ON c.category_id = r.category_id
GROUP BY 
    c.category_id, c.name
ORDER BY 
    request_count DESC;

-- ============================================================================
-- 6. SET OPERATOR: UNION (Users who are sellers OR have posted requests)
-- VIVA EXPLANATION: UNION combines result sets of two queries and removes 
-- duplicate rows. UNION ALL would keep duplicates. We project just the user_id 
-- from both sets to match the schema for the set operation.
-- ============================================================================
SELECT seller_id AS user_id FROM SELLER
UNION
SELECT user_id FROM REQUEST;

-- ============================================================================
-- 7. SET OPERATOR: INTERSECT equivalent (Users who are BOTH sellers and buyers)
-- VIVA EXPLANATION: MySQL does not support the INTERSECT operator. We simulate 
-- it using an INNER JOIN between SELLER and BUYER.
-- In Oracle or PostgreSQL, you would write:
-- SELECT seller_id FROM SELLER INTERSECT SELECT buyer_id FROM BUYER;
-- ============================================================================
SELECT 
    s.seller_id AS user_id, 
    u.name
FROM 
    SELLER s
INNER JOIN 
    BUYER b ON s.seller_id = b.buyer_id
JOIN 
    `USER` u ON s.seller_id = u.user_id;

-- ============================================================================
-- 8. SET OPERATOR: EXCEPT equivalent (Sellers who have never received a review)
-- VIVA EXPLANATION: MySQL does not support EXCEPT (or MINUS in Oracle). We 
-- simulate it using LEFT JOIN ... IS NULL. We join sellers' listings to reviews.
-- In Oracle, you would write:
-- SELECT seller_id FROM SELLER MINUS SELECT DISTINCT l.seller_id FROM REVIEW r JOIN LISTING l ON r.listing_id=l.listing_id;
-- ============================================================================
SELECT 
    s.seller_id, 
    u.name
FROM 
    SELLER s
JOIN 
    `USER` u ON s.seller_id = u.user_id
LEFT JOIN 
    LISTING l ON s.seller_id = l.seller_id
LEFT JOIN 
    REVIEW r ON l.listing_id = r.listing_id
WHERE 
    r.review_id IS NULL
GROUP BY 
    s.seller_id, u.name;

-- ============================================================================
-- 9. Revenue by month
-- VIVA EXPLANATION: Uses DATE_FORMAT to extract year-month from the order_date 
-- for grouping. Groups sales to show monthly trends.
-- ============================================================================
SELECT 
    DATE_FORMAT(order_date, '%Y-%m') AS month, 
    SUM(total_amount) AS monthly_revenue
FROM 
    ORDERS
WHERE 
    status = 'COMPLETED'
GROUP BY 
    month
ORDER BY 
    month;

-- ============================================================================
-- 10. Top-rated listings with minimum 3 reviews
-- VIVA EXPLANATION: Uses HAVING to ensure at least 3 reviews exist for 
-- statistical significance before considering the average rating.
-- ============================================================================
SELECT 
    l.title, 
    AVG(r.rating) AS avg_rating,
    COUNT(r.review_id) AS review_count
FROM 
    LISTING l
JOIN 
    REVIEW r ON l.listing_id = r.listing_id
GROUP BY 
    l.listing_id, l.title
HAVING 
    COUNT(r.review_id) >= 3
ORDER BY 
    avg_rating DESC;

-- ============================================================================
-- VIEWS
-- ============================================================================

-- ============================================================================
-- VIEW 1: available_listings_view
-- Shows all active listings with seller name, category name, price, condition
-- WHY: Saves writing the same 3-table JOIN every time the frontend needs to 
-- show the marketplace feed.
-- ============================================================================
CREATE OR REPLACE VIEW available_listings_view AS
SELECT 
    l.listing_id,
    u.name AS seller_name,
    c.name AS category_name,
    l.title,
    l.price,
    l.condition,
    l.image_url,
    l.created_at
FROM 
    LISTING l
JOIN 
    SELLER s ON l.seller_id = s.seller_id
JOIN 
    `USER` u ON s.seller_id = u.user_id
JOIN 
    CATEGORY c ON l.category_id = c.category_id
WHERE 
    l.status = 'ACTIVE';

-- ============================================================================
-- VIEW 2: seller_dashboard_view  
-- Shows each seller's name, total listings, active listings, total revenue, avg rating
-- WHY: The seller's home page/dashboard needs this aggregated data. A view makes 
-- it one simple SELECT from the application code, abstracting the complex joins 
-- and conditional aggregations.
-- ============================================================================
CREATE OR REPLACE VIEW seller_dashboard_view AS
SELECT 
    s.seller_id,
    u.name AS seller_name,
    COUNT(l.listing_id) AS total_listings,
    SUM(CASE WHEN l.status = 'ACTIVE' THEN 1 ELSE 0 END) AS active_listings,
    s.total_sales AS total_revenue,
    s.avg_rating
FROM 
    SELLER s
JOIN 
    `USER` u ON s.seller_id = u.user_id
LEFT JOIN 
    LISTING l ON s.seller_id = l.seller_id
GROUP BY 
    s.seller_id, u.name, s.total_sales, s.avg_rating;

-- ============================================================================
-- RELATIONAL ALGEBRA KEY
-- ============================================================================
-- Ï€ : Projection (SELECT columns)
-- Ïƒ : Selection (WHERE / HAVING conditions)
-- â‹ˆ : Natural/Inner Join
-- âŸ• : Left Outer Join
-- Ï : Rename
-- Î³ : Aggregation/Grouping (GROUP BY)
-- ============================================================================

