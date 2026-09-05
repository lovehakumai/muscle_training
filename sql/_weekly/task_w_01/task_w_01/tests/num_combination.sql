with base as (
    select 
        *
    from {{ ref("int_transactions_cleanse") }}
)
, final as (
    select 
        *
    from base 
    where 
        (purchase_amount < 0 and points_earned > 0)
        or (purchase_amount > 0 and points_earned < 0)
        or (purchase_amount is not null and points_earned is null )
        or (purchase_amount is null and points_earned is not null )
)
select * from final;