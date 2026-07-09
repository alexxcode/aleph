# Proyecto dbt + BigQuery: plataforma de analítica para un distribuidor

**Nombre de trabajo:** *Aleph* 

En el cuento de Borges, el Aleph es "uno de los puntos del espacio que contienen todos los puntos", un lugar donde, sin superposición, se concentran de manera simultánea todas las realidades del universo.

En la ingeniería de datos, ese es exactamente el santo grial: el Single Source of Truth (SSOT).

---

## 1. Decisiones de arquitectura (ya cerradas)

- **Warehouse:** BigQuery.
- **Fuente:** `bigquery-public-data.thelook_ecommerce`. Nativa, sin ingesta. Tablas: `products`, `inventory_items`, `distribution_centers`, `orders`, `order_items`, `users`, `events`.
- **Motor dbt:** dbt Core v1.x estable (Python) para el build. Fusion / Core v2 se menciona, no se usa todavía.
- **Patrón:** medallón estilo Kimball. `sources` → `staging` → `intermediate` → `marts` (dims + facts + marts analíticos) → capa ML → capa semántica.

### Por qué esta fuente y no una genérica
El valor no es el dataset, es que su esquema es el de un distribuidor. 


## 2. Proyecto GCP

Name: Aleph
Project id:	aleph12


## 3. Arquitectura completa de modelos

### sources
`sources.yml` apuntando a las 7 tablas de thelook. Con `freshness` configurado sobre `orders.created_at` (thelook genera datos nuevos, el freshness es real).

Opción recomendada: leer directo del dataset público (read-only, gratis). Opción avanzada: un `CREATE TABLE AS SELECT` una vez a tu propio dataset `raw_thelook` para controlar la fuente y poder simular cambios para los snapshots.

### staging (materializados como `view`)
Uno por tabla fuente, limpieza 1:1 (renombrar, castear tipos, sin lógica de negocio):
`stg_thelook__orders`, `stg_thelook__order_items`, `stg_thelook__products`, `stg_thelook__users`, `stg_thelook__inventory_items`, `stg_thelook__distribution_centers`, `stg_thelook__events`.

### intermediate (`ephemeral` o `view`)
- `int_order_items_enriched`: order_items + products + inventory (trae costo y precio al grano de línea de orden).
- `int_inventory_status`: estado actual de cada item (en stock vs vendido, días en inventario).
- `int_customer_orders`: agregado de órdenes por cliente (primera compra, recurrencia).

### marts: dimensiones (`table`)
`dim_products`, `dim_customers`, `dim_distribution_centers`, `dim_dates` (generada con `dbt_date` o un macro).

### marts: hechos (`incremental`, particionados y clusterizados)
- `fct_order_items`: grano línea de orden. Partición por fecha de orden, cluster por `product_id` / `distribution_center_id`. Métricas: sale_price, cost, margen.
- `fct_orders`: grano orden. Estado, tiempos, valor total.
- `fct_inventory_snapshot`: grano diario de inventario (foto del stock por producto/centro por día). Aquí es donde el snapshot cobra sentido.

### marts: analíticos
- `mart_product_performance`: ingreso, margen, unidades por producto/categoría/centro/mes.
- `mart_inventory_health`: stock on hand, días de cobertura, sell-through, dead stock, clasificación ABC.
- `mart_customer_rfm`: segmentación RFM, nuevos vs recurrentes, retención por cohorte.
- `mart_fulfillment_sla`: tiempos order-to-ship-to-deliver, desempeño por centro (usa `shipped_at` / `delivered_at`).

### snapshots (SCD2)
- `snap_products`: historial de `retail_price` y `cost`. Esto habilita el margen correcto: el margen de una venta se calcula con el costo **al momento de la venta**, no el costo actual. Ese detalle es analytics engineering real que la mayoría de juniors omite. Menciónalo.

