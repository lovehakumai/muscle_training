with merchants as (
    select * from {{ ref('stg_apexpay__raw_merchants') }}
)
, terminals as (
    select * from {{ ref('stg_apexpay__raw_terminals') }}
)
, transactions as (
    select * from {{ ref('stg_apexpay__raw_transactions') }}
)

, agg_tran_by_merchant as (
    select 
        merchant_id
        , count(*) as settled_tx_count 
        , sum(amount) as total_settled_amount
        , sum(fee_amount) as total_fee_amount
    from 
        transactions 
    where
        transaction_status = 'SETTLED'
        and date_trunc(month, transaction_timestamp) = '2026-07-01'::timestamp
    group by 
        merchant_id
)
, agg_term_by_merchant as (
    select
        merchant_id
        , count(distinct terminal_id) as active_terminal_count
    from 
        terminals
    where 
        valid_to is null 
        and is_active = true 
    group by 
        merchant_id
)
, final as (
    select
        merchant_id
        , merchant_name
        , country_code
        , total_settled_amount
        , total_fee_amount
        , settled_tx_count
        , active_terminal_count
    from merchants 
    inner join agg_tran_by_merchant
    using(merchant_id)
    inner join agg_term_by_merchant
    using(merchant_id)
    
)
select * from final