{{ config(severity='warn') }}

-- Fase 3 — demuestra el valor del snapshot SCD2: el costo vigente al momento de
-- la venta (product_cost_at_sale) puede diferir del costo ACTUAL del producto
-- (dim_products.cost) tras un cambio de precio/costo.
--
-- Convención de test singular: pasa si devuelve 0 filas. Aquí devuelve una fila
-- únicamente si NO existe ningún caso de diferencia.
--
-- Severidad `warn` (no `error`) a propósito: la diferencia solo existe cuando el
-- snapshot ha capturado >=2 versiones del costo de un producto (lo cual ocurre
-- con el tiempo, o en dev donde se simuló el cambio). En un entorno fresco
-- (primer build de prod, dataset efímero de CI) el snapshot tiene una sola
-- versión y aún no hay diferencia: eso es esperado, no un fallo del pipeline.

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
