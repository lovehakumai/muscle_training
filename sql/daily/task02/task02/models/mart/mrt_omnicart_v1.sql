with base as (
    select * from {{ref('stg_omnicart__raw_user_clickstream')}}
)
, extract_data as (
    select 
        * 
    from base 
    where 
    event_timestamp >= '2026-08-25T00:00:00'
    and country_code = 'US'
)
, layer_1 as (
    select 
        event_id
        , user_id
        , event_timestamp
        , f.value as payload_l01
    from
        extract_data as b
        , lateral flatten( input => parse_json(b.event_payload) ) as f
)
, layer_interaction as (
    select 
        event_id
        , user_id
        , event_timestamp
        , f.value:item_id::varchar as item_id
        , f.index as position_index
        , NVL(f.value:applied_discount::boolean, false) as discount_applied
        , f.value:price::number as price
    from layer_1 as l1
    , lateral flatten(input => l1.payload_l01) as f 
)
select * from layer_interaction