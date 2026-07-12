-- Fase 3 — demuestra el valor del snapshot SCD2: el costo vigente al momento de
-- la venta (product_cost_at_sale) puede diferir del costo ACTUAL del producto
-- (dim_products.cost) tras un cambio de precio/costo.
--
-- Convención de test singular: pasa si devuelve 0 filas. Aquí devuelve una fila
-- (y FALLA) únicamente si NO existe ningún caso de diferencia, es decir, si el
-- historial de costo no se está aplicando correctamente al recálculo de margen.

with comparados as (

    select
        f.order_item_id,
        f.product_cost_at_sale,
        p.cost as product_cost_current
    from {{ ref('fct_order_items') }} as f
    inner join {{ ref('dim_products') }} as p
        on f.product_id = p.product_id
    where f.product_cost_at_sale is not null
      and f.product_cost_at_sale <> p.cost

),

validacion as (

    select count(*) as casos_diferentes
    from comparados

)

select *
from validacion
where casos_diferentes = 0
