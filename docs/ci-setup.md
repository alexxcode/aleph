# CI/CD — puesta a punto (una sola vez)

Los workflows (`.github/workflows/`) usan una **service account** cuyo keyfile vive
solo en GitHub Secrets. Estos pasos manejan credenciales, así que los ejecuta la
persona dueña del proyecto (no se automatizan ni se commitea el keyfile).

## 1. Crear la service account y sus roles (mínimos)

```powershell
gcloud iam service-accounts create dbt-ci `
  --project=aleph12 --display-name="dbt CI"

gcloud projects add-iam-policy-binding aleph12 `
  --member="serviceAccount:dbt-ci@aleph12.iam.gserviceaccount.com" `
  --role="roles/bigquery.dataEditor"

gcloud projects add-iam-policy-binding aleph12 `
  --member="serviceAccount:dbt-ci@aleph12.iam.gserviceaccount.com" `
  --role="roles/bigquery.jobUser"
```

## 2. Generar el keyfile (archivo temporal, NO se commitea)

```powershell
gcloud iam service-accounts keys create dbt-ci-key.json `
  --iam-account=dbt-ci@aleph12.iam.gserviceaccount.com
```

## 3. Cargarlo como secret de GitHub

```powershell
gh secret set DBT_GOOGLE_KEYFILE --repo alexxcode/aleph < dbt-ci-key.json
```

Luego **borra el keyfile local**:

```powershell
Remove-Item dbt-ci-key.json
```

Si el keyfile toca el historial de git en algún momento, rota la credencial de
inmediato (borrar el commit no basta).

## 4. Probar de punta a punta

- **Corrida programada:** en GitHub → Actions → *Prod (scheduled)* → *Run workflow*
  (dispara la primera corrida manual; construye `analytics` y publica el manifest).
- **CI de PR:** abre un PR de prueba contra `main`. Debe crear `dbt_ci_pr_<n>`,
  correr `dbt build` (Slim CI si ya hubo una corrida programada) y borrar el
  dataset al final.

## Qué hace cada workflow

| Workflow | Disparo | Acción |
|---|---|---|
| `ci_pr.yml` | PR a `main` | build en dataset efímero `dbt_ci_pr_<n>`, teardown siempre |
| `scheduled_prod.yml` | cron diario 07:00 UTC + manual | `dbt build --full-refresh` sobre `analytics`, publica `manifest.json` |
