with base as (
    select * from {{ref('stg_omnicart__raw_user_clickstream')}}
)
, extract_data as (
    select 
        event_id,
        user_id,
        event_timestamp,
        event_payload:interactions as interactions_array
    from base 
    where 
    event_timestamp >= '2026-08-25T00:00:00'
    and country_code = 'US'
)
, final as (
    select 
        event_id
        , user_id
        , event_timestamp
        , f.value:item_id::varchar as item_id
        , f.index as position_index
        , NVL(f.value:applied_discount::boolean, false) as discount_applied
        , f.value:price::decimal(10, 2) as price
    from
        extract_data as b
        , lateral flatten( input => b.interactions_array ) as f
    where 
        f.value:action_type::varchar = 'PURCHASE_INTENT'
)
select * from final