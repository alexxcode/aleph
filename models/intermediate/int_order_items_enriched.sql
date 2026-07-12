with order_items as (

    select * from {{ ref('stg_thelook__order_items') }}

),

inventory as (

    select * from {{ ref('stg_thelook__inventory_items') }}

),

-- historial SCD2 de costo/precio de producto (snap_products), rankeado por
-- versión para resolver el costo vigente al momento de cada venta
product_versions as (

    select
        product_id,
        cost as product_cost,
        dbt_valid_from,
        dbt_valid_to,
        row_number() over (partition by product_id order by dbt_valid_from) as version_num,
        min(dbt_valid_from) over (partition by product_id)                   as first_valid_from
    from {{ ref('snap_products') }}

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

        -- métricas: costo del producto vigente al momento de la venta (SCD2)
        product_versions.product_cost                         as product_cost_at_sale,
        order_items.sale_price - product_versions.product_cost as gross_margin_at_sale,

        -- timestamps
        order_items.created_at,
        order_items.shipped_at,
        order_items.delivered_at,
        order_items.returned_at

    from order_items
    left join inventory
        on order_items.inventory_item_id = inventory.inventory_item_id
    left join product_versions
        on order_items.product_id = product_versions.product_id
        and (
            -- versión cuyo rango de validez contiene la fecha de venta
            (order_items.created_at >= product_versions.dbt_valid_from
                and (order_items.created_at < product_versions.dbt_valid_to
                     or product_versions.dbt_valid_to is null))
            -- ventas anteriores al primer snapshot: se atribuyen a la versión más antigua
            or (order_items.created_at < product_versions.first_valid_from
                and product_versions.version_num = 1)
        )

)

select * from enriched
