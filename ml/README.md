# Forecast de demanda (Fase 6)

Paso de Python que cierra el loop analytics ↔ ML: entrena un modelo de demanda,
escribe el pronóstico de vuelta a BigQuery y ese output reingresa a dbt como
`source` para producir recomendaciones de inventario.

## Qué hace

- **Entrada:** `mart_demand_features` (dbt) — grano **categoría × semana**, panel
  denso con target (unidades), lags (1/2/4/8 sem), medias móviles (4/12 sem),
  calendario y señales de tráfico web (`events`).
- **Modelo:** un único **LightGBM** global (`objective=regression_l1`), con la
  categoría como feature categórica nativa.
- **Validación:** **temporal recursiva** (nunca aleatoria). Reserva las últimas
  H semanas y las pronostica de forma recursiva (cada semana usa las predicciones
  previas como lags). Se reportan **MAE y WAPE por horizonte**.
- **Salida:** `aleph12.<dataset>.ml_forecast_demand` (categoría × semana futura),
  declarada como `source` en dbt → alimenta `mart_inventory_recommendations`.

## Por qué categoría × semana (y no producto)

La demanda por SKU es extremadamente dispersa: ningún producto supera ~24 ventas
en 3 años, y el 98% de las combinaciones producto×semana son cero. A ese grano no
hay señal. A nivel **categoría** (26 categorías, ~150–300 u/semana) la señal es
fuerte y forecasteable. El forecast de categoría se **asigna a cada SKU por su
participación reciente** en el mart de recomendaciones (forecasting jerárquico
top-down), de modo que las recomendaciones siguen siendo a nivel SKU × centro.

## Cómo ejecutar

```powershell
# desde la raíz del repo, con el .venv activo
pip install -r ml/requirements.txt
python ml/train_forecast.py --project aleph12 --dataset dbt_alexis --horizon 8
```

Luego, en dbt:

```powershell
dbt build --select mart_inventory_recommendations
```

## Métricas (última corrida)

Ver `ml/metrics.json`. Referencia: WAPE ≈ 0.11 a 1 semana, degradando con el
horizonte (esperado en forecast recursivo); WAPE global ≈ 0.32 sobre 8 semanas.

## Reproducibilidad

El modelo usa `random_state=42`. El script es idempotente: sobrescribe
`ml_forecast_demand` (WRITE_TRUNCATE) en cada corrida. La orquestación de este
paso dentro del pipeline se aborda en la Fase 8.
