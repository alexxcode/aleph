# Aleph — Instrucciones operativas

Guía de trabajo del proyecto. Toda persona o herramienta que ejecute tareas en este repo sigue este documento. Ante conflicto entre este documento y cualquier otra fuente, gana este documento. Los cambios a estas instrucciones se hacen por PR, no sobre la marcha.

---

## 0. Contexto en una línea

Plataforma de analítica end-to-end para un distribuidor, sobre `bigquery-public-data.thelook_ecommerce`, con dbt Core v1.x + BigQuery, cerrando el ciclo staging → marts dimensionales → marts analíticos → forecast de demanda (LightGBM) → recomendaciones de inventario de vuelta al warehouse. El diseño completo vive en `proyecto_dbt.md`; este archivo define **cómo se ejecuta**.

---

## 1. Parámetros fijos del entorno

Estos valores no se cambian sin actualizar este documento primero.

| Parámetro | Valor |
|---|---|
| Proyecto GCP | `aleph12` (ya creado, billing habilitado) |
| Región de TODOS los datasets | `US` (multi-región; obligatorio: thelook vive en US y BigQuery no cruza regiones) |
| Fuente | `bigquery-public-data.thelook_ecommerce` (solo lectura; nunca se copia salvo lo indicado en §6 Fase 3) |
| Motor | dbt Core v1.x estable + `dbt-bigquery` (NO Fusion / Core v2 por ahora) |
| Datasets destino | `dbt_alexis` (dev), `analytics` (prod), `dbt_ci_pr_<numero>` (efímeros de CI) |
| SO de desarrollo | Windows (PowerShell). Los comandos de este doc son PowerShell salvo indicación |
| Python | 3.11+ en venv local `.venv` |
| Repo | GitHub, **público desde el día uno** (ver §3, reglas de secretos) |

---

## 2. Setup inicial (una sola vez)

```powershell
# 1. Ambiente Python
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install dbt-bigquery

# 2. Autenticación local: OAuth con gcloud (NO keyfile en local)
#    Instalar Google Cloud SDK si no está: https://cloud.google.com/sdk/docs/install
gcloud auth application-default login
gcloud config set project aleph12

# 3. Crear datasets destino (región US)
bq --location=US mk --dataset aleph12:dbt_alexis
bq --location=US mk --dataset aleph12:analytics

# 4. Inicializar proyecto dbt (si el repo está vacío)
dbt init aleph

# 5. Verificación obligatoria antes de cualquier otra cosa
dbt debug
```

`profiles.yml` (vive en `~/.dbt/`, NUNCA en el repo):

```yaml
aleph:
  target: dev
  outputs:
    dev:
      type: bigquery
      method: oauth
      project: aleph12
      dataset: dbt_alexis
      location: US
      threads: 4
      priority: interactive
      job_execution_timeout_seconds: 300
      maximum_bytes_billed: 2000000000   # 2 GB por query: freno de costo, ver §3
    prod:
      type: bigquery
      method: oauth            # en CI/CD se sobreescribe con service account, ver §7
      project: aleph12
      dataset: analytics
      location: US
      threads: 4
      maximum_bytes_billed: 10000000000  # 10 GB
```

Criterio de salida del setup: `dbt debug` en verde contra `dev`.

---

## 3. Reglas duras (violarlas rompe el proyecto o lo expone)

1. **Secretos.** El repo es público. Nunca se commitea: `profiles.yml`, keyfiles JSON de service accounts, `.env`, tokens. El `.gitignore` incluye desde el primer commit: `profiles.yml`, `*.json` de credenciales, `.env`, `target/`, `dbt_packages/`, `logs/`, `.venv/`. Si un secreto toca el historial de git, se rota la credencial de inmediato; borrar el commit no basta.
2. **Costo.** `maximum_bytes_billed` queda configurado en todos los targets y no se elimina para "destrabar" una query. Si una query lo excede, se optimiza la query (partición, cluster, filtros), no el límite. Excepción única: backfill inicial de un incremental, documentado en el PR.
3. **Región.** Todo dataset nuevo se crea en `US`. Sin excepciones.
4. **Fuente pública.** `bigquery-public-data.thelook_ecommerce` es de solo lectura y se referencia siempre vía `source()`, nunca hardcodeada en un modelo.
5. **Nada llega a `main` sin pasar `dbt build` completo** (run + test) en verde. Localmente antes del PR, y en CI dentro del PR.
6. **Un cambio, un PR, un propósito.** No se mezclan fases en un mismo PR. Commits en español, imperativo, prefijados por área: `staging:`, `marts:`, `ml:`, `ci:`, `docs:`.
7. **No se avanza de fase con la anterior en rojo.** El criterio de salida de cada fase (§6) es binario.

---

## 4. Convenciones de código

