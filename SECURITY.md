# Security

## Scope

This is a learning and portfolio repository. It is not a maintained product and
carries no service-level commitment. The Terraform, Helm and GitOps
configuration here is a starting point that must be reviewed before it is used
for anything that holds real data.

## Reporting a vulnerability

Open a GitHub security advisory on this repository, or a regular issue if the
problem is not sensitive. Please do not include credentials, account IDs,
kubeconfigs or ARNs from a real account in the report.

## What this repository does with secrets

- No credential is committed. `terraform.tfvars`, `.env`, kubeconfigs and
  private keys are gitignored.
- The application secret in AWS Secrets Manager is created empty by Terraform
  and filled by `make configure-app-secret`, so no database password ever
  reaches Terraform state.
- The RDS master password is managed by RDS itself and read only at the moment
  the application secret is written.
- External Secrets Operator reads Secrets Manager through IRSA. No AWS access
  key exists in the cluster.
- CI runs without AWS credentials. The image build workflow uses GitHub OIDC to
  assume a role; there is no long-lived key.
- Gitleaks runs on every pull request and on pushes to `main`.

See [docs/secrets.md](docs/secrets.md) for the full flow.

## Known weak defaults

These are deliberate so the dev environment is cheap and easy to tear down.
Change them before using this for anything real:

- The EKS API endpoint is public, restricted only by `eks_public_access_cidrs`.
- ArgoCD is installed with its built-in admin user and without ingress or SSO.
- The dev environment sets `ecr_force_delete = true`,
  `rds_skip_final_snapshot = true`, `rds_deletion_protection = false` and
  `app_secret_recovery_days = 0`.
- The example application is served over plain HTTP when no ACM certificate is
  configured.
