with base as (
    select * from {{ source('ecommerce', 'raw_transactions') }}
)
, rename as (
    select 
        transaction_id::varchar as transaction_id
        , user_id::int as user_id 
        , transaction_timestamp::timestamp as transaction_timestamp
        , purchase_amount::int as purchase_amount
        , points_earned::int as points_earned
    from base 
)
select * from rename 