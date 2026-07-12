with source as (

    select * from {{ source('raw_thelook', 'products') }}

),

renamed as (

    select
        -- claves
        id as product_id,
        distribution_center_id,

        -- atributos
        name as product_name,
        category,
        brand,
        department,
        sku,

        -- métricas
        cost,
        retail_price

    from source

)

select * from renamed
