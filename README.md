# Aleph

[![CI (PR)](https://github.com/alexxcode/aleph/actions/workflows/ci_pr.yml/badge.svg)](https://github.com/alexxcode/aleph/actions/workflows/ci_pr.yml)
[![Prod (scheduled)](https://github.com/alexxcode/aleph/actions/workflows/scheduled_prod.yml/badge.svg)](https://github.com/alexxcode/aleph/actions/workflows/scheduled_prod.yml)

> *"El lugar donde están, sin confundirse, todos los lugares del orbe, vistos desde todos los ángulos."* — J. L. Borges

En ingeniería de datos, ese punto que lo contiene todo tiene un nombre más prosaico: **Single Source of Truth**. **Aleph** es una plataforma de analítica *end-to-end* para un distribuidor de e-commerce, construida sobre **dbt + BigQuery**, que va del dato crudo a una recomendación de inventario accionable — y cierra el círculo devolviendo un pronóstico de demanda (ML) al warehouse.

---

## Qué hace

Toma el esquema de un distribuidor real (el dataset público `bigquery-public-data.thelook_ecommerce`) y lo transporta por todas las capas de una plataforma analítica de producción:

```
sources → staging → intermediate → marts (dims · facts · analíticos) → capa ML → capa semántica → BI
```

El diferencial no es el dashboard final, sino el **loop completo**: la ingeniería analítica alimenta un modelo de forecasting (LightGBM), y ese pronóstico regresa como fuente a dbt para producir recomendaciones de reorden, stock de seguridad y alertas de quiebre.

---

## Arquitectura

```mermaid
flowchart LR
    src[(thelook_ecommerce\n7 tablas)] --> stg[staging\nstg_thelook__*]
    stg --> int[intermediate\nint_*]
    int --> dim[dims\ndim_*]
    int --> fct[facts\nfct_* incrementales]
    dim --> mart[marts analíticos\nmart_*]
    fct --> mart
    fct --> feat[mart_demand_features]
    feat --> ml{{LightGBM\nforecast}}
    ml --> fcast[(ml_forecast_demand)]
    fcast --> reco[mart_inventory_recommendations]
    fct --> reco
    mart --> bi[[BI / Evidence.dev]]
    reco --> bi
```

**Patrón:** medallón estilo Kimball (star schema). Facts incrementales, particionados por fecha y clusterizados. Snapshots SCD2 para calcular el margen con el **costo vigente al momento de la venta**, no el actual.

---

## Stack

| Capa | Herramienta |
|---|---|
| Warehouse | BigQuery (región `US`) |
| Transformación | dbt Core 1.11 + `dbt-bigquery` |
| Calidad | tests genéricos + singulares, `dbt_utils`, `dbt_expectations`, model contracts |
| ML | Python 3.12, LightGBM (validación temporal) |
| CI/CD | GitHub Actions (dataset efímero por PR, Slim CI, corrida programada) |
| BI | Evidence.dev |

---

## Estructura del repo

```
models/
├── staging/thelook/     # limpieza 1:1 con la fuente
├── intermediate/        # joins y enriquecimiento
└── marts/
    ├── core/            # dimensiones y hechos (star schema)
    └── analytics/       # marts de consumo de negocio
snapshots/               # SCD2 (historial precio/costo)
ml/                      # forecast de demanda (Python)
macros/  ·  tests/  ·  seeds/  ·  .github/workflows/
```

---

## Roadmap

- [x] **Fase 0 — Fundaciones.** Proyecto GCP, dbt + BigQuery, repo, materializaciones por capa.
- [x] **Fase 1 — Sources + staging.** Las 7 tablas como `source` con freshness; los 7 modelos de staging.
- [x] **Fase 2 — Núcleo dimensional.** Dims + facts incrementales, partición/cluster, relationships.
- [x] **Fase 3 — Snapshots SCD2.** Historial de precio/costo y margen histórico correcto.
- [x] **Fase 4 — Calidad + documentación.** `dbt_expectations`, tests singulares, contracts, exposures, [grafo de linaje](docs/lineage.md).
- [x] **Fase 5 — Marts analíticos.** Performance de producto, salud de inventario (ABC), RFM, SLA de fulfillment.
- [x] **Fase 6 — Features + forecast ML.** Features de demanda (categoría×semana), LightGBM con validación temporal, forecast de vuelta a BQ, recomendaciones de inventario.
- [x] **Fase 7 — Capa semántica.** Métricas (revenue, gross_margin, aov, units_sold) con MetricFlow.
- [x] **Fase 8 — Orquestación + CI/CD.** Actions (dataset efímero por PR + teardown), Slim CI (`state:modified+ --defer`), corrida diaria a `analytics`. Ver [setup](docs/ci-setup.md).
- [ ] **Fase 9 — BI + writeup.** Dashboard y narrativa raw → recomendación.

---

## Cómo correrlo

```powershell
# 1. Entorno
python -m venv .venv
.\.venv\Scripts\Activate.ps1
pip install -r requirements.txt

# 2. Autenticación (OAuth / Application Default Credentials)
gcloud auth application-default login

# 3. Verificar conexión y construir
dbt debug
dbt build
```

> El `profiles.yml` vive en `~/.dbt/` y **nunca** se versiona. El repo no contiene credenciales.

---

*Proyecto en construcción — este README se actualiza al cierre de cada fase.*
