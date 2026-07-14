"""Aleph — dashboard de negocio (Fase 9).

Lee los marts analíticos de BigQuery y presenta ventas/margen, salud de
inventario (ABC), segmentación RFM, SLA de fulfillment y las recomendaciones
de inventario (forecast ML). Se autentica con Application Default Credentials.

Uso local:
    pip install -r bi/requirements.txt
    streamlit run bi/app.py
"""
from __future__ import annotations

import os

import pandas as pd
import plotly.express as px
import streamlit as st
from google.cloud import bigquery

PROJECT = os.environ.get("ALEPH_PROJECT", "aleph12")
DATASET = os.environ.get("ALEPH_DATASET", "dbt_alexis")

st.set_page_config(page_title="Aleph — Analytics", page_icon="📦", layout="wide")


@st.cache_resource
def _client() -> bigquery.Client:
    return bigquery.Client(project=PROJECT)


@st.cache_data(ttl=3600)
def q(sql: str) -> pd.DataFrame:
    return _client().query(sql, location="US").to_dataframe()


def t(name: str) -> str:
    return f"`{PROJECT}.{DATASET}.{name}`"


# --------------------------------------------------------------------------- #
st.title("📦 Aleph — Plataforma de analítica")
st.caption(
    "De datos crudos a recomendaciones de inventario, sobre dbt + BigQuery. "
    f"Fuente: `{PROJECT}.{DATASET}`."
)

# KPIs -----------------------------------------------------------------------
kpi = q(f"""
    select
        sum(gross_revenue)                              as revenue,
        sum(gross_margin_amount)                        as gross_margin,
        sum(n_line_items)                               as units,
        count(*)                                        as orders,
        safe_divide(sum(gross_revenue), count(*))       as aov
    from {t('fct_orders')}
""").iloc[0]

c1, c2, c3, c4, c5 = st.columns(5)
c1.metric("Ingreso", f"${kpi.revenue/1e6:,.2f}M")
c2.metric("Margen bruto", f"${kpi.gross_margin/1e6:,.2f}M")
c3.metric("Unidades", f"{int(kpi.units):,}")
c4.metric("Órdenes", f"{int(kpi.orders):,}")
c5.metric("Ticket promedio", f"${kpi.aov:,.2f}")

tabs = st.tabs([
    "📈 Productos", "📦 Inventario (ABC)", "👥 Clientes (RFM)",
    "🚚 Fulfillment", "🔮 Recomendaciones (ML)",
])

# --- Productos --------------------------------------------------------------
with tabs[0]:
    st.subheader("Desempeño por producto")
    by_cat = q(f"""
        select category,
               sum(gross_revenue) as revenue,
               sum(gross_margin_amount) as margin,
               sum(units_sold) as units
        from {t('mart_product_performance')}
        group by category order by revenue desc
    """)
    col1, col2 = st.columns(2)
    col1.plotly_chart(
        px.bar(by_cat.head(15), x="revenue", y="category", orientation="h",
               title="Ingreso por categoría", labels={"revenue": "Ingreso", "category": ""}),
        use_container_width=True)
    by_cat["margin_pct"] = by_cat["margin"] / by_cat["revenue"]
    col2.plotly_chart(
        px.bar(by_cat.head(15), x="margin_pct", y="category", orientation="h",
               title="Margen % por categoría", labels={"margin_pct": "Margen %", "category": ""}),
        use_container_width=True)

    trend = q(f"""
        select month_start_date, sum(gross_revenue) as revenue, sum(units_sold) as units
        from {t('mart_product_performance')}
        group by month_start_date order by month_start_date
    """)
    st.plotly_chart(
        px.line(trend, x="month_start_date", y="revenue", title="Ingreso mensual",
                labels={"month_start_date": "", "revenue": "Ingreso"}),
        use_container_width=True)

# --- Inventario ABC ---------------------------------------------------------
with tabs[1]:
    st.subheader("Salud de inventario y clasificación ABC")
    abc = q(f"""
        select abc_class,
               count(*) as skus,
               sum(inventory_cost_on_hand) as capital,
               countif(is_dead_stock) as dead_stock
        from {t('mart_inventory_health')}
        group by abc_class order by abc_class
    """)
    col1, col2 = st.columns(2)
    col1.plotly_chart(
        px.bar(abc, x="abc_class", y="skus", color="abc_class",
               title="SKUs por clase ABC", labels={"abc_class": "Clase", "skus": "SKUs"}),
        use_container_width=True)
    col2.plotly_chart(
        px.pie(abc, names="abc_class", values="capital", title="Capital en inventario por clase ABC"),
        use_container_width=True)
    st.metric("SKUs marcados como dead stock", f"{int(abc['dead_stock'].sum()):,}")

# --- Clientes RFM -----------------------------------------------------------
with tabs[2]:
    st.subheader("Segmentación RFM")
    seg = q(f"""
        select segment, count(*) as clientes, sum(monetary) as valor
        from {t('mart_customer_rfm')}
        group by segment order by clientes desc
    """)
    col1, col2 = st.columns(2)
    col1.plotly_chart(
        px.bar(seg, x="segment", y="clientes", color="segment",
               title="Clientes por segmento", labels={"segment": "", "clientes": "Clientes"}),
        use_container_width=True)
    col2.plotly_chart(
        px.bar(seg, x="segment", y="valor", color="segment",
               title="Valor monetario por segmento", labels={"segment": "", "valor": "Gasto"}),
        use_container_width=True)

# --- Fulfillment ------------------------------------------------------------
with tabs[3]:
    st.subheader("SLA de fulfillment por centro")
    sla = q(f"""
        select distribution_center_name,
               avg(avg_hours_to_ship) as hrs_ship,
               avg(avg_hours_to_deliver) as hrs_deliver
        from {t('mart_fulfillment_sla')}
        where distribution_center_name is not null
        group by distribution_center_name order by hrs_ship
    """)
    st.plotly_chart(
        px.bar(sla, x="distribution_center_name", y=["hrs_ship", "hrs_deliver"],
               barmode="group", title="Horas promedio: order→ship y ship→deliver",
               labels={"distribution_center_name": "Centro", "value": "Horas", "variable": ""}),
        use_container_width=True)

# --- Recomendaciones ML -----------------------------------------------------
with tabs[4]:
    st.subheader("Recomendaciones de inventario (forecast LightGBM)")
    status = q(f"""
        select inventory_status,
               count(*) as skus,
               sum(inventory_cost_on_hand) as capital
        from {t('mart_inventory_recommendations')}
        group by inventory_status order by skus desc
    """)
    col1, col2 = st.columns(2)
    col1.plotly_chart(
        px.bar(status, x="inventory_status", y="skus", color="inventory_status",
               title="SKUs por estado de inventario", labels={"inventory_status": "", "skus": "SKUs"}),
        use_container_width=True)
    col2.plotly_chart(
        px.bar(status, x="inventory_status", y="capital", color="inventory_status",
               title="Capital inmovilizado por estado", labels={"inventory_status": "", "capital": "USD"}),
        use_container_width=True)

    fc = q(f"""
        select category, sum(predicted_units) as forecast_8w
        from {t('ml_forecast_demand')}
        group by category order by forecast_8w desc limit 15
    """)
    st.plotly_chart(
        px.bar(fc, x="forecast_8w", y="category", orientation="h",
               title="Demanda pronosticada (8 semanas) por categoría",
               labels={"forecast_8w": "Unidades", "category": ""}),
        use_container_width=True)

st.caption("Aleph · dbt + BigQuery + LightGBM · dashboard Streamlit (Fase 9)")
