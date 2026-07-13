-- Cero ventas sin costo asociado: toda línea con precio de venta debe tener un
-- costo real de la unidad vendida. Pasa si devuelve 0 filas.

select
    order_item_id,
    order_id,
    sale_price,
    cost
from {{ ref('fct_order_items') }}
where sale_price is not null
  and cost is null
