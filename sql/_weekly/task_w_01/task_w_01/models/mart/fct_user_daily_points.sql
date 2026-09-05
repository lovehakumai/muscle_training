{# 
    [PURPOSE]
        - Aggregate cleansed transaction table by date in transaction_timestamp and user_id, 
        - and calculate sum of `points_earned` and `purchase_amount`. 
        
 #}
with base as (
    select * from {{ ref('int_transactions_cleanse') }}
)
, final as (
    select
        user_id  
        , date_trunc('day', transaction_timestamp) as transaction_timestamp
        , sum(purchase_amount) as purchase_amount
        , sum(points_earned) as points_earned
    from base 
    group by 
        user_id 
        , date_trunc('day', transaction_timestamp)
)
select * from final 