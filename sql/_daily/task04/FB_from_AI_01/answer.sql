-- 修正内容：
-- 1. GROUP BY を追加し、0件入力時に (NULL, NULL) が返るバグを修正
-- 2. Sargableな範囲指定（>= と <）に変更し、パーティションプルーニングを有効化
-- 3. CTEを2段階に削減（無意味な ORDER BY を持つ base CTE を削除）
-- 4. 実行日時に時刻が含まれていても安全なように DATE_TRUNC を追加
-- 5. スカラサブクエリによるオプティマイザ依存を避け、CROSS JOIN で確実に定数を結合
-- 6. raw_ 接頭辞を外し、命名を処理の実態に適合させた
-- ※ 本コードは実行していません（机上トレースのみ）

SET SESSION_DATE = '2026-09-01 00:00:00.000'::timestamp_ntz;

WITH date_boundaries AS (
    -- SESSION_DATE の時刻成分を切り捨ててから週の開始を計算
    SELECT
        DATE_TRUNC('DAY', DATEADD(DAY, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE)) AS week_start_date
),
extract_targets AS (
    SELECT
        b.week_start_date AS week,
        SUM(s.amount) AS amount_sum
    FROM 
        raw_weekly_sales s
    CROSS JOIN 
        date_boundaries b
    WHERE 
        -- Sargableな条件指定（カラムを関数で加工しない）
        s.sale_timestamp >= b.week_start_date
        AND s.sale_timestamp < DATEADD(DAY, 7, b.week_start_date)
    GROUP BY 
        b.week_start_date
)
SELECT * FROM extract_targets;
