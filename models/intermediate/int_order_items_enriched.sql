with order_items as (

    select * from {{ ref('stg_thelook__order_items') }}

),

inventory as (

    select * from {{ ref('stg_thelook__inventory_items') }}

),

enriched as (

    select
        -- claves
        order_items.order_item_id,
        order_items.order_id,
        order_items.user_id,
        order_items.product_id,
        order_items.inventory_item_id,
        inventory.distribution_center_id,

        -- atributos
        order_items.status,

        -- métricas: precio de venta y costo real de la unidad vendida
        order_items.sale_price,
        inventory.cost,
        order_items.sale_price - inventory.cost as gross_margin_amount,

        -- timestamps
        order_items.created_at,
        order_items.shipped_at,
        order_items.delivered_at,
        order_items.returned_at

    from order_items
    left join inventory
        on order_items.inventory_item_id = inventory.inventory_item_id

)

select * from enriched
