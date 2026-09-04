```sql
WITH base AS (
SELECT * FROM {{ ref('stg_slickride__raw_ride_updates') }}
)


SELECT
system_record_id
, ride_id
, updated_at
, passenger_name
, fare_amount

, RIGHT(ride_status_label, LEN(ride_status_label)-2) AS ride_status
, CASE WHEN COUNT(*)OVER(
PARTITION BY max_updated_at_flg, ride_id
) > 1 THEN TRUE ELSE FALSE END AS is_duplicate_at_timestamp
FROM
(
SELECT
system_record_id
, ride_id
, updated_at
, passenger_name
, fare_amount
, MAX(CASE
WHEN ride_status = 'REQUESTED' THEN '1.REQUESTED'
WHEN ride_status = 'ACCEPTED' THEN '2.ACCEPTED'
WHEN ride_status = 'ARRIVED' THEN '3.ARRIVED'
WHEN ride_status = 'PICKED_UP' THEN '4.PICKED_UP'
WHEN ride_status = 'COMPLETED' THEN '5.COMPLETED'
WHEN ride_status = 'CANCELLED' THEN '6.CANCELLED'
END)OVER(PARTITION BY system_record_id, ride_id, updated_at) AS ride_status_label
, CASE WHEN MAX(updated_at)OVER(
PARTITION BY NULL
) = updated_at THEN TRUE ELSE NULL END AS max_updated_at_flg
FROM base
)
QUALIFY
ROW_NUMBER()OVER(
PARTITION BY ride_id, updated_at
ORDER BY system_record_id DESC
) = 1
```


2時間弱考えたけどだめだぁヘルプくださあい