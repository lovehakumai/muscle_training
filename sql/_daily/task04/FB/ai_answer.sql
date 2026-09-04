-- 基準となる実行日を設定
SET SESSION_DATE = '2026-09-01 00:00:00.000'::timestamp_ntz;

-- 1. 最初に「先週の開始日時」と「終了日時」を1行だけ算出して定数化する
with date_boundaries as (
    select
        -- 先週月曜の 00:00:00 を算出
        date_trunc('day', dateadd(day, -(dayofweekiso($SESSION_DATE) - 1) - 7, $SESSION_DATE)) as last_week_start,
        -- 今週月曜の 00:00:00 (先週日曜 23:59:59 の直後) を算出
        dateadd(day, 7, last_week_start) as last_week_end
),

-- 2. メインテーブルに生のまま範囲条件を当てて、高速に集計する（2段階目のCTE）
raw_extract_targets as (
    select
        (select last_week_start from date_boundaries) as week,
        sum(amount) as amount_sum
    from raw_weekly_sales
    where
        -- カラムに関数をかけず生のまま比較する（Sargableな範囲指定）
        sale_timestamp >= (select last_week_start from date_boundaries)
        and sale_timestamp < (select last_week_end from date_boundaries)
)

select * from raw_extract_targets;