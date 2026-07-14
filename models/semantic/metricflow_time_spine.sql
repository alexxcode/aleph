-- Time spine diario requerido por MetricFlow para métricas sobre el tiempo.
-- Reutiliza dim_dates como columna calendario.
select date_day
from {{ ref('dim_dates') }}