### SQL
- Keywords en minúscula, snake_case en todo.
- Un CTE por concepto lógico; el `select` final es siempre `select * from <cte_final>` o una proyección explícita corta.
- CTEs de import al inicio: primero se traen las refs (`with orders as (select * from {{ ref('stg_thelook__orders') }})`), después la lógica.
- Nunca `select *` hacia un mart; las columnas de marts se enumeran explícitamente (habilita contracts en Fase 4).
- Ningún modelo referencia otro modelo salvo vía `ref()`, ni una fuente salvo vía `source()`.

### Nomenclatura de modelos
- `stg_thelook__<tabla>` — staging, 1:1 con la fuente, sin joins, sin lógica de negocio. Solo: renombrar, castear, normalizar strings/timestamps.
- `int_<concepto>` — intermedios, joins y enriquecimiento. No se exponen a BI.
- `dim_<entidad>` / `fct_<proceso>` — núcleo dimensional.
- `mart_<dominio>` — tablas de consumo de negocio.
- `snap_<entidad>` — snapshots SCD2.
- `ml_<artefacto>` — tablas escritas por el paso de Python (entran como source, no como ref).

### Materializaciones (default por capa, configurado en `dbt_project.yml`, no modelo a modelo)
| Capa | Materialización |
|---|---|
| staging | `view` |
| intermediate | `ephemeral` |
| dims | `table` |
| facts | `incremental` + partición por fecha + cluster |
| marts analíticos | `table` |

### YAML y tests
- Cada modelo tiene entrada en un `.yml` de su carpeta con `description` y tests. Mínimo no negociable: `unique` + `not_null` en la clave primaria de cada modelo de marts, `relationships` de facts hacia dims, `accepted_values` en columnas de estado.
- Un modelo sin tests no se mergea. Un test que falla no se skipea: o se arregla el modelo, o se documenta el hallazgo del dato y se ajusta el test con severidad `warn` justificada en el PR.

### Estructura del repo
```
aleph/
├── models/
│   ├── staging/thelook/        # stg_*.sql + _thelook__sources.yml + _thelook__models.yml
│   ├── intermediate/           # int_*.sql + _int__models.yml
│   └── marts/
│       ├── core/               # dims, facts + yml
│       └── analytics/          # mart_* + yml
├── snapshots/
├── ml/                         # scripts Python del forecast (Fase 6)
├── macros/
├── tests/                      # tests singulares
├── .github/workflows/
├── dbt_project.yml
├── packages.yml
├── proyecto_dbt.md             # diseño completo
└── instrucciones.md            # este archivo
```

### Packages (`packages.yml`)
`dbt_utils` y `dbt_date` desde Fase 1; `dbt_expectations` desde Fase 4. `dbt deps` después de cualquier cambio en packages.

---

## 5. Ciclo de trabajo por tarea

Toda tarea, del tamaño que sea, sigue este ciclo:

1. Rama desde `main`: `fase<N>/<descripcion-corta>`.
2. Implementar el cambio más pequeño que deja el proyecto en estado consistente.
3. Verificar en local, en este orden:
   ```powershell
   dbt parse                              # errores de compilación/jinja
   dbt build --select <modelos tocados>+  # iteración barata
   dbt build                              # build completo antes de abrir el PR
   ```
4. PR con: qué cambia, por qué, salida resumida de `dbt build`, y si aplica, bytes procesados de las queries nuevas (visibles en la UI de BigQuery o en `target/run_results.json`).
5. Merge solo con CI en verde.

Regla de selección: durante el desarrollo se itera con `--select <modelo>+`; el build completo es obligatorio solo en el paso 3.3 y en CI.

---

## 6. Fases y criterios de salida

Cada fase termina cuando su criterio de salida se cumple de forma verificable. El detalle de diseño está en `proyecto_dbt.md`; aquí el orden, el alcance y el "done".

**Fase 0 — Fundaciones.**
Alcance: §2 completo, repo inicializado, `.gitignore` correcto, `dbt_project.yml` con defaults de materialización por capa.
Done: `dbt debug` verde, primer commit en `main` sin secretos, modelo de ejemplo de `dbt init` eliminado.

**Fase 1 — Sources + staging.**
Alcance: `_thelook__sources.yml` con las 7 tablas y `freshness` sobre `orders` (`loaded_at_field: created_at`); los 7 `stg_thelook__*`; tests `unique`/`not_null` en PKs de staging.
Done: `dbt build --select staging` verde; `dbt source freshness` corre y reporta.

**Fase 2 — Núcleo dimensional.**
Alcance: `dim_products`, `dim_customers`, `dim_distribution_centers`, `dim_dates`; `fct_order_items` y `fct_orders` incrementales, particionados por fecha de orden, clusterizados por `product_id`/`distribution_center_id`; `relationships` facts→dims.
Done: `dbt build --select marts.core` verde dos veces seguidas; la segunda corrida valida la lógica incremental y debe procesar significativamente menos bytes que la primera (anotar ambas cifras en el PR).

