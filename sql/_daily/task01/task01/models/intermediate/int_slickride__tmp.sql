WITH base AS (
    SELECT * FROM {{ ref('stg_slickride__raw_ride_updates') }}
)
SELECT 
    ride_id,
    passenger_name,
    updated_at,
    ride_status,
    fare_amount,
    -- 1. 監査カラム：同じ ride_id かつ同じ updated_at のレコードが2件以上存在するか
    IFF(COUNT(*) OVER (PARTITION BY ride_id, updated_at) > 1, TRUE, FALSE) AS is_duplicate_at_timestamp
FROM base
-- 2. QUALIFY句で「乗車IDごと」の最新1行のみを直接 Top-K 抽出
QUALIFY ROW_NUMBER() OVER (
    PARTITION BY ride_id
    ORDER BY 
        updated_at DESC,                                        -- 最新のタイムスタンプを優先
        CASE ride_status                                        -- ステータス優先度を決定論的にマッピング
            WHEN 'CANCELLED' THEN 6
            WHEN 'COMPLETED' THEN 5
            WHEN 'PICKED_UP'  THEN 4
            WHEN 'ARRIVED'    THEN 3
            WHEN 'ACCEPTED'   THEN 2
            WHEN 'REQUESTED'  THEN 1
            ELSE 0
        END DESC,
        system_record_id DESC                                   -- 完全物理重複時のタイブレーク
) = 1
{# SELECT 
    system_record_id
    , ride_id
    , updated_at
    , passenger_name
    , fare_amount  
    , RIGHT(ride_status_label, LEN(ride_status_label)-2) AS ride_status
    , CASE WHEN COUNT(*)OVER( 
        PARTITION BY max_updated_at_flg, ride_id
    ) > 1 THEN TRUE ELSE FALSE END AS is_duplicate_at_timestamp
FROM 
(
    SELECT
        system_record_id
        , ride_id
        , updated_at
        , passenger_name
        , fare_amount
        , MAX(CASE 
            WHEN ride_status = 'REQUESTED' THEN '1.REQUESTED'
            WHEN ride_status = 'ACCEPTED' THEN '2.ACCEPTED'
            WHEN ride_status = 'ARRIVED' THEN '3.ARRIVED'
            WHEN ride_status = 'PICKED_UP' THEN '4.PICKED_UP'
            WHEN ride_status = 'COMPLETED' THEN '5.COMPLETED'
            WHEN ride_status = 'CANCELLED' THEN '6.CANCELLED'
        END)OVER(PARTITION BY system_record_id, ride_id, updated_at) AS ride_status_label
        , CASE WHEN MAX(updated_at)OVER(
            PARTITION BY NULL
        ) = updated_at THEN TRUE ELSE NULL END AS max_updated_at_flg
    FROM base 
)
QUALIFY 
    ROW_NUMBER()OVER(
        PARTITION BY ride_id, updated_at
        ORDER BY system_record_id DESC 
    ) = 1 #}