{{
    config(
        materialized='incremental',
        incremental_strategy='insert_overwrite',
        partition_by={'field': 'order_date', 'data_type': 'date'},
        cluster_by=['product_id', 'distribution_center_id'],
        on_schema_change='sync_all_columns'
    )
}}

with enriched as (

    select * from {{ ref('int_order_items_enriched') }}

),

final as (

    select
        -- claves
        order_item_id,
        order_id,
        user_id,
        product_id,
        distribution_center_id,
        inventory_item_id,

        -- partición
        date(created_at) as order_date,

        -- atributos
        status,

        -- timestamps
        created_at as ordered_at,
        shipped_at,
        delivered_at,
        returned_at,

        -- métricas
        sale_price,
        cost,
        gross_margin_amount

    from enriched

    {% if is_incremental() %}
    -- reprocesa solo las particiones recientes (con holgura para llegadas tardías)
    where date(created_at) >= date_sub(
        (select max(order_date) from {{ this }}), interval 3 day
    )
    {% endif %}

)

select * from final
