# EKS GitOps Platform

[![checks](https://github.com/mstrugarevic1/eks-gitops-platform/actions/workflows/checks.yml/badge.svg?branch=main&event=push)](https://github.com/mstrugarevic1/eks-gitops-platform/actions/workflows/checks.yml)

This repository is a practical starting point for running the same EKS platform
in separate AWS accounts.

Terraform creates the AWS infrastructure. ArgoCD installs and manages
Kubernetes add-ons and workloads after the cluster is available.

It is intended for engineers who want a small, readable EKS boilerplate with a
clear ownership boundary. It is not a managed platform product, a service
catalog, or a complete production operating model.

## What It Deploys

For each environment, Terraform creates:

- a VPC with public and private subnets;
- an EKS cluster with a managed node group;
- an ECR repository for the example application;
- one PostgreSQL RDS instance;
- Secrets Manager entries used by the example application;
- IAM and IRSA roles for cluster add-ons;
- CloudWatch alarms and a dashboard.

ArgoCD manages the Kubernetes side:

- AWS Load Balancer Controller;
- Cluster Autoscaler;
- External Secrets Operator;
- metrics-server;
- optional observability manifests already present in GitOps config;
- a small example application chart.

## Architecture

![EKS GitOps platform architecture](architecture.png)

Terraform and ArgoCD deliberately do different jobs:

- Terraform owns AWS infrastructure.
- ArgoCD owns Kubernetes add-ons and workloads.

Terraform outputs are copied into `gitops/environments/<env>/environment.json`
by `make configure-gitops-values`. Those GitOps files are committed and pushed,
then ArgoCD reconciles them from the remote repository.

## Repository Structure

```text
app/                     example Python web app and Dockerfile
bootstrap/               remote Terraform backend bootstrap scripts
deploy/argocd/           ArgoCD Helm install values
gitops/                  ArgoCD environment config and rendered Applications
terraform/environments/  per-environment tfvars examples
terraform/foundation/    optional GitHub OIDC role for ECR pushes
terraform/modules/       network, EKS, RDS and observability modules
terraform/stack/         shared Terraform root module
scripts/                 deployment, GitOps and verification helpers
tests/                   GitOps renderer tests
docs/                    detailed setup, configuration and troubleshooting
```

## Prerequisites

Install the tools checked by:

```bash
make prerequisites
```

That target checks for `aws`, `terraform`, `kubectl`, `helm`, `jq`, `python3`,
`openssl`, and usable AWS credentials.

You also need:

- an AWS account for the Terraform backend bootstrap;
- a deployment role in the target account that Terraform can assume;
- an EKS API CIDR allow list for your operator or VPN address;
- a Git remote that ArgoCD can read.

The deployment role is not created by the EKS stack. Create it before running
`make plan`.

## Quick Start

Start with `dev`. Keep the first deployment small: single NAT gateway, public
EKS API restricted to your IP, small node group, no database deletion
protection.

```bash
cp terraform/environments/dev.tfvars.example terraform/environments/dev.tfvars
```

Edit `terraform/environments/dev.tfvars`:

```hcl
project     = "my-platform"
environment = "dev"
aws_region  = "us-east-1"

aws_account_id = "111111111111"

deployment_role_arn = (
  "arn:aws:iam::111111111111:role/platform-terraform-deploy"
)

eks_public_access_cidrs = ["203.0.113.10/32"]
```

Then run:

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
git add gitops/
git commit -m "chore: configure dev GitOps values"
git push
make apply-argocd-apps ENV=dev
make verify ENV=dev
```

For private repositories, register repository credentials in ArgoCD before
applying the root Application:

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

The full deployment path is in [docs/deployment.md](docs/deployment.md).

## Optional Services

Observability can be enabled or disabled per environment in
`gitops/environments/<env>/environment.json`.

This repository currently provisions PostgreSQL through the `rds` module. It
does not currently include Redis, MySQL, Aurora, MSK, OpenSearch, DocumentDB, or
a service catalog layer.

## Validation

Run local static checks with:

```bash
make check
```

Run Terraform checks for one environment with:

```bash
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
```

Run live cluster checks after deployment with:

```bash
make verify ENV=dev
```

## Destroy

Delete Kubernetes-managed resources before destroying Terraform-managed AWS
infrastructure:

```bash
make destroy-gitops ENV=dev
make destroy ENV=dev
```

The destroy order matters because Kubernetes controllers can create AWS
resources such as load balancers.

## Limitations

This repository has not been fully end-to-end verified in this workspace after
the multi-account role change. Static checks pass, and the live plan now depends
on an assumable `deployment_role_arn`.

The project does not provide:

- a prebuilt cross-account role bootstrap;
- private EKS API connectivity such as VPN or Direct Connect;
- application CI secrets or deploy keys;
- backup restore runbooks;
- production incident response procedures;
- cost controls beyond the documented small dev defaults.

Configuration details are in [docs/configuration.md](docs/configuration.md).
Operational steps are in [docs/deployment.md](docs/deployment.md). Common
failures are in [docs/troubleshooting.md](docs/troubleshooting.md).
