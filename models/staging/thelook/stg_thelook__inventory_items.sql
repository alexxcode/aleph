with source as (

    select * from {{ source('thelook', 'inventory_items') }}

),

renamed as (

    select
        -- claves
        id as inventory_item_id,
        product_id,
        product_distribution_center_id as distribution_center_id,

        -- atributos de producto (denormalizados en la fuente)
        product_category,
        product_name,
        product_brand,
        product_department,
        product_sku,

        -- métricas
        cost,
        product_retail_price as retail_price,

        -- timestamps
        created_at,
        sold_at

    from source

)

select * from renamed
