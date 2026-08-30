```sql
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
```

# PR :
## Purpose
Create mart table for analytics team


## How

In the first cte 'extract_data', I filtered the data by event_timestamp and country code before opening the variant(json) value column 'event_payload', therefore, snowflake doesn't need to scan whole expanded rows and occurs spillage.


And the data is flattened for 2 times to get the interaction array in the event_payload column and position_index is the index of the array. This mart table will help your analyzing customer actions flow.


Additionally, I can add the Customer's action like 'click / purchase...etc', this information also will help understanding customers actions deeply. please feel free to ask me to add them if you need it.


## Note

Please confirm if this model are perfect or not and merge it into our develpment branch.
Sincerely, Masa.