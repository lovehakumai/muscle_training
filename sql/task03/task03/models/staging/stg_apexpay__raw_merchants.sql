with source as (

    select * from {{ source('apexpay', 'raw_merchants') }}

),

renamed as (

    select
        merchant_id,
        merchant_name,
        category,
        country_code 

    from source

)

select * from renamed