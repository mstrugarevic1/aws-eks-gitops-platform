# Secrets

## Path convention

One convention, derived from the same two values everywhere:

```text
<project>/<environment>/example-app
```

For `project = "my-platform"` and `environment = "dev"` that is
`my-platform/dev/example-app`.

| Where | How it is set |
| ----- | ------------- |
| Terraform | `app_secret_name = "${var.project}/${var.environment}/example-app"` in `terraform/stack/main.tf` |
| Terraform output | `app_secret_name` |
| GitOps | `exampleApp.secretManagerPath` in `gitops/environments/<env>/environment.json` |

`make configure-gitops-values ENV=<env>` copies the Terraform output into
`environment.json`, so the two cannot drift. The IRSA policy for External Secrets
is scoped to that one secret ARN.

## Why Terraform creates the secret empty

Terraform creates the Secrets Manager entry but writes no value into it. If it
wrote the database password, that password would be stored in plaintext in the
Terraform state file in S3. Filling the secret from a separate command keeps the
credential out of state entirely.

The RDS master password is managed by RDS itself
(`manage_master_user_password`), so Terraform never sees it either.

## Filling the secret

```bash
make configure-app-secret ENV=dev
```

`scripts/configure-app-secret.sh`:

1. Fails if the Terraform outputs are missing, which means the environment has
   not been applied.
2. Reads the RDS-managed master secret from Secrets Manager.
3. Reads the RDS endpoint, port, database name and user from Terraform outputs.
4. Keeps the existing `APP_SECRET_KEY` if the secret was already filled, and
   generates one with `openssl rand -hex 32` otherwise. Rotating it on every run
   would invalidate live sessions.
5. Writes a new version of the application secret.

It is idempotent, and it never prints a password. The payload is built with `jq`,
so passwords containing shell or URL metacharacters survive intact.

## Keys created

| Key | Value |
| --- | ----- |
| `DB_HOST` | RDS endpoint host |
| `DB_PORT` | RDS port |
| `DB_NAME` | database name |
| `DB_USER` | master user name |
| `DB_PASSWORD` | master password, read from the RDS-managed secret |
| `APP_SECRET_KEY` | application signing key, generated once and preserved |
| `DATABASE_URL` | `postgresql://user:password@host:port/dbname`, URL-encoded |

## How they reach the pod

![Secret flow through the EKS GitOps platform](../architecture.png)

ArgoCD applies two manifests, rendered into
`gitops/environments/<env>/manifests/external-secrets/`:

- a `ClusterSecretStore` named `<env>-aws-secretsmanager`, pointing at the
  environment's region and authenticating as the `external-secrets` service
  account through IRSA;
- an `ExternalSecret` in the application namespace that extracts the whole
  Secrets Manager entry with `dataFrom.extract` and writes it to a Kubernetes
  Secret named by `exampleApp.secretName`.

`dataFrom.extract` copies every JSON key as-is, so the Kubernetes Secret has the
same key names as the table above. It refreshes hourly.

The Deployment consumes it with `envFrom.secretRef`, so all seven keys arrive as
environment variables. `secret.name` in the chart must equal
`exampleApp.secretName` in `environment.json`; a unit test checks that.

## What the application does with them

`DATABASE_URL` drives the `/readyz` probe: the app opens a connection, runs
`SELECT 1`, and caches the result for ten seconds. When `DATABASE_URL` is unset
the check is skipped and the pod stays ready, so the platform can be demonstrated
without RDS.

`DB_PASSWORD` and `APP_SECRET_KEY` are never logged. The database check reports
only the exception type, because the exception message can contain the
connection string.

## Rotation

Rotating the RDS master password is an AWS-side operation. Afterwards:

```bash
make configure-app-secret ENV=dev
```

External Secrets picks up the new version within its refresh interval, or
immediately with:

```bash
kubectl -n example-app annotate externalsecret example-app force-sync=$(date +%s) --overwrite
```

The pods need a restart to see the new environment variables:

```bash
kubectl -n example-app rollout restart deployment
```

## Rules

- No credential is committed. `terraform.tfvars`, `.env`, `*.pem`, `*.key`,
  kubeconfigs and `argocd-repo-key*` are gitignored, and Gitleaks runs in CI.
- Everything `configure-gitops-values` writes into `environment.json` is
  non-secret: account IDs, ARNs, resource names. That file is meant to be
  committed.
- No AWS access key exists in the cluster. Every AWS call from a controller goes
  through IRSA.
