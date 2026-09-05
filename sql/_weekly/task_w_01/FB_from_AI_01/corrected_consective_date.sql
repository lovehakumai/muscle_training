/*
  [修正版スクリプトの差分]
  - user_id 単位ではなく、システム全体の日付の一覧を `distinct` で取得するように変更
  - datediff が != 1 ではなく > 1 のとき（1日以上スキップしたとき）に失敗するよう条件を変更
    （複数ユーザーによる同日重複で差分0となり、テストが誤検知で落ちるバグを防ぐため）
*/
with daily_dates as (
    -- 修正版のモデルでカラム名が date になっている想定
    select distinct date as cur_date
    from {{ ref('fct_user_daily_points') }}
),
base as (
    select
        cur_date,
        lag(cur_date) over (order by cur_date) as pre_date
    from daily_dates
)
select 
    1
from base
where pre_date is not null 
  and datediff('day', pre_date, cur_date) > 1
