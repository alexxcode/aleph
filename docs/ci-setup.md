# CI/CD — puesta a punto (una sola vez)

Los workflows (`.github/workflows/`) se autentican en GCP con **Workload Identity
Federation (WIF)**: GitHub Actions obtiene credenciales vía OIDC, **sin keyfile**
ni secretos que rotar. La service account solo recibe permisos; nunca se exporta
una llave.

> Nota: la creación de keyfiles de service account está deshabilitada por política
> de seguridad (`iam.disableServiceAccountKeyCreation`). WIF es la alternativa
> recomendada y no requiere desactivar esa política.

## 1. Service account y roles (ya hecho)

```powershell
gcloud iam service-accounts create dbt-ci --project=aleph12 --display-name="dbt CI"
gcloud projects add-iam-policy-binding aleph12 --member="serviceAccount:dbt-ci@aleph12.iam.gserviceaccount.com" --role="roles/bigquery.dataEditor"
gcloud projects add-iam-policy-binding aleph12 --member="serviceAccount:dbt-ci@aleph12.iam.gserviceaccount.com" --role="roles/bigquery.jobUser"
```

## 2. Workload Identity Pool + provider OIDC (restringido al repo)

```powershell
gcloud iam workload-identity-pools create github-pool `
  --project=aleph12 --location=global --display-name="GitHub Actions"

gcloud iam workload-identity-pools providers create-oidc github-provider `
  --project=aleph12 --location=global --workload-identity-pool=github-pool `
  --display-name="GitHub OIDC" `
  --issuer-uri="https://token.actions.githubusercontent.com" `
  --attribute-mapping="google.subject=assertion.sub,attribute.repository=assertion.repository" `
  --attribute-condition="assertion.repository=='alexxcode/aleph'"
```

## 3. Permitir que el repo impersone la service account

```powershell
$POOL = gcloud iam workload-identity-pools describe github-pool `
  --project=aleph12 --location=global --format="value(name)"

gcloud iam service-accounts add-iam-policy-binding dbt-ci@aleph12.iam.gserviceaccount.com `
  --project=aleph12 --role="roles/iam.workloadIdentityUser" `
  --member="principalSet://iam.googleapis.com/$POOL/attribute.repository/alexxcode/aleph"
```

## 4. Variables del repo (no son secretos)

```powershell
$PN = gcloud projects describe aleph12 --format="value(projectNumber)"
$PROVIDER = "projects/$PN/locations/global/workloadIdentityPools/github-pool/providers/github-provider"

gh variable set GCP_WIF_PROVIDER   --repo alexxcode/aleph --body "$PROVIDER"
gh variable set GCP_SERVICE_ACCOUNT --repo alexxcode/aleph --body "dbt-ci@aleph12.iam.gserviceaccount.com"
```

## 5. Probar de punta a punta

- **Corrida programada:** GitHub → Actions → *Prod (scheduled)* → **Run workflow**
  (construye `analytics` y publica el manifest para el defer).
- **CI de PR:** abre un PR de prueba contra `main`. Debe crear `dbt_ci_pr_<n>`,
  correr `dbt build` (Slim CI si ya hubo una corrida programada) y borrar el
  dataset al final.

## Qué hace cada workflow

| Workflow | Disparo | Acción |
|---|---|---|
| `ci_pr.yml` | PR a `main` | build en dataset efímero `dbt_ci_pr_<n>`, teardown siempre |
| `scheduled_prod.yml` | cron diario 07:00 UTC + manual | `dbt build --full-refresh` sobre `analytics`, publica `manifest.json` |
