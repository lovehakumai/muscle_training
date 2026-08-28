-- テスト用テーブルの作成
CREATE OR REPLACE TRANSIENT TABLE raw_user_clickstream (
    event_id VARCHAR,
    user_id VARCHAR,
    country_code VARCHAR,
    event_timestamp TIMESTAMP_NTZ,
    event_payload VARIANT
);

-- テストデータのインサート
INSERT INTO raw_user_clickstream (event_id, user_id, country_code, event_timestamp, event_payload)
SELECT 
    'EVT_101', 'USR_001', 'US', '2026-08-25 10:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "iOS",
        "interactions": [
            {"item_id": "PROD_A", "action_type": "IMPRESSION", "price": 10.00, "applied_discount": false},
            {"item_id": "PROD_B", "action_type": "PURCHASE_INTENT", "price": 49.99, "applied_discount": true},
            {"item_id": "PROD_C", "action_type": "CLICK", "price": 15.50}
        ]
    }')
UNION ALL
SELECT 
    'EVT_102', 'USR_002', 'US', '2026-08-25 11:30:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Android",
        "interactions": [
            {"item_id": "PROD_D", "action_type": "PURCHASE_INTENT", "price": 120.00, "applied_discount": null},
            {"item_id": "PROD_E", "action_type": "PURCHASE_INTENT", "price": 5.00, "applied_discount": false}
        ]
    }')
UNION ALL
-- 罠1: 対象外リージョン（EU）かつ膨大な配列データ（展開前に除外されるべき）
SELECT 
    'EVT_103', 'USR_BOT_01', 'EU', '2026-08-25 12:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Bot",
        "interactions": [
            {"item_id": "SPAM_1", "action_type": "PURCHASE_INTENT", "price": 999.00},
            {"item_id": "SPAM_2", "action_type": "PURCHASE_INTENT", "price": 999.00},
            {"item_id": "SPAM_3", "action_type": "PURCHASE_INTENT", "price": 999.00}
        ]
    }')
UNION ALL
-- 罠2: 対象外日時（過去データ。展開前にプルーニングされるべき）
SELECT 
    'EVT_104', 'USR_003', 'US', '2026-08-20 09:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Web",
        "interactions": [
            {"item_id": "PROD_OLD", "action_type": "PURCHASE_INTENT", "price": 30.00, "applied_discount": true}
        ]
    }')
UNION ALL
-- 罠3: 対象レコードだが PURCHASE_INTENT が配列内に1件も存在しないケース
SELECT 
    'EVT_105', 'USR_004', 'US', '2026-08-25 15:00:00'::TIMESTAMP_NTZ,
    PARSE_JSON('{
        "device": "Web",
        "interactions": [
            {"item_id": "PROD_VIEW_ONLY", "action_type": "IMPRESSION", "price": 25.00}
        ]
    }');