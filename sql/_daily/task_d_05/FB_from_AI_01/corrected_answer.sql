/*
【修正版スクリプト】
※ コードは実行せず、机上トレースで作成しています。

元のスクリプトからの変更点：
1. WHERE 句を CTE の中に移動: 
   全件ソートによるパフォーマンスの悪化（Spillage）を防ぐため、対象日のデータだけを先に絞ってから QUALIFY を実行するようにしました。
2. QUALIFY の不要な PARTITION BY store_id, sales_date の修正:
   WHERE 句で `sales_date = $target_dt` に絞ったため、`PARTITION BY store_id` だけで「その日の各店舗の最新」を取れるようになりました。
3. NVL の削除:
   GROUP BY があるため 0件のときは 0行が返ります。NULL が発生することはないため、不要な関数を外して可読性を高めました。
*/

SET raw_target_dt = '2026-09-01 00:00:00'::TIMESTAMP_NTZ;
SET target_dt = date_trunc('day', $raw_target_dt);

with latest_sales_date as (
    select
        store_id
        , sales_date
        , amount
        , received_at
    from 
        raw_daily_sales
    where 
        sales_date = $target_dt
    qualify
        row_number() over(partition by store_id order by received_at desc) = 1
)
select 
    sales_date
    , sum(amount) as amount
from 
    latest_sales_date
group by 
    sales_date
;
