# example-app

Minimal workload used to exercise the platform end to end. It is not a real
application and is not meant to grow into one.

| Endpoint   | Purpose                                                        |
| ---------- | -------------------------------------------------------------- |
| `/`        | service info as JSON                                            |
| `/healthz` | liveness probe, 200 while the process is up                     |
| `/readyz`  | readiness probe, 503 when a configured database is unreachable  |
| `/metrics` | Prometheus text format, scraped through the `VMServiceScrape`   |

## Configuration

From the ConfigMap rendered by the Helm chart:

| Variable    | Default   | Meaning                          |
| ----------- | --------- | -------------------------------- |
| `APP_ENV`   | `unknown` | environment name                 |
| `LOG_LEVEL` | `INFO`    | Python log level                 |
| `PORT`      | `8000`    | listen port                      |

From the Kubernetes Secret produced by the `ExternalSecret`
(see [docs/deployment.md](../docs/deployment.md#8-fill-the-application-secret)):

| Variable         | Meaning                                                   |
| ---------------- | --------------------------------------------------------- |
| `DATABASE_URL`   | full `postgresql://` URL; when unset the DB check is skipped |
| `DB_HOST`        | RDS endpoint host                                          |
| `DB_PORT`        | RDS port                                                   |
| `DB_NAME`        | database name                                              |
| `DB_USER`        | database user                                              |
| `DB_PASSWORD`    | database password, never logged                            |
| `APP_SECRET_KEY` | application signing key, never logged                      |

## Build

```bash
make build-app ENV=dev TAG=0.1.0
```

That builds `app/Dockerfile`, tags it with the ECR repository from the
environment's Terraform output, and pushes it. CI does the same through
`.github/workflows/build-app.yml`.

## Run locally

```bash
docker build -t example-app:dev app
docker run --rm -p 8000:8000 -e APP_ENV=local example-app:dev
curl localhost:8000/healthz
```
