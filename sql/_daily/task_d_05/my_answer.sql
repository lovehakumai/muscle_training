-- ======================================
-- [SET VARIOUS] 
-- Set various baseline date here, it will be adjusted to the execution environment.
-- Use datetrunc function just in case of having the datetime with time.
-- ======================================
SET raw_target_dt = '2026-09-01 00:00:00'::TIMESTAMP_NTZ;
SET target_dt = date_trunc('day', $raw_target_dt);
with latest_sales_date as (
    select
        store_id
        , sales_date
        , amount
        , received_at
    from raw_daily_sales
    qualify
        row_number()over(partition by store_id order by received_at desc) = 1
)
select 
    NVL(sales_date, $target_dt) as sales_date
    , NVL(sum( amount ), 0) as amount
from 
    latest_sales_date
where 
    sales_date = $target_dt
group by sales_date
;