### capa ML (tu diferencial, continuidad con Dupin)
- `mart_demand_features`: grano producto × semana. Lags, medias móviles, tendencia, estacionalidad, features de tráfico/promoción derivadas de `events`.
- Paso Python (LightGBM, tu terreno): lee `mart_demand_features`, pronostica demanda de las próximas N semanas, escribe a una tabla BQ `ml_forecast_demand`.
- `ml_forecast_demand` entra como nuevo `source` en dbt → `mart_inventory_recommendations`: cruza pronóstico + inventario actual → punto de reorden, stock de seguridad, flag de riesgo de quiebre.

Esto cierra el loop: analytics engineering alimenta ML, ML retroalimenta los marts. La mayoría de proyectos de portafolio dbt se quedan en el dashboard. El tuyo cierra el ciclo, y eso es exactamente lo que un ML engineer aporta y un analytics engineer puro no.

### capa semántica (avanzada, opcional)
`semantic_models` + métricas (revenue, gross_margin, aov, units_sold, active_customers) con la nueva spec de Semantic Layer YAML. Ojo: cambió en 2026, trátala como fase opcional y ligera.

---

## 4. Testing, calidad y madurez de producción

- Genéricos en todos los modelos clave (unique, not_null, relationships entre facts y dims, accepted_values en status).
- `dbt_utils`: `unique_combination_of_columns`, `accepted_range`.
- `dbt_expectations`: chequeos distribucionales y de tipo.
- Singulares: margen nunca negativo más allá de un umbral, cero `order_items` huérfanos, cero ventas sin costo asociado.
- `source freshness` sobre orders.
- Model contracts en los marts críticos (tipos y constraints forzados).
- Docs con descripciones en yml, `dbt docs generate`, exposures apuntando al dashboard y al modelo ML, screenshot del grafo de linaje para el README.

## 5. Orquestación y CI/CD

- Repo en GitHub. README que cuente la historia (raw → business-ready → recomendación de inventario) con el grafo de linaje.
- GitHub Actions: `dbt build` (deps, seed, run, test) en cada PR contra un dataset CI aislado, con keyfile de service account en secrets.
- Slim CI: `state:modified` + `--defer` contra el manifest de prod una vez lo tengas (esto es señal de madurez, procesas solo lo que cambió).
- Corrida diaria programada (cron de Actions, o dbt Cloud developer gratis).

## 6. Capa BI

- **Recomendada:** Evidence.dev (BI como código, markdown + SQL, git-friendly, despliega como sitio estático). Encaja con tu estética y es un artefacto de LinkedIn potente.
- **Fallback de baja fricción:** Looker Studio (nativo BQ, cero setup).

---

## 7. Ruta completa 

Las fases van en orden de dependencia, no en días.

- **Fase 0 — Fundaciones.** Proyecto GCP, service account, `dbt-bigquery`, `dbt init`, conexión, repo git, dataset CI.
- **Fase 1 — Staging + sources.** `sources.yml` sobre thelook, freshness, los 7 staging, tests básicos.
- **Fase 2 — Núcleo dimensional.** Dims + facts, star schema, facts incrementales, partición/cluster, tests de relationships.
- **Fase 3 — Snapshots / SCD2.** Historial de precio/costo. Margen correcto al momento de venta.
- **Fase 4 — Calidad + docs.** dbt_expectations, singulares, docs, exposures, linaje.
- **Fase 5 — Marts analíticos.** ABC, margen, RFM/cohortes, SLA de fulfillment, inventory health.
- **Fase 6 — Features + forecast ML.** `mart_demand_features`, LightGBM, forecast de vuelta a BQ, `mart_inventory_recommendations`.
- **Fase 7 — Capa semántica.** Métricas / MetricFlow (opcional).
- **Fase 8 — Orquestación + CI/CD.** Actions, slim CI, corrida programada.
- **Fase 9 — BI + writeup.** Evidence.dev o Looker Studio, README, post de LinkedIn.

---
