# AWS EKS GitOps Platform

Personal learning repository for an AWS EKS platform managed with Terraform and
ArgoCD.

Terraform provisions the AWS infrastructure. ArgoCD manages Kubernetes add-ons
and the example application after the cluster exists. The project is meant for
practice and portfolio review, not as a reusable platform product.

## Architecture

![AWS EKS GitOps platform architecture](docs/images/architecture.png)

The diagram will be added manually.

## What This Demonstrates

- AWS infrastructure provisioning with Terraform.
- EKS cluster setup with managed node groups and IRSA.
- GitOps reconciliation with ArgoCD Applications.
- Kubernetes add-on management through Helm and manifests.
- A small Python application deployed through a Helm chart.
- Integration with RDS PostgreSQL through External Secrets Operator.
- Offline validation for Terraform, GitOps rendering, Helm, Kubernetes
  manifests, shell scripts, Python, Markdown, workflows, and secret scanning.

## Ownership Boundary

Terraform owns AWS resources:

- VPC, public subnets, private subnets, database subnets, routing, and NAT;
- EKS cluster and managed node groups;
- AWS Client VPN;
- RDS PostgreSQL;
- ECR;
- Secrets Manager entries;
- IAM and IRSA roles;
- CloudWatch resources;
- Terraform backend resources.

ArgoCD owns resources inside Kubernetes:

- AWS Load Balancer Controller;
- Cluster Autoscaler;
- External Secrets Operator;
- metrics-server;
- Grafana, VictoriaMetrics, Loki, and Promtail;
- the example application.

ArgoCD itself is installed by Helm before GitOps reconciliation starts.

## Main Components

- `terraform/stack`: shared Terraform root for the EKS platform.
- `terraform/foundation`: optional GitHub OIDC role for image pushes.
- `terraform/modules`: network, EKS, Client VPN, RDS, and observability modules.
- `gitops/base`: component registry used by the GitOps renderer.
- `gitops/environments`: rendered ArgoCD root and child Applications.
- `gitops/addons/observability`: GitOps-managed observability values and
  dashboards.
- `gitops/apps/example-app/chart`: stateless example application Helm chart.
- `app`: minimal Python web application and Dockerfile.
- `scripts`: helper scripts for GitOps rendering, secrets, verification, and
  cleanup.

## Repository Structure

```text
.
|-- app/
|-- bootstrap/
|-- deploy/
|   `-- argocd/
|-- docs/
|-- gitops/
|   |-- addons/
|   |-- apps/
|   |-- base/
|   `-- environments/
|-- scripts/
|-- terraform/
|   |-- environments/
|   |-- foundation/
|   |-- modules/
|   `-- stack/
`-- tests/
```

## Minimal Quick Start

Use `dev` first and keep it disposable.

```bash
make prerequisites
cp terraform/environments/dev.tfvars.example terraform/environments/dev.tfvars
```

Edit `terraform/environments/dev.tfvars`, then run:

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
make apply ENV=dev
make kubeconfig ENV=dev
make configure-app-secret ENV=dev
make deploy-argocd ENV=dev
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
```

Commit and push the rendered GitOps environment files so ArgoCD can read them,
then apply the root Application:

```bash
make apply-argocd-apps ENV=dev
make verify ENV=dev
```

For private repositories, register an ArgoCD deploy key before applying the root
Application:

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

## Documentation

- [Configuration](docs/configuration.md)
- [Deployment](docs/deployment.md)
- [Troubleshooting](docs/troubleshooting.md)
- [Example application](app/README.md)

## Validation Commands

```bash
make fmt-check
make validate ENV=dev
make check
terraform -chdir=terraform/foundation init -backend=false
terraform -chdir=terraform/foundation validate
```

The GitHub workflow also runs TFLint, Checkov, Ruff, ShellCheck, Helm lint,
Helm template, kubeconform, actionlint, markdownlint, and Gitleaks.

## Scope And Limitations

- The example app is a stateless Deployment connected to PostgreSQL on RDS.
- The project does not deploy a complete production operating model.
- The `production` environment files are examples of stricter defaults, not a
  claim that the repository is production-ready.
- Real AWS behavior still depends on account limits, IAM permissions, regional
  service availability, certificate setup, quotas, and current AWS pricing.
- Destroy Kubernetes-managed resources before destroying Terraform-managed AWS
  infrastructure, because Kubernetes controllers can create AWS load balancers.

## Disclaimer

This repository is a personal learning and practice project.

It is provided as-is and is not a production-ready platform, managed
service, official reference architecture, or guarantee of any particular
technical or operational outcome.

The configuration has not been validated for every AWS account, region,
workload, security requirement, availability requirement, or cost profile.

Review and adapt all infrastructure, IAM, networking, security, database,
backup, monitoring, and operational settings before using any part of the
project outside a disposable environment.

AWS resources created by this project may incur charges.

No guarantee is made regarding correctness, security, availability,
compatibility, cost, or operational outcome.
