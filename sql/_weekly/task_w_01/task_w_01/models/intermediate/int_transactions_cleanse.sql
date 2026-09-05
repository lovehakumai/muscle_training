{# 
Q : Is there any description template in dbt?
[PURPOSE]Cleanse the `raw_transactions` table before aggregating
[PROBLEMS]
    - `transaction_id` is duplicated value due to retrying process
    - `purchase_amount` includes minus value, this is valid value
    - `points_earned` includes NULL value, this is valid value
    - `points_earned` includes iregularly big value by the bug
    - `transaction_timestamp` isn't consective due to error on system
[HOW]
    - Change `transaction_id` into unique and not_null value by grouping and using the window function
        - [ESCALATION] 
            Neeed to Check how to define the uniqueness of `transaction_id`, 
            here in this pipeline, transaction_id with :
                - highest `user_id`
                - latest `transaction_timestamp`
                - highest `purchase_amount`
                - `points_earned` is not null with positive  `purchase_amount` value.
            [CONCLUSION] From Client : 
                - Making `transaction_id` unique only includes latest `transaction_timestamp`. 
                - This is because, if there's dupulicated `transaction_id` with different `user_id` and `purchase_amount` means the problems in upstream, we shouldn't fix it here. 
[ADDITIONAL INFO] From Client : 
    - points_earned might include minus when the transaction was repayment one. 
    - but if there's minus point with positive `purchase_amount` value, this is invalid. 
    - If there's non-consective `transaction_timestamp` rows, it must be detected in the test because this problem caused by upstream system.
 #}
with base as (
    select * from {{ ref('stg_ecommerce__transaction') }}
)
, final as (
    select 
        transaction_id
        , user_id 
        , transaction_timestamp
        , purchase_amount
        , points_earned
    from base 
    qualify 
        row_number()over(partition by transaction_id order by transaction_timestamp desc) = 1
)
select * from final 