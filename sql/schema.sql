-- ============================================================================
-- CampusSwap — Campus Marketplace Database Schema
-- Database  : MySQL 8.0+
-- Run       : mysql -u root -p < schema.sql
-- ============================================================================
-- WHY MySQL?
--   Your college teaches Oracle SQL*Plus, but MySQL is free, runs on any
--   laptop, and supports triggers, procedures, transactions, and CHECK
--   constraints (from v8.0). The SQL is 95% identical; differences are
--   noted in comments so you can defend the choice in viva.
-- ============================================================================

DROP DATABASE IF EXISTS campusswap;
CREATE DATABASE campusswap CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE campusswap;

-- ============================================================================
-- 1. USER — any registered student on the platform
-- ============================================================================
-- DESIGN DECISION: We keep one USER table and add optional SELLER / BUYER
-- child tables. This is "overlapping, partial" specialization because a user
-- can be both a seller AND a buyer, and some users may be neither yet.
-- In Oracle you would use VARCHAR2 instead of VARCHAR; rest stays the same.

CREATE TABLE `USER` (
    user_id       INT           AUTO_INCREMENT,
    name          VARCHAR(100)  NOT NULL,
    email         VARCHAR(150)  NOT NULL,
    phone         VARCHAR(15),
    hostel_block  VARCHAR(20),           -- e.g. "Block-A", "Girls Hostel-2"
    room_no       VARCHAR(10),
    joined_at     DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_user       PRIMARY KEY (user_id),
    CONSTRAINT uq_user_email UNIQUE      (email)
    -- VIVA NOTE: UNIQUE on email prevents duplicate registrations.
    -- AUTO_INCREMENT is MySQL's version of Oracle's SEQUENCE + TRIGGER.
) ENGINE=InnoDB;


-- ============================================================================
-- 2. SELLER — specialization of USER (overlapping, partial)
-- ============================================================================
-- A user becomes a SELLER when they list their first item.
-- upi_id stores their UPI handle for receiving payments.

CREATE TABLE SELLER (
    seller_id    INT,
    upi_id       VARCHAR(50),
    total_sales  DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    avg_rating   DECIMAL(3,2)  NOT NULL DEFAULT 0.00,

    CONSTRAINT pk_seller PRIMARY KEY (seller_id),
    CONSTRAINT fk_seller_user FOREIGN KEY (seller_id)
        REFERENCES `USER`(user_id)
        ON DELETE CASCADE
    -- ON DELETE CASCADE: if the user account is deleted, their seller
    -- profile goes too. This maintains referential integrity.
) ENGINE=InnoDB;


-- ============================================================================
-- 3. BUYER — specialization of USER (overlapping, partial)
-- ============================================================================
-- A user becomes a BUYER when they place their first order.

CREATE TABLE BUYER (
    buyer_id        INT,
    wallet_balance  DECIMAL(10,2) NOT NULL DEFAULT 0.00,

    CONSTRAINT pk_buyer PRIMARY KEY (buyer_id),
    CONSTRAINT fk_buyer_user FOREIGN KEY (buyer_id)
        REFERENCES `USER`(user_id)
        ON DELETE CASCADE
) ENGINE=InnoDB;


-- ============================================================================
-- 4. CATEGORY — with self-referencing FK for sub-categories
-- ============================================================================
-- DESIGN DECISION: parent_category_id points back to the same table.
-- This lets us model "Books > Engineering > CSE" as a tree.
-- A NULL parent means it is a top-level (root) category.

CREATE TABLE CATEGORY (
    category_id         INT          AUTO_INCREMENT,
    name                VARCHAR(100) NOT NULL,
    parent_category_id  INT          DEFAULT NULL,

    CONSTRAINT pk_category PRIMARY KEY (category_id),
    CONSTRAINT fk_category_parent FOREIGN KEY (parent_category_id)
        REFERENCES CATEGORY(category_id)
        ON DELETE SET NULL
    -- ON DELETE SET NULL: if a parent category is removed, children become
    -- top-level instead of being deleted. Preserves data.
) ENGINE=InnoDB;


-- ============================================================================
-- 5. LISTING — an item put up for sale
-- ============================================================================
-- ENUM columns store a fixed set of allowed values. MySQL enforces them;
-- in Oracle you would use a CHECK constraint with IN(...) instead.

