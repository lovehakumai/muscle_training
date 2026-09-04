USE SCHEMA MUSCLE_DB_TASK04.RAW;
-- EXECUTED ON TUESDAY
SET SESSION_DATE = '2026-09-01 00:00:00.000'::timestamp_ntz;
with base as (
    select * from raw_weekly_sales order by sale_timestamp 
)
, raw_get_baseline as (
-- get baseline by executing day
    select
        sale_id
        , sale_timestamp
        , amount
        , dateadd(day, -(DAYOFWEEKISO($SESSION_DATE) - 1) - 7, $SESSION_DATE) as baseline
        , case 
            when datediff('day', baseline, sale_timestamp) between 0 and 7 then true 
            else false end as target_flg
    from 
        base
)
, raw_extract_targets as (
    select
        MIN(baseline) as week
        , SUM(amount) as amount_sum
    from raw_get_baseline
    where target_flg
)

select * from raw_extract_targets;