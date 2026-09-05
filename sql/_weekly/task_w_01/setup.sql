CREATE DATABASE IF NOT EXISTS MUSCLE_TRAINING;
USE DATABASE MUSCLE_TRAINING;
CREATE SCHEMA IF NOT EXISTS RAW;
USE SCHEMA RAW;

CREATE OR REPLACE TABLE raw_transactions (
    transaction_id VARCHAR,
    user_id INT,
    transaction_timestamp TIMESTAMP,
    purchase_amount INT,
    points_earned INT
);

INSERT INTO raw_transactions (transaction_id, user_id, transaction_timestamp, purchase_amount, points_earned) VALUES
('TXN-001', 1, '2026-09-01 10:00:00', 1000, 10),
('TXN-002', 2, '2026-09-01 11:30:00', 500, 5),
('TXN-003', 3, '2026-09-02 12:00:00', 2000, 20),
('TXN-003', 3, '2026-09-02 12:05:00', 2000, 20),
('TXN-004', 1, '2026-09-02 15:00:00', -1000, -10),
('TXN-005', 4, '2026-09-03 09:00:00', 300, NULL),
('TXN-006', 5, '2026-09-05 10:00:00', 99999999, 999999)
