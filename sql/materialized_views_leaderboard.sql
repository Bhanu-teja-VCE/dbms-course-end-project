-- ============================================================================
-- Complex Engineering Problem: Real-Time Analytics Using Materialized Views
-- and Incremental Data Refresh
--
-- Database Engine : MySQL 8.0+ (InnoDB Storage Engine)
-- Target System   : High-Throughput Live Leaderboard Analytics
-- ============================================================================
-- OBJECTIVES:
-- 1. Build an events/score table that feeds a real-time leaderboard
-- 2. Implement the leaderboard as a plain view and measure its performance
-- 3. Implement it as a materialized view with full periodic refresh
-- 4. Implement incremental maintenance using active event triggers and summary tables
-- 5. Compare query latency, write overhead, and data freshness across all approaches
-- ============================================================================

DROP DATABASE IF EXISTS `leaderboard_analytics_db`;
CREATE DATABASE `leaderboard_analytics_db` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `leaderboard_analytics_db`;

-- ============================================================================
-- 1. BASE TABLES: USERS AND SCORE EVENTS
-- ============================================================================

-- Reference table for platform users
CREATE TABLE `users` (
    `user_id`       INT AUTO_INCREMENT PRIMARY KEY,
    `username`      VARCHAR(50) NOT NULL UNIQUE,
    `country_code`  VARCHAR(3)  NOT NULL DEFAULT 'IND',
    `registered_at` DATETIME    NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

-- High-throughput, append-only event log table
CREATE TABLE `user_score_event` (
    `event_id`      BIGINT AUTO_INCREMENT PRIMARY KEY,
    `user_id`       INT NOT NULL,
    `game_id`       INT NOT NULL,
    `score_delta`   INT NOT NULL,
    `created_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT `fk_event_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE,
    INDEX `idx_user_created` (`user_id`, `created_at`),
    INDEX `idx_score_delta` (`score_delta`)
) ENGINE=InnoDB;


-- ============================================================================
-- 2. APPROACH 1: PLAIN VIRTUAL VIEW
-- ============================================================================
-- CHARACTERISTICS:
-- - Computed dynamically on every read request (zero storage overhead).
-- - Zero write overhead on INSERT into user_score_event.
-- - Read Cost: O(N log N) — scans entire table, computes SUM, and sorts.
-- - Data Freshness: 100% real-time (instantaneous).
-- ============================================================================

CREATE OR REPLACE VIEW `v_leaderboard_plain` AS
SELECT 
    u.user_id,
    u.username,
    u.country_code,
    COALESCE(SUM(e.score_delta), 0) AS total_score,
    COUNT(e.event_id)               AS total_events,
    MAX(e.created_at)               AS last_activity_at,
    DENSE_RANK() OVER (ORDER BY COALESCE(SUM(e.score_delta), 0) DESC) AS `rank`
FROM `users` u
JOIN `user_score_event` e ON u.user_id = e.user_id
GROUP BY u.user_id, u.username, u.country_code;


-- ============================================================================
-- 3. APPROACH 2: MATERIALIZED VIEW (PHYSICAL TABLE WITH FULL REFRESH)
-- ============================================================================
-- CHARACTERISTICS:
-- - In MySQL (which lacks native MATERIALIZED VIEW statements like Oracle/Postgres),
--   a materialized view is modeled as a physical table populated by an atomic procedure.
-- - Read Cost: O(log U + k) — sub-millisecond B+ tree index range lookup.
-- - Write Cost: Zero overhead on individual inserts; large batch spike on refresh.
-- - Data Freshness: Stale (lag = elapsed time since last refresh).
-- ============================================================================

CREATE TABLE `mv_leaderboard_full` (
    `user_id`           INT PRIMARY KEY,
    `username`          VARCHAR(50) NOT NULL,
    `country_code`      VARCHAR(3)  NOT NULL,
    `total_score`       BIGINT      NOT NULL DEFAULT 0,
    `total_events`      INT         NOT NULL DEFAULT 0,
    `last_activity_at`  DATETIME    NULL,
    `leaderboard_rank`  INT         NOT NULL DEFAULT 0,
    `last_refreshed_at` DATETIME    NOT NULL,
    INDEX `idx_mv_rank` (`total_score` DESC, `user_id`)
) ENGINE=InnoDB;

-- Stored Procedure to execute an atomic Full Refresh
DELIMITER $$
CREATE PROCEDURE `sp_refresh_leaderboard_full`()
BEGIN
    DECLARE v_start_time DATETIME(6);
    DECLARE v_end_time   DATETIME(6);
    DECLARE v_elapsed_ms DECIMAL(10, 2);

    SET v_start_time = NOW(6);

    -- Atomic rebuild using a temporary staging table to minimize read lock downtime
    CREATE TEMPORARY TABLE `tmp_mv_refresh` LIKE `mv_leaderboard_full`;

    INSERT INTO `tmp_mv_refresh` (
        user_id, username, country_code, total_score, total_events, 
        last_activity_at, leaderboard_rank, last_refreshed_at
    )
    SELECT 
        u.user_id,
        u.username,
        u.country_code,
        COALESCE(SUM(e.score_delta), 0) AS total_score,
        COUNT(e.event_id)               AS total_events,
        MAX(e.created_at)               AS last_activity_at,
        DENSE_RANK() OVER (ORDER BY COALESCE(SUM(e.score_delta), 0) DESC) AS leaderboard_rank,
        NOW()                           AS last_refreshed_at
    FROM `users` u
    JOIN `user_score_event` e ON u.user_id = e.user_id
    GROUP BY u.user_id, u.username, u.country_code;

    -- Atomic swap into the destination materialized table
    START TRANSACTION;
    TRUNCATE TABLE `mv_leaderboard_full`;
    INSERT INTO `mv_leaderboard_full` SELECT * FROM `tmp_mv_refresh`;
    COMMIT;

    DROP TEMPORARY TABLE `tmp_mv_refresh`;

    SET v_end_time = NOW(6);
    SET v_elapsed_ms = TIMESTAMPDIFF(MICROSECOND, v_start_time, v_end_time) / 1000.0;

    SELECT 'Full Refresh Completed' AS `status`, v_elapsed_ms AS `elapsed_time_ms`;
END$$
DELIMITER ;


-- ============================================================================
-- 4. APPROACH 3: INCREMENTAL DATA REFRESH (EVENT-DRIVEN TRIGGERS)
-- ============================================================================
-- CHARACTERISTICS:
-- - Uses a persistent summary table maintained incrementally by active triggers.
-- - Read Cost: O(log U + k) — sub-millisecond using clustered index.
-- - Write Cost: O(log U) overhead per insert into user_score_event.
-- - Data Freshness: 100% real-time (zero staleness lag).
-- ============================================================================

CREATE TABLE `summary_leaderboard_incremental` (
    `user_id`           INT PRIMARY KEY,
    `total_score`       BIGINT   NOT NULL DEFAULT 0,
    `total_events`      INT      NOT NULL DEFAULT 0,
    `last_updated_at`   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    CONSTRAINT `fk_summary_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`user_id`) ON DELETE CASCADE,
    INDEX `idx_summary_score` (`total_score` DESC, `user_id`)
) ENGINE=InnoDB;

-- Trigger: Incrementally updates leaderboard on every score append
DELIMITER $$
CREATE TRIGGER `trg_incremental_score_insert`
AFTER INSERT ON `user_score_event`
FOR EACH ROW
BEGIN
    INSERT INTO `summary_leaderboard_incremental` (`user_id`, `total_score`, `total_events`, `last_updated_at`)
    VALUES (NEW.user_id, NEW.score_delta, 1, NOW())
    ON DUPLICATE KEY UPDATE
        `total_score`     = `total_score` + NEW.score_delta,
        `total_events`    = `total_events` + 1,
        `last_updated_at` = NOW();
END$$
DELIMITER ;


-- ============================================================================
-- 5. SEED DATA GENERATOR: POPULATING BENCHMARK DATASET
-- ============================================================================

DELIMITER $$
CREATE PROCEDURE `sp_seed_benchmark_data`(IN p_num_users INT, IN p_num_events INT)
BEGIN
    DECLARE i INT DEFAULT 1;
    DECLARE v_rand_user INT;
    DECLARE v_rand_score INT;

    -- Disable autocommit & indexes for bulk generation
    SET FOREIGN_KEY_CHECKS = 0;
    TRUNCATE TABLE `user_score_event`;
    TRUNCATE TABLE `summary_leaderboard_incremental`;
    TRUNCATE TABLE `users`;
    SET FOREIGN_KEY_CHECKS = 1;

    -- 1. Insert Users
    START TRANSACTION;
    WHILE i <= p_num_users DO
        INSERT INTO `users` (`username`, `country_code`) 
        VALUES (CONCAT('player_', i), ELT(1 + FLOOR(RAND()*5), 'IND', 'USA', 'GBR', 'SGP', 'DEU'));
        SET i = i + 1;
    END WHILE;
    COMMIT;

    -- 2. Insert Events in Batches (Fires Trigger for Incremental Table)
    SET i = 1;
    START TRANSACTION;
    WHILE i <= p_num_events DO
        SET v_rand_user  = 1 + FLOOR(RAND() * p_num_users);
        SET v_rand_score = 10 + FLOOR(RAND() * 500);

        INSERT INTO `user_score_event` (`user_id`, `game_id`, `score_delta`, `created_at`)
        VALUES (v_rand_user, 1 + FLOOR(RAND() * 10), v_rand_score, NOW() - INTERVAL FLOOR(RAND()*30) DAY);

        IF MOD(i, 5000) = 0 THEN
            COMMIT;
            START TRANSACTION;
        END IF;

        SET i = i + 1;
    END WHILE;
    COMMIT;

    -- Populate Materialized View initial snapshot
    CALL `sp_refresh_leaderboard_full`();

    SELECT 'Data Seeding Completed' AS `status`, p_num_users AS `users`, p_num_events AS `events`;
END$$
DELIMITER ;


-- ============================================================================
-- 6. BENCHMARK SUITE: LATENCY, THROUGHPUT & FRESHNESS MEASUREMENT
-- ============================================================================

-- Query 1: Top 10 Leaderboard via Plain View (Dynamic Evaluation)
-- EXPLAIN ANALYZE shows full scan + temp table + filesort:
-- EXPLAIN ANALYZE SELECT * FROM v_leaderboard_plain WHERE `rank` <= 10;
SELECT * FROM `v_leaderboard_plain` WHERE `rank` <= 10;

-- Query 2: Top 10 Leaderboard via Full-Refresh Materialized View
-- EXPLAIN ANALYZE shows index scan on idx_mv_rank:
-- EXPLAIN ANALYZE SELECT user_id, username, total_score, leaderboard_rank FROM mv_leaderboard_full ORDER BY total_score DESC LIMIT 10;
SELECT `user_id`, `username`, `total_score`, `leaderboard_rank` 
FROM `mv_leaderboard_full` 
ORDER BY `total_score` DESC 
LIMIT 10;

-- Query 3: Top 10 Leaderboard via Incremental Summary Table
-- EXPLAIN ANALYZE shows covering index scan on idx_summary_score:
SELECT 
    s.user_id,
    u.username,
    s.total_score,
    s.total_events,
    s.last_updated_at,
    DENSE_RANK() OVER (ORDER BY s.total_score DESC) AS `rank`
FROM `summary_leaderboard_incremental` s
JOIN `users` u ON s.user_id = u.user_id
ORDER BY s.total_score DESC
LIMIT 10;

-- ============================================================================
-- 7. FRESHNESS COMPARISON EXPERIMENT
-- ============================================================================
-- Insert a massive score delta for user_id = 1
-- Observe immediate reflection in Incremental Table vs Stale lag in Full MV:
--
-- INSERT INTO user_score_event (user_id, game_id, score_delta) VALUES (1, 99, 100000);
--
-- Check Incremental: Instantly updated!
-- SELECT * FROM summary_leaderboard_incremental WHERE user_id = 1;
--
-- Check Materialized View: Still shows previous score (Stale until sp_refresh_leaderboard_full() is called)!
-- SELECT * FROM mv_leaderboard_full WHERE user_id = 1;
-- ============================================================================
