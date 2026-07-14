"""Forecast de demanda por categoria x semana (Fase 6 del proyecto Aleph).

Lee mart_demand_features de BigQuery, entrena un LightGBM global con validacion
temporal (recursiva, multi-horizonte), registra metricas (MAE/WAPE por horizonte)
y escribe el pronostico de las proximas H semanas en aleph12.<dataset>.ml_forecast_demand.

Uso:
    python ml/train_forecast.py --project aleph12 --dataset dbt_alexis --horizon 8
"""
from __future__ import annotations

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import numpy as np
import pandas as pd
import lightgbm as lgb
from google.cloud import bigquery

FEATURES = [
    "category",
    "week_of_year", "month_of_year",
    "lag_1w", "lag_2w", "lag_4w", "lag_8w",
    "roll_mean_4w", "roll_mean_12w", "roll_std_12w",
    "events_total", "events_purchase", "events_cart",
]
TARGET = "units_sold"
CAT_FEATURES = ["category"]


def load_data(project: str, dataset: str) -> pd.DataFrame:
    client = bigquery.Client(project=project)
    sql = f"select * from `{project}.{dataset}.mart_demand_features`"
    df = client.query(sql, location="US").to_dataframe()
    df["week_start_date"] = pd.to_datetime(df["week_start_date"])
    df = df.sort_values(["category", "week_start_date"]).reset_index(drop=True)
    df["category"] = df["category"].astype("category")
    return df


def train_model(train_df: pd.DataFrame) -> lgb.LGBMRegressor:
    model = lgb.LGBMRegressor(
        objective="regression_l1",   # MAE: robusto para demanda
        n_estimators=400,
        learning_rate=0.05,
        num_leaves=31,
        min_child_samples=20,
        subsample=0.8,
        colsample_bytree=0.8,
        random_state=42,
        verbose=-1,
    )
    model.fit(
        train_df[FEATURES], train_df[TARGET],
        categorical_feature=CAT_FEATURES,
    )
    return model


def _feature_row(category, week, hist, events):
    """Construye la fila de features para una semana futura dado el historico."""
    s = hist  # lista de unidades (actuals + predicciones) mas reciente al final
    def lag(k):
        return s[-k] if len(s) >= k else np.nan
    last12 = s[-12:] if len(s) >= 1 else [0]
    return {
        "category": category,
        "week_of_year": int(pd.Timestamp(week).isocalendar().week),
        "month_of_year": int(pd.Timestamp(week).month),
        "lag_1w": lag(1), "lag_2w": lag(2), "lag_4w": lag(4), "lag_8w": lag(8),
        "roll_mean_4w": float(np.mean(s[-4:])) if s else np.nan,
        "roll_mean_12w": float(np.mean(last12)),
        "roll_std_12w": float(np.std(last12)),
        "events_total": events["events_total"],
        "events_purchase": events["events_purchase"],
        "events_cart": events["events_cart"],
    }


def recursive_forecast(model, df, start_week, horizon, events_assumption):
    """Pronostica `horizon` semanas desde start_week (inclusive) por categoria,
    de forma recursiva (cada semana usa las predicciones previas como lags)."""
    rows = []
    for category, g in df.groupby("category", observed=True):
        g = g[g["week_start_date"] < start_week]
        hist = g[TARGET].tolist()
        for h in range(horizon):
            week = pd.Timestamp(start_week) + pd.Timedelta(weeks=int(h))
            feat = _feature_row(category, week, hist, events_assumption)
            X = pd.DataFrame([feat])
            X["category"] = X["category"].astype("category")
            pred = float(model.predict(X)[0])
            pred = max(0.0, pred)
            rows.append({
                "category": category, "forecast_week": week.date(),
                "week_ahead": h + 1, "predicted_units": round(pred, 2),
            })
            hist.append(pred)
    return pd.DataFrame(rows)


