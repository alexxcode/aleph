-- SLA de fulfillment por centro de distribución y mes: tiempos order-to-ship y
-- ship-to-deliver, y tasas de envío/entrega. Grano: centro x mes.

with order_items as (

    select * from {{ ref('fct_order_items') }}

),

dates as (

    select date_day, month_start_date from {{ ref('dim_dates') }}

),

centers as (

    select distribution_center_id, distribution_center_name
    from {{ ref('dim_distribution_centers') }}

),

enriched as (

    select
        order_items.distribution_center_id,
        dates.month_start_date,
        order_items.shipped_at,
        order_items.delivered_at,
        timestamp_diff(order_items.shipped_at, order_items.ordered_at, hour)   as hours_to_ship,
        timestamp_diff(order_items.delivered_at, order_items.shipped_at, hour) as hours_to_deliver,
        timestamp_diff(order_items.delivered_at, order_items.ordered_at, hour) as hours_order_to_deliver
    from order_items
    inner join dates
        on order_items.order_date = dates.date_day

),

agg as (

    select
        distribution_center_id,
        month_start_date,
        count(*)                                                    as n_lines,
        countif(shipped_at is not null)                             as n_shipped,
        countif(delivered_at is not null)                           as n_delivered,
        avg(hours_to_ship)                                          as avg_hours_to_ship,
        avg(hours_to_deliver)                                       as avg_hours_to_deliver,
        avg(hours_order_to_deliver)                                 as avg_hours_order_to_deliver,
        safe_divide(countif(delivered_at is not null), count(*))    as pct_delivered
    from enriched
    group by distribution_center_id, month_start_date

),

final as (

    select
        agg.distribution_center_id,
        centers.distribution_center_name,
        agg.month_start_date,
        agg.n_lines,
        agg.n_shipped,
        agg.n_delivered,
        agg.avg_hours_to_ship,
        agg.avg_hours_to_deliver,
        agg.avg_hours_order_to_deliver,
        agg.pct_delivered
    from agg
    left join centers
        on agg.distribution_center_id = centers.distribution_center_id

)

select * from final