CREATE TABLE LISTING (
    listing_id   INT            AUTO_INCREMENT,
    seller_id    INT            NOT NULL,
    category_id  INT            NOT NULL,
    title        VARCHAR(200)   NOT NULL,
    description  TEXT,
    price        DECIMAL(10,2)  NOT NULL,
    quantity     INT            NOT NULL DEFAULT 1,
    `condition`  ENUM('NEW','LIKE_NEW','GOOD','FAIR','POOR') NOT NULL DEFAULT 'GOOD',
    status       ENUM('ACTIVE','SOLD','EXPIRED','REMOVED')   NOT NULL DEFAULT 'ACTIVE',
    image_url    VARCHAR(500),
    created_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    CONSTRAINT pk_listing       PRIMARY KEY (listing_id),
    CONSTRAINT fk_listing_seller   FOREIGN KEY (seller_id)
        REFERENCES SELLER(seller_id) ON DELETE CASCADE,
    CONSTRAINT fk_listing_category FOREIGN KEY (category_id)
        REFERENCES CATEGORY(category_id) ON DELETE RESTRICT,
    CONSTRAINT chk_listing_price CHECK (price > 0),
    CONSTRAINT chk_listing_qty   CHECK (quantity >= 0)
    -- CHECK (price > 0): prevents someone listing a free item by accident.
    -- ON DELETE RESTRICT on category: you can't delete a category that has
    -- listings — forces the admin to re-categorize first.
) ENGINE=InnoDB;


-- ============================================================================
-- 6. BOOK_DETAILS — specialization of LISTING for books
-- ============================================================================
-- Not every listing is a book. Only book listings get an entry here.
-- This is an IS-A relationship (LISTING --specializes--> BOOK_DETAILS).

CREATE TABLE BOOK_DETAILS (
    listing_id  INT,
    isbn        VARCHAR(20),
    author      VARCHAR(200),
    edition     VARCHAR(50),
    subject     VARCHAR(100),

    CONSTRAINT pk_book_details PRIMARY KEY (listing_id),
    CONSTRAINT fk_book_listing FOREIGN KEY (listing_id)
        REFERENCES LISTING(listing_id)
        ON DELETE CASCADE
    -- CASCADE: if the listing is deleted, its book details go too.
) ENGINE=InnoDB;


-- ============================================================================
-- 7. ORDERS — a purchase made by a buyer
-- ============================================================================
-- Named ORDERS (not ORDER) because ORDER is a reserved SQL keyword.

CREATE TABLE ORDERS (
    order_id      INT            AUTO_INCREMENT,
    buyer_id      INT            NOT NULL,
    order_date    DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,
    total_amount  DECIMAL(10,2)  NOT NULL DEFAULT 0.00,
    status        ENUM('PENDING','CONFIRMED','DELIVERED','CANCELLED')
                                 NOT NULL DEFAULT 'PENDING',

    CONSTRAINT pk_orders PRIMARY KEY (order_id),
    CONSTRAINT fk_orders_buyer FOREIGN KEY (buyer_id)
        REFERENCES BUYER(buyer_id) ON DELETE CASCADE,
    CONSTRAINT chk_order_total CHECK (total_amount >= 0)
) ENGINE=InnoDB;


-- ============================================================================
-- 8. ORDER_ITEM — line items within an order (many-to-many resolver)
-- ============================================================================
-- One order can contain multiple listings, and one listing can appear in
-- multiple orders. ORDER_ITEM resolves this M:N relationship.
-- price_at_purchase stores the price at the time of purchase — the listing
-- price might change later, but the invoice should stay the same.

CREATE TABLE ORDER_ITEM (
    item_id            INT           AUTO_INCREMENT,
    order_id           INT           NOT NULL,
    listing_id         INT           NOT NULL,
    quantity           INT           NOT NULL DEFAULT 1,
    price_at_purchase  DECIMAL(10,2) NOT NULL,

    CONSTRAINT pk_order_item PRIMARY KEY (item_id),
    CONSTRAINT fk_oi_order   FOREIGN KEY (order_id)
        REFERENCES ORDERS(order_id) ON DELETE CASCADE,
    CONSTRAINT fk_oi_listing FOREIGN KEY (listing_id)
        REFERENCES LISTING(listing_id) ON DELETE RESTRICT,
    CONSTRAINT chk_oi_qty   CHECK (quantity > 0),
    CONSTRAINT chk_oi_price CHECK (price_at_purchase > 0)
    -- ON DELETE RESTRICT on listing: we never delete a listing that has
    -- been ordered — it's part of the purchase history.
) ENGINE=InnoDB;


-- ============================================================================
-- 9. PAYMENT — payment details for an order
-- ============================================================================

