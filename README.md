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

Use [docs/deployment.md](docs/deployment.md) for the complete deployment guide:
prerequisites, required values, credentials, networking, commands, expected
flow, verification, and the relevant failure checks.

## Validation

```bash
make fmt-check
make check
make validate-offline
```

The CI workflow also runs TFLint, Checkov, Ruff, ShellCheck, Helm lint,
kubeconform, actionlint, markdownlint, and Gitleaks.

## Documentation

- [Deployment guide](docs/deployment.md): complete environment deployment path
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

## Before Deployment

- Replace placeholder AWS account IDs, certificate ARNs, VPC IDs, role ARNs,
  and image repository values before applying an environment.
- Create the `production` Git branch or change the production GitOps
  `targetRevision` to an immutable release tag or commit SHA before applying it.
- Validate the full flow in real AWS accounts for `dev`, `staging`, and
  `production`.

## Disclaimer

This repository is provided as-is. No guarantee is made regarding correctness,
security, availability, compatibility, cost, or operational outcome.
