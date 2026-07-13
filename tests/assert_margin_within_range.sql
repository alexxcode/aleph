-- Margen dentro de un rango plausible: el costo no debería superar 3x el precio
-- de venta (margen absurdamente negativo). Pasa si devuelve 0 filas.

select
    order_item_id,
    sale_price,
    cost,
    gross_margin_amount
from {{ ref('fct_order_items') }}
where sale_price > 0
  and cost is not null
  and cost > sale_price * 3
