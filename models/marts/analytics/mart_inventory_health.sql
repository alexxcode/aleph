-- Estado de inventario al último snapshot: cobertura, sell-through, dead stock y
-- clasificación ABC por contribución a la venta de los últimos 12 meses.

with as_of as (

    select max(snapshot_date) as as_of_date from {{ ref('fct_inventory_snapshot') }}

),

inventory as (

    select
        product_id,
        distribution_center_id,
        units_on_hand,
        inventory_cost_on_hand
    from {{ ref('fct_inventory_snapshot') }}
    where snapshot_date = (select as_of_date from as_of)

),

products as (

    select product_id, product_name, category, brand from {{ ref('dim_products') }}

),

sales_90d as (

    select
        product_id,
        distribution_center_id,
        count(*) as units_sold_90d
    from {{ ref('fct_order_items') }}
    where order_date > date_sub((select as_of_date from as_of), interval 90 day)
    group by product_id, distribution_center_id

),

product_revenue as (

    select
        product_id,
        sum(sale_price) as revenue_12m
    from {{ ref('fct_order_items') }}
    where order_date > date_sub((select as_of_date from as_of), interval 365 day)
    group by product_id

),

abc as (

    select
        product_id,
        revenue_12m,
        sum(revenue_12m) over (order by revenue_12m desc)
            / nullif(sum(revenue_12m) over (), 0) as cumulative_revenue_pct
    from product_revenue

),

abc_class as (

    select
        product_id,
        case
            when cumulative_revenue_pct <= 0.80 then 'A'
            when cumulative_revenue_pct <= 0.95 then 'B'
            else 'C'
        end as abc_class
    from abc

),

final as (

    select
        inventory.product_id,
        inventory.distribution_center_id,
        products.product_name,
        products.category,

        inventory.units_on_hand,
        inventory.inventory_cost_on_hand,
        coalesce(sales_90d.units_sold_90d, 0)                                as units_sold_90d,
        safe_divide(coalesce(sales_90d.units_sold_90d, 0), 90.0)            as avg_daily_units,
        safe_divide(
            inventory.units_on_hand,
            safe_divide(coalesce(sales_90d.units_sold_90d, 0), 90.0)
        )                                                                    as days_of_coverage,
        safe_divide(
            coalesce(sales_90d.units_sold_90d, 0),
            coalesce(sales_90d.units_sold_90d, 0) + inventory.units_on_hand
        )                                                                    as sell_through_90d,
        (inventory.units_on_hand > 0 and coalesce(sales_90d.units_sold_90d, 0) = 0) as is_dead_stock,
        coalesce(abc_class.abc_class, 'C')                                   as abc_class

    from inventory
    left join products   on inventory.product_id = products.product_id
    left join sales_90d
        on inventory.product_id = sales_90d.product_id
       and inventory.distribution_center_id = sales_90d.distribution_center_id
    left join abc_class  on inventory.product_id = abc_class.product_id

)

select * from final
