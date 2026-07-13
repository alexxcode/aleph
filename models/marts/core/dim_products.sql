{{ config(contract={'enforced': true}) }}

with products as (

    select * from {{ ref('stg_thelook__products') }}

),

final as (

    select
        product_id,
        distribution_center_id,
        product_name,
        category,
        brand,
        department,
        sku,
        cost,
        retail_price,
        retail_price - cost                              as base_margin_amount,
        safe_divide(retail_price - cost, retail_price)   as base_margin_pct
    from products

)

select * from final
