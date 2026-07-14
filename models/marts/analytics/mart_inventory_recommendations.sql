-- Recomendaciones de inventario por producto x centro (Fase 6). Cierra el loop:
-- toma el forecast de demanda por categoría (ml_forecast_demand), lo asigna a
-- cada SKU por su participación reciente en la categoría, y lo cruza con el
-- inventario actual para derivar punto de reorden, stock de seguridad y riesgo.

{% set lead   = var('inventory_lead_time_weeks') %}
{% set safety = var('inventory_safety_weeks') %}
{% set target = var('inventory_target_weeks') %}

with latest_inventory as (

    select
        product_id,
        distribution_center_id,
        units_on_hand,
        inventory_cost_on_hand
    from {{ ref('fct_inventory_snapshot') }}
    where snapshot_date = (select max(snapshot_date) from {{ ref('fct_inventory_snapshot') }})

),

category_forecast as (

    -- demanda semanal media pronosticada por categoría (horizonte completo)
    select
        category,
        avg(predicted_units) as cat_weekly_forecast
    from {{ source('ml', 'ml_forecast_demand') }}
    group by category

),

recent_sales as (

    select
        products.category,
        order_items.product_id,
        count(*) as units_12w
    from {{ ref('fct_order_items') }} as order_items
    inner join {{ ref('dim_products') }} as products
        on order_items.product_id = products.product_id
    where order_items.order_date > date_sub(
        (select max(order_date) from {{ ref('fct_order_items') }}), interval 12 week)
    group by products.category, order_items.product_id

),

category_totals as (

    select category, sum(units_12w) as cat_units_12w
    from recent_sales
    group by category

),

product_share as (

    select
        recent_sales.product_id,
        safe_divide(recent_sales.units_12w, category_totals.cat_units_12w) as category_share
    from recent_sales
    inner join category_totals
        on recent_sales.category = category_totals.category

),

enriched as (

    select
        inv.product_id,
        inv.distribution_center_id,
        products.category,
        products.product_name,
        inv.units_on_hand,
        inv.inventory_cost_on_hand,
        coalesce(category_forecast.cat_weekly_forecast, 0)               as cat_weekly_forecast,
        coalesce(product_share.category_share, 0)                        as category_share,
        coalesce(category_forecast.cat_weekly_forecast * product_share.category_share, 0)
                                                                         as forecast_weekly_units
    from latest_inventory as inv
    inner join {{ ref('dim_products') }} as products
        on inv.product_id = products.product_id
    left join category_forecast
        on products.category = category_forecast.category
    left join product_share
        on inv.product_id = product_share.product_id

),

final as (

    select
        product_id,
        distribution_center_id,
        category,
        product_name,
        units_on_hand,
        inventory_cost_on_hand,
        cat_weekly_forecast,
        category_share,
        round(forecast_weekly_units, 3)                                  as forecast_weekly_units,

        -- política de inventario
        round(forecast_weekly_units * {{ safety }}, 1)                   as safety_stock,
        round(forecast_weekly_units * {{ lead }} + forecast_weekly_units * {{ safety }}, 1)
                                                                         as reorder_point,
        safe_divide(units_on_hand, forecast_weekly_units)                as weeks_of_cover,

        -- señales accionables
        units_on_hand < (forecast_weekly_units * {{ lead }} + forecast_weekly_units * {{ safety }})
                                                                         as needs_reorder,
        greatest(
            cast(ceil(
                forecast_weekly_units * {{ target }} + forecast_weekly_units * {{ safety }} - units_on_hand
            ) as int64), 0)                                              as suggested_reorder_qty,
        (forecast_weekly_units > 0 and units_on_hand < forecast_weekly_units * {{ lead }})
                                                                         as is_stockout_risk,

        -- clasificación accionable del estado de inventario
        case
            when forecast_weekly_units > 0 and units_on_hand < forecast_weekly_units * {{ lead }}
                then 'Stockout risk'
            when units_on_hand < forecast_weekly_units * {{ lead }} + forecast_weekly_units * {{ safety }}
                then 'Reorder'
            when forecast_weekly_units = 0 or safe_divide(units_on_hand, forecast_weekly_units) > 26
                then 'Overstock'
            else 'Healthy'
        end                                                              as inventory_status

    from enriched

)

select * from final
