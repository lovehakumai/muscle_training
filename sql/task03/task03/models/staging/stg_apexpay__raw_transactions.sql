with source as (

    select * from {{ source('apexpay', 'raw_transactions') }}

),

renamed as (

    select
        transaction_id,
        merchant_id,
        terminal_id,
        transaction_timestamp::timestamp as transaction_timestamp,
        transaction_status,
        amount::decimal(10, 2) as amount,
        fee_amount::decimal(10, 2) as fee_amount ,
        raw_payload,
        user_agent_details

    from source

)

select * from renamed