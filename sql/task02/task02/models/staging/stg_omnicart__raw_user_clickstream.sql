with base as (
    select * from {{source('omnicart', 'raw_user_clickstream')}}
) 
, rename as (
    select 
        cast(event_id as string) as event_id 
        , cast(country_code as string) as country_code
        , cast(user_id as string) as user_id
        , cast(event_timestamp as timestamp) as event_timestamp
        , cast(event_payload as variant) as event_payload
    from base 
)

select * from rename 