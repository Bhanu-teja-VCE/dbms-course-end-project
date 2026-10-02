-- STAGE 5: NORMALIZATION
-- Database: campusswap

USE campusswap;

-- ============================================================================
-- 1. UNNORMALIZED TABLE
-- ============================================================================
-- We start with a flat, deliberately unnormalized table that combines order, 
-- item, payment, buyer, and listing data. This represents how data might look
-- if exported to a spreadsheet.

DROP TABLE IF EXISTS ORDER_RAW;

CREATE TABLE ORDER_RAW (
    order_id INT, 
    buyer_name VARCHAR(100), 
    buyer_email VARCHAR(150),
    buyer_hostel VARCHAR(20), 
    item_name VARCHAR(200), 
    item_price DECIMAL(10,2),
    item_qty INT, 
    seller_name VARCHAR(100), 
    seller_upi VARCHAR(50),
    category_name VARCHAR(100), 
    payment_method VARCHAR(20),
    payment_status VARCHAR(20), 
    order_date DATETIME, 
    order_status VARCHAR(20)
);

-- Inserting sample data to demonstrate redundancy and anomalies
INSERT INTO ORDER_RAW VALUES
(101, 'Rahul Sharma', 'rahul@college.edu', 'Block A', 'Engineering Physics Book', 450.00, 1, 'Amit Kumar', 'amit@ybl', 'Books', 'UPI', 'Completed', '2023-10-01 10:00:00', 'Delivered'),
(101, 'Rahul Sharma', 'rahul@college.edu', 'Block A', 'Scientific Calculator', 800.00, 1, 'Priya Singh', 'priya@okicici', 'Electronics', 'UPI', 'Completed', '2023-10-01 10:00:00', 'Delivered'),
(102, 'Neha Gupta', 'neha@college.edu', 'Block C', 'Drafting Board', 1200.00, 1, 'Amit Kumar', 'amit@ybl', 'Stationery', 'Cash', 'Pending', '2023-10-02 11:30:00', 'Confirmed'),
(103, 'Rahul Sharma', 'rahul@college.edu', 'Block A', 'Lab Coat', 300.00, 1, 'Rohan Verma', 'rohan@paytm', 'Clothing', 'UPI', 'Completed', '2023-10-05 09:15:00', 'Confirmed');

-- ============================================================================
-- 2. FUNCTIONAL DEPENDENCIES (FDs)
-- ============================================================================
-- A Functional Dependency (X -> Y) means that if we know the value of attribute X,
-- it uniquely determines the value of attribute Y. In other words, for any two rows
-- with the same value of X, they MUST have the same value of Y.

