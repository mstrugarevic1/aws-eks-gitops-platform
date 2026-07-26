# AWS EKS GitOps Platform — Multi-Environment

This repository deploys isolated `dev`, `staging`, and `production` AWS
environments using the same Terraform and GitOps architecture with
environment-specific configuration.

This is a personal learning and practice project provided as-is. Review
security, availability, and cost settings before using it outside disposable
environments.

Terraform provisions AWS infrastructure. ArgoCD manages Kubernetes add-ons and
workloads after each EKS cluster exists. The sample application exists only to
validate the platform end to end.

## Overview

Each environment has its own Terraform variables, Terraform backend, AWS
resources, GitOps environment config, and rendered ArgoCD Applications.

| Terraform | ArgoCD |
| --- | --- |
| VPC, public, private, and database subnets | AWS Load Balancer Controller |
| Routing and NAT | Cluster Autoscaler |
| EKS cluster and managed node groups | External Secrets Operator |
| AWS Client VPN | metrics-server |
| RDS PostgreSQL | Grafana, VictoriaMetrics, Loki, and Promtail |
| ECR | sample application |
| Secrets Manager entries | |
| IAM and IRSA roles | |
| CloudWatch resources | |

## Architecture

![AWS EKS GitOps platform architecture](docs/images/architecture.png)

## Environments

The environment list is defined in
`gitops/environments/environments.json`.

```text
dev
staging
production
```

Terraform examples live in `terraform/environments/`. GitOps environment config
lives in `gitops/environments/<env>/environment.json`.

## Deployment

Start with `dev`, then repeat the same commands with `ENV=staging` or
`ENV=production` after creating the matching tfvars file.

```bash
# Check local tools and AWS credentials.
make prerequisites

# Create the ignored environment tfvars file.
cp terraform/environments/dev.tfvars.example terraform/environments/dev.tfvars

# Create or reuse the Terraform backend for this environment.
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform

# Initialize the Terraform stack.
make init ENV=dev

# Validate Terraform configuration.
make validate ENV=dev

# Review the AWS infrastructure changes.
make plan ENV=dev

# Apply the AWS infrastructure.
make apply ENV=dev

# Configure kubectl for the new EKS cluster.
make kubeconfig ENV=dev

# Fill the application secret from RDS outputs.
make configure-app-secret ENV=dev

# Install ArgoCD before GitOps reconciliation.
make deploy-argocd ENV=dev

# Write Terraform outputs into GitOps environment config.
make configure-gitops-values ENV=dev

# Validate rendered GitOps configuration.
make gitops-validate ENV=dev

# Apply the root ArgoCD Application.
make apply-argocd-apps ENV=dev

# Run read-only live checks.
make verify ENV=dev
```

Private repositories also need ArgoCD repository credentials:

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

## Validation

```bash
make fmt-check
make check
terraform -chdir=terraform/stack init -backend=false
terraform -chdir=terraform/stack validate
terraform -chdir=terraform/foundation init -backend=false
terraform -chdir=terraform/foundation validate
```

The CI workflow also runs TFLint, Checkov, Ruff, ShellCheck, Helm lint,
kubeconform, actionlint, markdownlint, and Gitleaks.

## Documentation

- [Configuration](docs/configuration.md)
- [Deployment](docs/deployment.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Sample application](app/README.md)

## Cleanup

Destroy Kubernetes-managed resources before Terraform-managed AWS resources:

```bash
make destroy-gitops ENV=dev
make destroy ENV=dev
```

Destroy the Terraform backend only after the environment state is no longer
needed:

```bash
./bootstrap/destroy-bootstrap.sh my-platform dev us-east-1 DELETE_TERRAFORM_BACKEND
```

## Pending Improvements

- Replace placeholder AWS account IDs, certificate ARNs, VPC IDs, role ARNs,
  and image repository values before applying an environment.
- Validate the full flow in real AWS accounts for `dev`, `staging`, and
  `production`.

## Disclaimer

This repository is provided as-is. No guarantee is made regarding correctness,
security, availability, compatibility, cost, or operational outcome.
