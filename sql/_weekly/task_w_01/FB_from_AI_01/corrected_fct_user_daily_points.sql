/*
  [修正版スクリプトの差分]
  - 要件で指定された通り、集計軸の日付カラム名を `transaction_timestamp` から `date` にリネーム
  - 要件で指定された通り、ポイントの合計カラム名を `points_earned` から `total_points_earned` にリネーム
  - 要件で指定された通り、その日のトランザクション数を表す `transaction_count` を追加
*/
with base as (
    select * from {{ ref('int_transactions_cleanse') }}
)
, final as (
    select
        user_id  
        , date_trunc('day', transaction_timestamp)::date as date
        , sum(purchase_amount) as purchase_amount
        , sum(points_earned) as total_points_earned
        , count(transaction_id) as transaction_count
    from base 
    group by 
        user_id 
        , date_trunc('day', transaction_timestamp)
)
select * from final