def evaluate(df, horizon):
    """Validacion temporal recursiva: reserva las ultimas `horizon` semanas."""
    max_week = df["week_start_date"].max()
    valid_start = max_week - pd.Timedelta(weeks=horizon - 1)
    train_df = df[df["week_start_date"] < valid_start].dropna(subset=FEATURES)
    model = train_model(train_df)

    ev = _recent_events(df[df["week_start_date"] < valid_start])
    fc = recursive_forecast(model, df, valid_start, horizon, ev)

    actual = df[df["week_start_date"] >= valid_start][
        ["category", "week_start_date", TARGET]
    ].copy()
    actual["forecast_week"] = actual["week_start_date"].dt.date
    m = fc.merge(actual, on=["category", "forecast_week"], how="inner")

    per_h = []
    for h in range(1, horizon + 1):
        sub = m[m["week_ahead"] == h]
        mae = (sub["predicted_units"] - sub[TARGET]).abs().mean()
        wape = (sub["predicted_units"] - sub[TARGET]).abs().sum() / max(sub[TARGET].sum(), 1)
        per_h.append({"week_ahead": h, "mae": round(mae, 2), "wape": round(wape, 4)})
    overall_wape = (m["predicted_units"] - m[TARGET]).abs().sum() / max(m[TARGET].sum(), 1)
    overall_mae = (m["predicted_units"] - m[TARGET]).abs().mean()
    return {"per_horizon": per_h,
            "overall": {"mae": round(overall_mae, 2), "wape": round(overall_wape, 4)},
            "valid_start": str(valid_start.date()), "n_valid_points": int(len(m))}


def _recent_events(df):
    last_weeks = df.sort_values("week_start_date")["week_start_date"].unique()[-4:]
    recent = df[df["week_start_date"].isin(last_weeks)]
    return {
        "events_total": float(recent.groupby("week_start_date")["events_total"].first().mean()),
        "events_purchase": float(recent.groupby("week_start_date")["events_purchase"].first().mean()),
        "events_cart": float(recent.groupby("week_start_date")["events_cart"].first().mean()),
    }


def write_forecast(project, dataset, fc, metrics):
    client = bigquery.Client(project=project)
    fc = fc.copy()
    fc["forecast_week"] = pd.to_datetime(fc["forecast_week"])
    fc["generated_at"] = datetime.now(timezone.utc)
    fc["model"] = "lightgbm_l1_v1"
    table_id = f"{project}.{dataset}.ml_forecast_demand"
    job = client.load_table_from_dataframe(
        fc, table_id,
        job_config=bigquery.LoadJobConfig(write_disposition="WRITE_TRUNCATE"),
    )
    job.result()
    print(f"[ok] {len(fc)} filas escritas en {table_id}")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--project", default="aleph12")
    ap.add_argument("--dataset", default="dbt_alexis")
    ap.add_argument("--horizon", type=int, default=8)
    args = ap.parse_args()

    print(f"[1/4] Cargando features de {args.project}.{args.dataset}.mart_demand_features ...")
    df = load_data(args.project, args.dataset)
    print(f"      {len(df)} filas, {df['category'].nunique()} categorias, "
          f"{df['week_start_date'].nunique()} semanas")

    print(f"[2/4] Validacion temporal recursiva (horizonte={args.horizon}) ...")
    metrics = evaluate(df, args.horizon)
    for h in metrics["per_horizon"]:
        print(f"      h+{h['week_ahead']}: MAE={h['mae']:>7}  WAPE={h['wape']:.3f}")
    print(f"      GLOBAL: MAE={metrics['overall']['mae']}  WAPE={metrics['overall']['wape']}")

    print("[3/4] Reentrenando en todo el historico y pronosticando ...")
    full = df.dropna(subset=FEATURES)
    model = train_model(full)
    next_week = df["week_start_date"].max() + pd.Timedelta(weeks=1)
    fc = recursive_forecast(model, df, next_week, args.horizon, _recent_events(df))

    print(f"[4/4] Escribiendo forecast en {args.dataset}.ml_forecast_demand ...")
    write_forecast(args.project, args.dataset, fc, metrics)

    metrics["generated_at"] = datetime.now(timezone.utc).isoformat()
    metrics["horizon"] = args.horizon
    Path(__file__).parent.joinpath("metrics.json").write_text(
        json.dumps(metrics, indent=2), encoding="utf-8")
    print("[done] metricas en ml/metrics.json")


if __name__ == "__main__":
    main()
