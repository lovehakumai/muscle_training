{{
    config(
        database = 'MUSCLE_DB_TASK03'
    )
}}
with merchans as (
    select * from {{ ref('stg_apexpay__raw_merchants') }}
)
, terminals as (
    select * from {{ ref('stg_apexpay__raw_terminals') }}
)
, transactions as (
    select * from {{ ref('stg_apexpay__raw_transactions') }}
)

select * from transactions