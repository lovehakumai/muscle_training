-- ======================================
-- [SET VARIOUS] 
-- Set various baseline date here, it will be adjusted to the execution environment.
-- Use datetrunc function just in case of having the datetime with time.
-- ======================================
-- 修正内容:
-- 1. [Pass 1] QUALIFY 句の PARTITION BY に sales_date を追加（別日付のデータ欠損を修正）
-- 2. [Pass 1] SELECT 句の不要な NVL 関数を削除（GROUP BY しているため 0件時はそもそも行が生成されない）
-- 3. [Pass 2] 窓関数の実行前に CTE 内で WHERE 絞り込みを行うように移動（フルスキャン回避）
-- 4. [Pass 2] CTE 名を latest_sales_date から deduplicated_sales に変更
-- 注記: コードは実行していません
-- ======================================
SET raw_target_dt = '2026-09-01 00:00:00'::TIMESTAMP_NTZ;
SET target_dt = date_trunc('day', $raw_target_dt);

with deduplicated_sales as (
    select
        store_id
        , sales_date
        , amount
        , received_at
    from raw_daily_sales
    where sales_date = $target_dt
    qualify
        row_number()over(partition by store_id, sales_date order by received_at desc) = 1
)
select 
    sales_date
    , sum( amount ) as amount
from 
    deduplicated_sales
group by sales_date
;
