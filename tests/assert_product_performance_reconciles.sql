-- Validación de negocio: el ingreso agregado en mart_product_performance debe
-- cuadrar con el ingreso de fct_order_items (misma base, sin filtros). Pasa si
-- la diferencia absoluta es despreciable (< 1).

with mart_total as (
    select sum(gross_revenue) as revenue from {{ ref('mart_product_performance') }}
),

fact_total as (
    select sum(sale_price) as revenue from {{ ref('fct_order_items') }}
)

select
    mart_total.revenue   as mart_revenue,
    fact_total.revenue   as fact_revenue
from mart_total
cross join fact_total
where abs(mart_total.revenue - fact_total.revenue) > 1
