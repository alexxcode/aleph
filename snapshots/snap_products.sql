{% snapshot snap_products %}

{{
    config(
        unique_key='product_id',
        strategy='check',
        check_cols=['cost', 'retail_price']
    )
}}

-- Lee la copia controlada (raw_thelook.products), no la fuente pública, para
-- poder simular cambios de precio/costo y registrar su historial SCD2.
select
    id as product_id,
    name as product_name,
    category,
    brand,
    department,
    sku,
    distribution_center_id,
    cost,
    retail_price
from {{ source('raw_thelook', 'products') }}

{% endsnapshot %}
