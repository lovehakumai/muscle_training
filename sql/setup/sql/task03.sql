-- 1. 加盟店マスタ
CREATE OR REPLACE TRANSIENT TABLE raw_merchants (
    merchant_id VARCHAR,
    merchant_name VARCHAR,
    category VARCHAR,
    country_code VARCHAR
);

-- 2. 決済端末マスタ（SCD Type 2履歴形式：1つの加盟店に複数端末が存在し、履歴行もある）
CREATE OR REPLACE TRANSIENT TABLE raw_terminals (
    terminal_id VARCHAR,
    merchant_id VARCHAR,
    terminal_model VARCHAR,
    is_active BOOLEAN,
    valid_from TIMESTAMP_NTZ,
    valid_to TIMESTAMP_NTZ
);

-- 3. 決済トランザクションテーブル（本番では数億行規模。巨大なペイロードを含む）
CREATE OR REPLACE TRANSIENT TABLE raw_transactions (
    transaction_id VARCHAR,
    merchant_id VARCHAR,
    terminal_id VARCHAR,
    transaction_timestamp TIMESTAMP_NTZ,
    transaction_status VARCHAR,
    amount DECIMAL(12,2),
    fee_amount DECIMAL(12,2),
    raw_payload VARCHAR,          -- 巨大なデバッグ用JSONテキスト（Spillageの元凶）
    user_agent_details VARCHAR    -- 巨大な文字列
);

-- テストデータのインサート
INSERT INTO raw_merchants (merchant_id, merchant_name, category, country_code) VALUES
('MCH_001', 'Tokyo Bistro', 'FOOD_BEVERAGE', 'JP'),
('MCH_002', 'Global Retail US', 'RETAIL', 'US'),
('MCH_003', 'Kyoto Sweets', 'FOOD_BEVERAGE', 'JP');

INSERT INTO raw_terminals (terminal_id, merchant_id, terminal_model, is_active, valid_from, valid_to) VALUES
-- MCH_001の端末（旧端末と現行端末）
('TRM_101', 'MCH_001', 'MODEL_A', FALSE, '2025-01-01 00:00:00', '2026-06-30 23:59:59'),
('TRM_101', 'MCH_001', 'MODEL_A_V2', TRUE, '2026-07-01 00:00:00', NULL),
('TRM_102', 'MCH_001', 'MODEL_B', TRUE, '2026-01-01 00:00:00', NULL),

-- MCH_002の端末
('TRM_201', 'MCH_002', 'MODEL_X', TRUE, '2026-01-01 00:00:00', NULL);

INSERT INTO raw_transactions (
    transaction_id, 
    merchant_id, 
    terminal_id, 
    transaction_timestamp, 
    transaction_status, 
    amount, 
    fee_amount, 
    raw_payload, 
    user_agent_details
)
-- 正常系: 2026年7月のSETTLEDトランザクション（対象）
SELECT 'TX_001', 'MCH_001', 'TRM_101', '2026-07-05 14:00:00'::TIMESTAMP_NTZ, 'SETTLED', 1000.00, 30.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_002', 'MCH_001', 'TRM_102', '2026-07-15 18:30:00'::TIMESTAMP_NTZ, 'SETTLED', 2500.00, 75.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_003', 'MCH_002', 'TRM_201', '2026-07-20 10:15:00'::TIMESTAMP_NTZ, 'SETTLED', 500.00, 15.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 US-Client'
UNION ALL
-- 罠1: 2026年7月だが、ステータスがFAILEDやREFUNDED（集計対象外。早期除外されるべき）
SELECT 'TX_004', 'MCH_001', 'TRM_101', '2026-07-08 12:00:00'::TIMESTAMP_NTZ, 'FAILED', 8000.00, 0.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_005', 'MCH_002', 'TRM_201', '2026-07-22 16:00:00'::TIMESTAMP_NTZ, 'REFUNDED', 300.00, 9.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 US-Client'
UNION ALL
-- 罠2: 対象ステータス(SETTLED)だが、過去月または未来月（2026年6月や8月。パーティション刈り込みで早期除外されるべき）
SELECT 'TX_006', 'MCH_001', 'TRM_101', '2026-06-30 23:55:00'::TIMESTAMP_NTZ, 'SETTLED', 4000.00, 120.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Tokyo-Client'
UNION ALL
SELECT 'TX_007', 'MCH_003', 'TRM_301', '2026-08-01 01:00:00'::TIMESTAMP_NTZ, 'SETTLED', 1200.00, 36.00, REPEAT('DUMMY_JSON_PAYLOAD_', 50), 'Mozilla/5.0 Kyoto-Client';