-- FDs in ORDER_RAW:
-- FD1: order_id -> buyer_email, buyer_name, buyer_hostel, order_date, order_status, payment_method, payment_status
--      (An order is placed by one buyer at a specific time with a specific status and payment)
-- FD2: buyer_email -> buyer_name, buyer_hostel
--      (A buyer's email uniquely identifies their name and hostel)
-- FD3: {order_id, item_name} -> item_price, item_qty, seller_name, seller_upi, category_name
--      (To know the details of an item bought, we need both the order it belongs to and the item name)
-- FD4: seller_name -> seller_upi 
--      (Assuming seller names are unique in this simplified scenario, a seller determines their UPI)


-- ============================================================================
-- 3. DATA ANOMALIES IN UNNORMALIZED FORM
-- ============================================================================
-- Since ORDER_RAW has multiple facts mixed together, it suffers from anomalies:

-- a. INSERT Anomaly: 
-- We cannot add a new seller (e.g., 'Vikram') and their UPI ID ('vikram@sbi') 
-- into the system unless they have actually made a sale (an order exists). 
-- We would have to insert NULLs for order_id, buyer details, etc., which violates entity integrity if order_id is part of the primary key.

-- b. UPDATE Anomaly:
-- If 'Rahul Sharma' moves from 'Block A' to 'Block B', we must update multiple rows 
-- (two rows for order 101, one row for order 103). If we miss one, the database 
-- becomes inconsistent (Rahul is in two different hostels simultaneously).

-- c. DELETE Anomaly:
-- If we delete order 102 (perhaps it was cancelled), we also completely lose the fact 
-- that 'Neha Gupta' lives in 'Block C', and that 'Drafting Board' belongs to 'Stationery'.


-- ============================================================================
-- 4. STEP-BY-STEP DECOMPOSITION
-- ============================================================================

-- ----------------------------------------------------------------------------
-- a. FIRST NORMAL FORM (1NF)
-- ----------------------------------------------------------------------------
-- Definition: A table is in 1NF if every column contains atomic (indivisible) values,
-- and there are no repeating groups or arrays.
-- Status: ORDER_RAW is already in 1NF because all attributes contain single, atomic values.
-- Let's define the primary key for our 1NF table. 
-- Since an order can have multiple items, order_id alone is not unique.
-- The composite key is {order_id, item_name}.


-- ----------------------------------------------------------------------------
-- b. SECOND NORMAL FORM (2NF)
-- ----------------------------------------------------------------------------
-- Definition: A table is in 2NF if it is in 1NF AND there are no partial dependencies.
-- A partial dependency occurs when a non-prime attribute depends on only a PART of a composite candidate key.

-- Analysis of ORDER_RAW (Key = {order_id, item_name}):
-- - buyer_email, order_date, etc., depend ONLY on order_id (Partial Dependency).
-- - item_price, item_qty depend on the full key {order_id, item_name} (Full Dependency).

-- Decomposition into 2NF:
-- We separate attributes depending only on order_id into an ORDERS_2NF table.
-- The rest stay in ORDER_ITEMS_2NF.

DROP TABLE IF EXISTS ORDER_ITEMS_2NF;
DROP TABLE IF EXISTS ORDERS_2NF;

CREATE TABLE ORDERS_2NF (
    order_id INT PRIMARY KEY,
    buyer_email VARCHAR(150),
    buyer_name VARCHAR(100),
    buyer_hostel VARCHAR(20),
    payment_method VARCHAR(20),
    payment_status VARCHAR(20),
    order_date DATETIME,
    order_status VARCHAR(20)
);

CREATE TABLE ORDER_ITEMS_2NF (
    order_id INT,
    item_name VARCHAR(200),
    item_price DECIMAL(10,2),
    item_qty INT,
    seller_name VARCHAR(100),
    seller_upi VARCHAR(50),
    category_name VARCHAR(100),
    PRIMARY KEY (order_id, item_name)
);


-- ----------------------------------------------------------------------------
-- c. THIRD NORMAL FORM (3NF)
-- ----------------------------------------------------------------------------
-- Definition: A table is in 3NF if it is in 2NF AND there are no transitive dependencies.
-- A transitive dependency occurs when A -> B and B -> C, meaning a non-prime attribute 
-- determines another non-prime attribute.

-- Analysis of 2NF Tables:
-- In ORDERS_2NF: order_id -> buyer_email -> buyer_name, buyer_hostel. 
-- buyer_name and buyer_hostel depend transitively on order_id via buyer_email.
-- In ORDER_ITEMS_2NF: {order_id, item_name} -> seller_name -> seller_upi.
-- seller_upi depends transitively on the primary key via seller_name.

-- Decomposition into 3NF:
-- We create separate tables for USERS (Buyers/Sellers) to remove these transitive dependencies.

DROP TABLE IF EXISTS ORDER_ITEMS_3NF;
DROP TABLE IF EXISTS ORDERS_3NF;
DROP TABLE IF EXISTS SELLERS_3NF;
DROP TABLE IF EXISTS BUYERS_3NF;

CREATE TABLE BUYERS_3NF (
    buyer_email VARCHAR(150) PRIMARY KEY,
    buyer_name VARCHAR(100),
    buyer_hostel VARCHAR(20)
);

CREATE TABLE ORDERS_3NF (
    order_id INT PRIMARY KEY,
    buyer_email VARCHAR(150), -- Foreign Key
    payment_method VARCHAR(20),
    payment_status VARCHAR(20),
    order_date DATETIME,
    order_status VARCHAR(20)
);

CREATE TABLE SELLERS_3NF (
    seller_name VARCHAR(100) PRIMARY KEY,
    seller_upi VARCHAR(50)
);

-- Note: In a real system (like our final schema), items would also have their own table (LISTINGS).
-- For this step-by-step based purely on our initial FDs, we'll keep items linked to orders.
CREATE TABLE ORDER_ITEMS_3NF (
    order_id INT,
    item_name VARCHAR(200),
    item_price DECIMAL(10,2),
    item_qty INT,
    seller_name VARCHAR(100), -- Foreign Key
    category_name VARCHAR(100),
    PRIMARY KEY (order_id, item_name)
);


-- ----------------------------------------------------------------------------
-- d. BOYCE-CODD NORMAL FORM (BCNF)
-- ----------------------------------------------------------------------------
-- Definition: A table is in BCNF if for every non-trivial functional dependency X -> Y, 
-- X is a superkey. It is a stricter version of 3NF.

-- Analysis of 3NF Tables:
-- BUYERS_3NF: FD is buyer_email -> buyer_name, buyer_hostel. buyer_email is the primary key (superkey). -> In BCNF.
-- ORDERS_3NF: FD is order_id -> buyer_email, payment_method, etc. order_id is primary key (superkey). -> In BCNF.
-- SELLERS_3NF: FD is seller_name -> seller_upi. seller_name is primary key (superkey). -> In BCNF.
-- ORDER_ITEMS_3NF: The determinant is {order_id, item_name}, which is the candidate key. -> In BCNF.

-- Conclusion: Our 3NF decomposition is already in BCNF based on the stated FDs.
-- These tables map closely to the Users, Orders, and Order_Items tables in our final schema.sql.


-- ============================================================================
-- 5. ATTRIBUTE CLOSURE EXAMPLE
-- ============================================================================
-- Let's compute the closure of the attribute set {order_id, item_name} 
-- denoted as {order_id, item_name}+

-- Step 1: Initialize the closure with the attributes themselves.
-- Closure = {order_id, item_name}

-- Step 2: Apply FD1: order_id -> buyer_email, order_date, order_status, payment_method, payment_status
-- Since order_id is in our closure, we can add the right side.
-- Closure = {order_id, item_name, buyer_email, order_date, order_status, payment_method, payment_status}

-- Step 3: Apply FD2: buyer_email -> buyer_name, buyer_hostel
-- Since buyer_email is now in our closure, we add the right side.
-- Closure = {order_id, item_name, buyer_email, order_date, order_status, payment_method, payment_status, buyer_name, buyer_hostel}

-- Step 4: Apply FD3: {order_id, item_name} -> item_price, item_qty, seller_name, category_name, seller_upi (from transitiveness)
-- Actually FD3 explicitly gave us item_price, item_qty, seller_name, category_name.
-- Closure = {order_id, item_name, buyer_email, order_date, order_status, payment_method, payment_status, buyer_name, buyer_hostel, item_price, item_qty, seller_name, category_name}

-- Step 5: Apply FD4: seller_name -> seller_upi
-- Closure = {order_id, item_name, buyer_email, order_date, order_status, payment_method, payment_status, buyer_name, buyer_hostel, item_price, item_qty, seller_name, category_name, seller_upi}

-- Conclusion:
-- The closure {order_id, item_name}+ contains ALL attributes of the ORDER_RAW table.
-- Therefore, {order_id, item_name} is a Superkey (and Candidate Key) for ORDER_RAW.
