with order_items as (

    select * from {{ ref('fct_order_items') }}

),

dates as (

    select date_day, month_start_date from {{ ref('dim_dates') }}

),

products as (

    select
        product_id,
        product_name,
        category,
        brand,
        department,
        distribution_center_id
    from {{ ref('dim_products') }}

),

joined as (

    select
        order_items.product_id,
        dates.month_start_date,
        order_items.order_id,
        order_items.sale_price,
        order_items.cost,
        order_items.gross_margin_amount
    from order_items
    inner join dates
        on order_items.order_date = dates.date_day

),

agg as (

    select
        product_id,
        month_start_date,
        count(*)                        as units_sold,
        count(distinct order_id)        as n_orders,
        sum(sale_price)                 as gross_revenue,
        sum(cost)                       as total_cost,
        sum(gross_margin_amount)        as gross_margin_amount
    from joined
    group by product_id, month_start_date

),

final as (

    select
        agg.product_id,
        products.product_name,
        products.category,
        products.brand,
        products.department,
        products.distribution_center_id,
        agg.month_start_date,
        agg.units_sold,
        agg.n_orders,
        agg.gross_revenue,
        agg.total_cost,
        agg.gross_margin_amount,
        safe_divide(agg.gross_margin_amount, agg.gross_revenue) as gross_margin_pct
    from agg
    left join products
        on agg.product_id = products.product_id

)

select * from final
