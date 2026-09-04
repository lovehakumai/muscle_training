CREATE DATABASE IF NOT EXISTS MUSCLE_DB_TASK01;
CREATE SCHEMA IF NOT EXISTS MUSCLE_DB_TASK01.PUBLIC;

USE DATABASE MUSCLE_DB_TASK01;
USE SCHEMA PUBLIC;
-- テスト用データベース・スキーマの設定
CREATE OR REPLACE TRANSIENT TABLE raw_ride_updates (
    system_record_id INT,
    ride_id VARCHAR,
    passenger_name VARCHAR,
    updated_at TIMESTAMP_NTZ,
    ride_status VARCHAR,
    fare_amount DECIMAL(10,2)
);

-- テストデータのインサート
INSERT INTO raw_ride_updates (system_record_id, ride_id, passenger_name, updated_at, ride_status, fare_amount) VALUES
-- ケース1: 通常の時系列更新（正常系。最新の 2026-08-23 10:15:00 が選ばれるべき）
(1001, 'RIDE_001', 'Alice', '2026-08-23 10:00:00', 'REQUESTED', 15.00),
(1002, 'RIDE_001', 'Alice', '2026-08-23 10:05:00', 'ACCEPTED', 15.00),
(1003, 'RIDE_001', 'Alice', '2026-08-23 10:15:00', 'PICKED_UP', 18.50),

-- ケース2: 同一時刻でのステータス競合（RIDE_002 の 11:00:00 に2レコード存在。優先度の高い ARRIVED が選ばれ、監査カラムは TRUE となるべき）
(1004, 'RIDE_002', 'Bob', '2026-08-23 10:55:00', 'REQUESTED', 22.00),
(1005, 'RIDE_002', 'Bob', '2026-08-23 11:00:00', 'ACCEPTED', 22.00),
(1006, 'RIDE_002', 'Bob', '2026-08-23 11:00:00', 'ARRIVED', 22.00),

-- ケース3: 同一時刻・同一ステータスでの完全な物理重複（RIDE_003 の 12:30:00。より大きい system_record_id = 1009 が選ばれ、監査カラムは TRUE となるべき）
(1007, 'RIDE_003', 'Charlie', '2026-08-23 12:00:00', 'REQUESTED', 30.00),
(1008, 'RIDE_003', 'Charlie', '2026-08-23 12:30:00', 'COMPLETED', 35.00),
(1009, 'RIDE_003', 'Charlie', '2026-08-23 12:30:00', 'COMPLETED', 35.00),

-- ケース4: 過去履歴に重複があるが、最新タイムスタンプ時点では単一レコード（RIDE_004。最新の 14:10:00 自体は重複していないため、監査カラムは FALSE となるべき）
(1010, 'RIDE_004', 'David', '2026-08-23 14:00:00', 'REQUESTED', 10.00),
(1011, 'RIDE_004', 'David', '2026-08-23 14:00:00', 'ACCEPTED', 10.00),
(1012, 'RIDE_004', 'David', '2026-08-23 14:10:00', 'COMPLETED', 12.00);