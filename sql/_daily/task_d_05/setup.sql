CREATE OR REPLACE TABLE raw_daily_sales (
    store_id VARCHAR,
    sales_date DATE,
    amount NUMBER,
    received_at TIMESTAMP_NTZ
);

INSERT INTO raw_daily_sales VALUES
    -- 2026-08-31: 対象外の日付
    ('store_A', '2026-08-31', 1000, '2026-08-31 20:00:00'),
    
    -- 2026-09-02: 対象外の日付。通信遅延による重複再送あり
    ('store_B', '2026-09-02', 1500, '2026-09-02 21:00:00'),
    ('store_B', '2026-09-02', 2000, '2026-09-02 23:00:00');
