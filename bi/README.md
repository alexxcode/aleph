# Dashboard BI (Fase 9)

Dashboard de negocio en **Streamlit** sobre los marts de BigQuery: ventas y
margen por producto, salud de inventario (ABC), segmentación RFM, SLA de
fulfillment y las recomendaciones de inventario que consumen el forecast ML.

## Correr en local

```powershell
# desde la raíz del repo, con el .venv activo
pip install -r bi/requirements.txt
streamlit run bi/app.py
```

Se autentica con **Application Default Credentials** (las mismas de dbt en local:
`gcloud auth application-default login`). Abre http://localhost:8501.

Por defecto lee de `aleph12.dbt_alexis`. Para apuntar a prod:

```powershell
$env:ALEPH_DATASET = "analytics"; streamlit run bi/app.py
```

## Deploy (link público)

**Streamlit Community Cloud** (gratis): conecta el repo de GitHub y apunta la app
a `bi/app.py`. Para el acceso a BigQuery en la nube se necesita una credencial de
service account en `st.secrets` (misma SA `dbt-ci`); como la creación de keyfiles
está deshabilitada por política, la alternativa es usar un proyecto de solo lectura
o correr el dashboard on-demand en local para capturas. El código de la app no
cambia entre local y deploy.

## Estructura

- `app.py` — dashboard (5 pestañas + KPIs), queries cacheadas 1h.
- `requirements.txt` — streamlit, plotly, google-cloud-bigquery.