**Fase 3 — Snapshots SCD2.**
Alcance: copia controlada de `products` a un dataset propio `raw_thelook` (único `CREATE TABLE AS SELECT` permitido sobre la fuente) para poder simular cambios; `snap_products` (estrategia `check` sobre `retail_price`, `cost`); recálculo de margen en `fct_order_items` usando el costo vigente al momento de la venta.
Done: `dbt snapshot` verde; test singular que demuestra al menos un caso de margen histórico ≠ margen con costo actual.

**Fase 4 — Calidad + documentación.**
Alcance: `dbt_expectations`, tests singulares (margen fuera de rango, huérfanos, ventas sin costo), contracts en `fct_order_items` y `dim_products`, descripciones completas, `dbt docs generate`, exposures.
Done: `dbt build` verde con los tests nuevos; docs generados; captura del grafo de linaje en `docs/` del repo.

**Fase 5 — Marts analíticos.**
Alcance: `mart_product_performance`, `mart_inventory_health` (ABC, días de cobertura, dead stock), `mart_customer_rfm`, `mart_fulfillment_sla`.
Done: `dbt build --select marts.analytics` verde; cada mart con al menos una validación de negocio documentada en su yml (ej.: la suma de ingreso del mart cuadra con `fct_order_items`).

**Fase 6 — Features + forecast ML.**
Alcance: `mart_demand_features` (producto × semana: lags, medias móviles, señales de `events`); script en `ml/` que lee de BigQuery, entrena LightGBM con validación temporal (nunca aleatoria: el split respeta el tiempo), escribe `ml_forecast_demand`; ese output se declara como source; `mart_inventory_recommendations` cruza forecast + inventario.
Done: script reproducible con `requirements.txt` propio y README corto en `ml/`; métricas del forecast (MAE/WAPE por horizonte) registradas; `dbt build` verde incluyendo el mart de recomendaciones.

**Fase 7 — Capa semántica (opcional).**
Alcance: métricas revenue, gross_margin, aov, units_sold sobre la spec vigente del Semantic Layer. Verificar la spec actual en docs.getdbt.com antes de escribir una línea: cambió en 2026.
Done: las métricas parsean sin error.

**Fase 8 — Orquestación + CI/CD.**
Alcance: workflow de GitHub Actions en PR (dataset efímero `dbt_ci_pr_<numero>`, `dbt build`, teardown del dataset); Slim CI con `state:modified+ --defer` contra el manifest de prod; corrida diaria programada contra `analytics` (cron de Actions).
Done: un PR de prueba pasa CI de punta a punta; la corrida programada completa en verde y publica artefactos (`manifest.json`) para el defer.

**Fase 9 — BI + writeup.**
Alcance: Evidence.dev (preferido) o Looker Studio sobre los marts; README principal con narrativa raw→recomendación, grafo de linaje, decisiones de arquitectura y cifras (modelos, tests, bytes ahorrados por incremental).
Done: dashboard accesible por link; README completo.

---

## 7. CI/CD: autenticación y aislamiento

- Local = OAuth (ADC). CI = service account. Son mundos separados y no se cruzan.
- La service account `dbt-ci@aleph12.iam.gserviceaccount.com` se crea con roles mínimos: `BigQuery Data Editor` + `BigQuery Job User` sobre el proyecto. El keyfile JSON vive SOLO en GitHub Secrets (`DBT_GOOGLE_KEYFILE`). El workflow lo materializa a un archivo temporal en runtime; el `profiles.yml` de CI se genera dentro del workflow (`method: service-account`) y nunca se commitea con secretos.
- Cada PR construye en su dataset efímero y lo borra al final (`bq rm -r -f`), pase o falle el build. Ningún PR toca `analytics`.
- Solo la corrida programada (o un merge a `main`, cuando se active el deploy) escribe en `analytics`.

---

## 8. Comandos de referencia rápida

```powershell
dbt debug                          # conexión y config
dbt deps                           # instalar packages
dbt parse                          # validación rápida sin tocar el warehouse
dbt build                          # run + test + snapshot + seed, todo
dbt build --select <modelo>+       # modelo y sus descendientes
dbt build --select staging         # una capa
dbt test --select <modelo>         # solo tests
dbt source freshness               # frescura de fuentes
dbt snapshot                       # solo snapshots
dbt docs generate; dbt docs serve  # documentación y linaje
dbt run --full-refresh --select <fct>  # reconstruir un incremental (justificar en PR)
```

---

## 9. Resolución de problemas frecuentes

- `dbt debug` falla con OAuth → `gcloud auth application-default login` de nuevo; verificar `gcloud config get-value project` = `aleph12`.
- `Access Denied / dataset not found` sobre thelook → casi siempre es región: el dataset destino no está en `US`.
- Query bloqueada por `maximum_bytes_billed` → revisar que el incremental filtre por la columna de partición y que no haya `select *` sobre tablas grandes. El límite no se sube (§3.2).
- Incremental que procesa lo mismo en cada corrida → el predicado de `is_incremental()` no está aplicando sobre la columna de partición.
- Windows: si PowerShell bloquea la activación del venv → `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` una vez.
