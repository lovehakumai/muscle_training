with base as (
    select  
        transaction_timestamp as cur_transaction_timestamp
        , lag(transaction_timestamp)over(order by transaction_timestamp) as pre_transaction_timestamp
    from {{ ref('fct_user_daily_points') }}
)
select 
    1
from base
where datediff('day', pre_transaction_timestamp, cur_transaction_timestamp ) != 1  