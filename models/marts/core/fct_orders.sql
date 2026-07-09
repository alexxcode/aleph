{{
    config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by={'field': 'order_date', 'data_type': 'date'},
        cluster_by=['status'],
        on_schema_change='sync_all_columns'
    )
}}

with orders as (

    select * from {{ ref('stg_thelook__orders') }}

),

items as (

    select * from {{ ref('int_order_items_enriched') }}

),

item_totals as (

    select
        order_id,
        count(*)                        as n_line_items,
        sum(sale_price)                 as gross_revenue,
        sum(cost)                       as total_cost,
        sum(sale_price - cost)          as gross_margin_amount
    from items
    group by order_id

),

final as (

    select
        -- claves
        orders.order_id,
        orders.user_id,

        -- partición
        date(orders.created_at) as order_date,

        -- atributos
        orders.status,
        orders.gender,

        -- timestamps
        orders.created_at as ordered_at,
        orders.shipped_at,
        orders.delivered_at,
        orders.returned_at,

        -- métricas
        orders.num_of_items,
        item_totals.n_line_items,
        item_totals.gross_revenue,
        item_totals.total_cost,
        item_totals.gross_margin_amount

    from orders
    left join item_totals
        on orders.order_id = item_totals.order_id

    {% if is_incremental() %}
    where date(orders.created_at) >= date_sub(
        (select max(order_date) from {{ this }}), interval 3 day
    )
    {% endif %}

)

select * from final