CREATE TABLE PAYMENT (
    payment_id  INT            AUTO_INCREMENT,
    order_id    INT            NOT NULL,
    amount      DECIMAL(10,2)  NOT NULL,
    method      ENUM('UPI','CASH','WALLET') NOT NULL,
    status      ENUM('PENDING','COMPLETED','FAILED','REFUNDED')
                               NOT NULL DEFAULT 'PENDING',
    paid_at     DATETIME,

    CONSTRAINT pk_payment PRIMARY KEY (payment_id),
    CONSTRAINT fk_payment_order FOREIGN KEY (order_id)
        REFERENCES ORDERS(order_id) ON DELETE CASCADE,
    CONSTRAINT chk_payment_amt CHECK (amount > 0)
) ENGINE=InnoDB;


-- ============================================================================
-- 10. REQUEST — "wanted" posts by students looking for specific items
-- ============================================================================

CREATE TABLE REQUEST (
    request_id   INT            AUTO_INCREMENT,
    user_id      INT            NOT NULL,
    category_id  INT,
    title        VARCHAR(200)   NOT NULL,
    description  TEXT,
    budget_max   DECIMAL(10,2),
    status       ENUM('OPEN','FULFILLED','CLOSED') NOT NULL DEFAULT 'OPEN',
    created_at   DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_request PRIMARY KEY (request_id),
    CONSTRAINT fk_request_user FOREIGN KEY (user_id)
        REFERENCES `USER`(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_request_category FOREIGN KEY (category_id)
        REFERENCES CATEGORY(category_id) ON DELETE SET NULL,
    CONSTRAINT chk_request_budget CHECK (budget_max IS NULL OR budget_max > 0)
) ENGINE=InnoDB;


-- ============================================================================
-- 11. REVIEW — a buyer reviews a listing after purchase
-- ============================================================================

CREATE TABLE REVIEW (
    review_id    INT      AUTO_INCREMENT,
    reviewer_id  INT      NOT NULL,
    listing_id   INT      NOT NULL,
    rating       TINYINT  NOT NULL,
    comment      TEXT,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_review PRIMARY KEY (review_id),
    CONSTRAINT fk_review_user FOREIGN KEY (reviewer_id)
        REFERENCES `USER`(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_review_listing FOREIGN KEY (listing_id)
        REFERENCES LISTING(listing_id) ON DELETE CASCADE,
    CONSTRAINT chk_review_rating CHECK (rating BETWEEN 1 AND 5),
    CONSTRAINT uq_review_one_per_user UNIQUE (reviewer_id, listing_id)
    -- UNIQUE on (reviewer_id, listing_id): one review per user per listing.
    -- CHECK rating BETWEEN 1 AND 5: exactly what the project requires.
) ENGINE=InnoDB;


-- ============================================================================
-- 12. PRICE_AUDIT — audit trail for price changes (used by Stage 6 trigger)
-- ============================================================================

CREATE TABLE PRICE_AUDIT (
    audit_id    INT            AUTO_INCREMENT,
    listing_id  INT            NOT NULL,
    old_price   DECIMAL(10,2)  NOT NULL,
    new_price   DECIMAL(10,2)  NOT NULL,
    changed_by  INT,
    changed_at  DATETIME       NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT pk_price_audit PRIMARY KEY (audit_id),
    CONSTRAINT fk_audit_listing FOREIGN KEY (listing_id)
        REFERENCES LISTING(listing_id) ON DELETE CASCADE
) ENGINE=InnoDB;


-- ============================================================================
-- VIVA QUICK REFERENCE
-- ============================================================================
-- Q: Why InnoDB?
-- A: InnoDB supports ACID transactions, row-level locking, and foreign keys.
--    MyISAM does not support FKs or transactions.
--
-- Q: Why DECIMAL instead of FLOAT for prices?
-- A: FLOAT has rounding errors (0.1 + 0.2 ≠ 0.3). DECIMAL stores exact
--    values, which is critical for money.
--
-- Q: Why ON DELETE CASCADE on some FKs and RESTRICT on others?
-- A: CASCADE removes child rows automatically (good for profiles, reviews).
--    RESTRICT prevents deletion if children exist (good for categories with
--    listings, listings with orders — we don't want to lose sales history).
--
-- Q: How is this different from Oracle?
-- A: AUTO_INCREMENT → Oracle uses SEQUENCE + TRIGGER or IDENTITY (12c+).
--    ENUM → Oracle uses CHECK with IN(...).
--    VARCHAR → Oracle uses VARCHAR2.
--    DATETIME → Oracle uses TIMESTAMP or DATE (which includes time).
-- ============================================================================
