with base as (
    select * from {{ref('stg_omnicart__raw_user_clickstream')}}
)
select * from base 