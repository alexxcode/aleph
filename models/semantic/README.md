# Capa semántica (Fase 7)

Métricas gobernadas sobre `fct_order_items`, definidas con la spec de
`semantic_models` + `metrics` de dbt/MetricFlow.

## Métricas

| Métrica | Tipo | Definición |
|---|---|---|
| `revenue` | simple | suma de `sale_price` |
| `gross_margin` | simple | suma de `gross_margin_amount` |
| `units_sold` | simple | conteo de líneas de orden |
| `orders` | simple | órdenes distintas |
| `aov` | ratio | `revenue / orders` (ticket promedio) |

Modelo semántico `order_items` con entidades (order_item, order, product,
customer, distribution_center), dimensiones (`order_date`, `status`) y el time
spine `metricflow_time_spine` (sobre `dim_dates`).

## Estado

Las definiciones **parsean y validan sin error** con dbt 1.11 (`dbt parse`; ver
`target/semantic_manifest.json`, que incluye las 5 métricas). Es el criterio de
salida de esta fase.

> Nota de runtime: consultar las métricas con el CLI de MetricFlow (`mf query`)
> requiere una versión de `metricflow`/`dbt-metricflow` alineada con el core; con
> dbt 1.11 la combinación disponible tiene un bug interno al construir el manifest
> (`string pattern on a bytes-like object`), ajeno a estas definiciones. En dbt
> Cloud Semantic Layer o con versiones alineadas, las métricas se consultan sin
> cambios en el YAML.
