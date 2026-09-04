with source as (

    select * from {{ source('apexpay', 'raw_terminals') }}

),

renamed as (

    select
        terminal_id,
        merchant_id,
        terminal_model,
        is_active::boolean as is_active,
        valid_from::timestamp as valid_from,
        valid_to::timestamp as valid_to

    from source

)

select * from renamed