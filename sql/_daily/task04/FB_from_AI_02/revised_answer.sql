-- 修正版: 全ての指摘と制約（2段階CTE、dbt互換の単一SELECT）を満たす形
-- 注記: コードは実行せず、机上トレースで構築しています。
-- 
-- 差分の理由:
-- 1. DATE_TRUNC の追加: $SESSION_DATE の時刻成分を捨てて境界を正規化し、未明の売上欠損を防ぐ
-- 2. CTEは2段階: boundaries(1段目) で境界を1行作り、targets(2段目) で LEFT JOIN して集計
-- 3. 単一 SELECT: dbt モデルにそのまま載せられるよう、SET による境界計算を避ける
-- 4. 半開区間: >= と < を使用し、対象カラムを加工しない（Sargable）
-- 5. 0件考慮: 0件でも週ラベルが出るよう集計キーにし、金額は COALESCE で0埋め

-- dbtモデル化を見据え、USE SCHEMAは本来不要ですが検証用に残します
USE SCHEMA MUSCLE_DB_TASK04.RAW;
SET SESSION_DATE = '2026-09-01 03:15:00.000'::timestamp_ntz;

with date_boundaries as (
    -- 1段目: 境界値の定数化 (DATE_TRUNC で時刻を落とす)
    select
        date_trunc('day', dateadd(day, -(dayofweekiso($SESSION_DATE) - 1) - 7, $SESSION_DATE)) as week_start,
        dateadd(day, 7, date_trunc('day', dateadd(day, -(dayofweekiso($SESSION_DATE) - 1) - 7, $SESSION_DATE))) as week_end
)
, extract_targets as (
    -- 2段目: 境界との LEFT JOIN でプルーニングを効かせつつ、0件入力時も 1行を確定させる
    select
        b.week_start as week_start_date,
        coalesce(sum(s.amount), 0) as amount_sum
    from date_boundaries b
    left join raw_weekly_sales s
        on s.sale_timestamp >= b.week_start
        and s.sale_timestamp < b.week_end
    group by b.week_start
)
select * from extract_targets;
