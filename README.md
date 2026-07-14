# eks-argocd-platform-boilerplate

[![checks](https://github.com/mstrugarevic1/eks-argocd-platform-boilerplate/actions/workflows/checks.yml/badge.svg?branch=main&event=push)](https://github.com/mstrugarevic1/eks-argocd-platform-boilerplate/actions/workflows/checks.yml)

This is a learning portfolio project and reusable multi-environment AWS EKS platform boilerplate using Terraform, ArgoCD App of Apps, Helm, and GitOps.

## Purpose

Use this repository as a starting point for an EKS platform where ownership is split clearly:

- Terraform creates and owns AWS infrastructure.
- ArgoCD owns Kubernetes add-ons and workloads.
- GitOps configuration supports `dev`, `staging`, and `production` from one component registry.

## Ownership

Terraform manages:

- VPC, public/private subnets, routes, NAT gateways, and internet gateway
- EKS cluster and managed node groups
- ECR
- RDS and the bootstrap AWS Secrets Manager secret
- IAM and IRSA roles
- CloudWatch alarms
- AWS-managed EKS add-ons, including EBS CSI

ArgoCD manages:

- AWS Load Balancer Controller
- External Secrets Operator and ExternalSecret manifests
- metrics-server
- Cluster Autoscaler
- observability stack
- workload Helm charts, including the optional `example-app`

## Structure

```text
bootstrap/                       # remote Terraform backend bootstrap
terraform/modules/               # reusable AWS modules
terraform/envs/dev/              # dev Terraform environment
terraform/envs/staging/          # staging Terraform environment
terraform/envs/production/       # production Terraform environment
terraform/foundation/            # optional GitHub OIDC/ECR push role
deploy/argocd/install/           # ArgoCD Helm values
deploy/observability/            # shared observability values and dashboards
deploy/storage/                  # shared storage manifests
gitops/base/components.json      # App of Apps component registry
gitops/apps/example-app/chart/   # optional example app chart
gitops/environments/<env>/       # per-env GitOps config and rendered apps
scripts/gitops.py                # local render/validation helper
```

## Prerequisites

- AWS CLI authenticated to the target account
- Terraform
- kubectl
- Helm
- Python 3
- An existing Git remote readable by ArgoCD

## Configure An Environment

Start with one environment. The same flow applies to `dev`, `staging`, and `production`.

```bash
cp terraform/envs/dev/terraform.tfvars.example terraform/envs/dev/terraform.tfvars
```

Set the project, region, network, and EKS API access CIDRs:

```hcl
project     = "my-platform"
environment = "dev"
aws_region  = "us-east-1"

azs                  = ["us-east-1a", "us-east-1b"]
vpc_cidr             = "10.10.0.0/16"
public_subnet_cidrs  = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs = ["10.10.11.0/24", "10.10.12.0/24"]
nat_gateway_strategy = "single"

eks_public_access_cidrs = ["203.0.113.10/32"]
```

Use `nat_gateway_strategy = "single"` for lower-cost environments and `nat_gateway_strategy = "per_az"` when each private subnet should route through a NAT gateway in the same AZ.

GitOps environment values live in:

```text
gitops/environments/dev/environment.json
gitops/environments/staging/environment.json
gitops/environments/production/environment.json
```

Before the cluster exists, these files contain placeholders such as `AWS_ACCOUNT_ID`, `VPC_ID`, and IRSA role ARNs. After Terraform creates the infrastructure, fill them with:

```bash
make configure-gitops-values ENV=dev
```

## Bootstrap And Deploy

Create the Terraform backend:

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
```

Initialize and review Terraform:

```bash
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
```

Apply only after the plan is reviewed:

```bash
make apply ENV=dev
```

Install ArgoCD, render GitOps values from Terraform outputs, validate the rendered manifests, and register the root app:

```bash
make deploy-argocd ENV=dev
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
make apply-argocd-apps ENV=dev
```

`apply-argocd-apps` applies only the root Application:

```text
gitops/environments/dev/root-app.yaml
```

ArgoCD then reconciles the child Applications from:

```text
gitops/environments/dev/apps/
```

## Validate Without Deploying

Run the safe local checks:

```bash
make check
```

This formats/checks Terraform files, parses JSON, renders all GitOps environments, and lints/renders the example Helm chart. It does not run `terraform init`, call AWS, apply Kubernetes manifests, or sync ArgoCD.

After replacing GitOps placeholders, validate one environment:

```bash
make gitops-validate ENV=dev
```

## Add An Environment

Create Terraform and GitOps environment directories:

```bash
cp -R terraform/envs/dev terraform/envs/sandbox
cp -R gitops/environments/dev gitops/environments/sandbox
```

Register the environment in one place:

```json
{
  "environments": ["dev", "staging", "production", "sandbox"]
}
```

Update:

```text
terraform/envs/sandbox/terraform.tfvars.example
gitops/environments/sandbox/environment.json
```

Render and validate:

```bash
make gitops-render ENV=sandbox
make gitops-validate ENV=sandbox
```

## Add An Application

Add a chart or manifest directory:

```text
gitops/apps/my-app/chart/
```

Register it in `gitops/base/components.json`:

```json
{
  "name": "my-app",
  "enabledKey": "apps.myApp",
  "wave": 20,
  "namespaceKey": "app",
  "createNamespace": true,
  "valueFilesFromEnv": ["myApp.valuesFile"],
  "source": { "path": "gitops/apps/my-app/chart" }
}
```

Enable it per environment:

```json
{
  "apps": {
    "exampleApp": true,
    "myApp": true
  },
  "myApp": {
    "valuesFile": "values-dev.yaml"
  }
}
```

Put environment-specific Helm values in the app chart directory:

```yaml
image:
  repository: "AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/my-app-dev"
  tag: "latest"

ingress:
  host: "my-app.dev.example.com"
```

Render the environment:

```bash
make gitops-render ENV=dev
```

## Enable Or Disable An Add-on

Edit `gitops/environments/<env>/environment.json`:

```json
{
  "addons": {
    "metricsServer": true,
    "awsLoadBalancerController": true,
    "clusterAutoscaler": true,
    "externalSecrets": true,
    "observability": false
  }
}
```

Render and validate after the change:

```bash
make gitops-render ENV=dev
make gitops-validate ENV=dev
```

## Secrets

Do not commit plaintext secrets, `.env` files, kubeconfigs, private keys, or real `terraform.tfvars` files.

The intended runtime path is:

- Terraform creates the AWS Secrets Manager secret and IRSA roles.
- External Secrets Operator reads from AWS Secrets Manager through IRSA.
- ArgoCD applies `ExternalSecret` manifests.
- Kubernetes workloads consume generated Kubernetes Secrets.

Use placeholders in examples and documentation.

## Destroy Safely

Remove ArgoCD-managed resources first so controller-created cloud resources, such as ALBs, are deleted before Terraform destroys the VPC:

```bash
kubectl -n argocd delete application dev-root
```

Wait until controller-created AWS resources are gone, then destroy Terraform-managed infrastructure:

```bash
make destroy ENV=dev
```

Delete the Terraform backend only after infrastructure is destroyed and state is no longer needed:

```bash
./bootstrap/destroy-bootstrap.sh my-platform dev us-east-1 DELETE_TERRAFORM_BACKEND
```

## Limitations

- ArgoCD repository credentials are intentionally not managed here.
- Production keeps `automated.prune` disabled by default.
- The example app demonstrates the GitOps workflow; replace it with a real workload.
- `make check` is static validation only. It does not prove that AWS quotas, IAM permissions, chart versions, or live cluster reconciliation are correct.
- Review cost and availability choices before production use, especially NAT gateway count, node sizing, RDS sizing, retention, and public EKS API access.
