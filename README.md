# eks-argocd-platform-boilerplate

Reusable multi-environment AWS EKS platform boilerplate using Terraform, ArgoCD App of Apps, Helm, and GitOps.

## Purpose

This repository is a starting point for an AWS EKS platform:

- Terraform creates and owns AWS infrastructure.
- ArgoCD owns Kubernetes add-ons and workloads.
- GitOps configuration supports multiple environments from one reusable component registry.

## Ownership

Terraform manages:

- VPC, subnets, routing, NAT/IGW
- EKS cluster and managed node groups
- ECR
- RDS and Secrets Manager bootstrap secret
- IAM and IRSA roles
- CloudWatch alarms
- AWS-managed EKS add-ons, such as EBS CSI

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
terraform/envs/dev/              # example Terraform environment
terraform/foundation/            # optional GitHub OIDC/ECR push role
deploy/argocd/install/           # ArgoCD Helm values
deploy/observability/            # shared observability values and dashboards
deploy/storage/                  # shared storage manifests
gitops/base/components.json      # reusable App of Apps component registry
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

## Environment Variables

Terraform variables are not committed. Create an environment variable file from the example:

```bash
cp terraform/envs/dev/terraform.tfvars.example terraform/envs/dev/terraform.tfvars
```

Set at least:

```hcl
project     = "my-platform"
environment = "dev"
aws_region  = "us-east-1"

eks_public_access_cidrs = ["203.0.113.10/32"]
```

GitOps environment config lives here:

```text
gitops/environments/dev/environment.json
gitops/environments/staging/environment.json
gitops/environments/production/environment.json
```

The important fields are:

```json
{
  "repoURL": "git@github.com:mstrugarevic1/eks-argocd-platform-boilerplate.git",
  "targetRevision": "main",
  "aws": {
    "accountId": "AWS_ACCOUNT_ID",
    "region": "us-east-1",
    "clusterName": "my-platform-dev",
    "vpcId": "VPC_ID",
    "roles": {
      "awsLoadBalancerController": "arn:aws:iam::AWS_ACCOUNT_ID:role/my-platform-dev-alb-controller",
      "clusterAutoscaler": "arn:aws:iam::AWS_ACCOUNT_ID:role/my-platform-dev-cluster-autoscaler",
      "externalSecrets": "arn:aws:iam::AWS_ACCOUNT_ID:role/my-platform-dev-external-secrets",
      "grafanaCloudWatch": "arn:aws:iam::AWS_ACCOUNT_ID:role/my-platform-dev-grafana-cloudwatch"
    }
  }
}
```

`make configure-gitops-values ENV=<env>` can fill the cluster, VPC, and IRSA values from Terraform outputs after infrastructure exists.

## Bootstrap

Create the Terraform backend:

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
```

Run Terraform:

```bash
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
make apply ENV=dev
```

Install ArgoCD and register the environment root app:

```bash
make deploy-argocd ENV=dev
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
make apply-argocd-apps ENV=dev
```

`apply-argocd-apps` only applies:

```text
gitops/environments/dev/root-app.yaml
```

ArgoCD syncs the child Applications from:

```text
gitops/environments/dev/apps/
```

## Validate Without Deploying

Local checks:

```bash
python3 -m py_compile scripts/gitops.py
make gitops-render ENV=dev
helm lint gitops/apps/example-app/chart
helm template example-app gitops/apps/example-app/chart \
  --values gitops/apps/example-app/chart/values-dev.yaml >/tmp/example-app.yaml
```

After replacing `AWS_ACCOUNT_ID`, `VPC_ID`, and role ARN placeholders, run:

```bash
make gitops-validate ENV=dev
```

These commands do not create AWS or Kubernetes resources.

## Add An Environment

Create Terraform and GitOps environment files:

```bash
cp -R terraform/envs/dev terraform/envs/staging
cp -R gitops/environments/dev gitops/environments/staging
```

Register it:

```json
{
  "environments": ["dev", "staging", "production"]
}
```

Update:

```text
terraform/envs/staging/terraform.tfvars.example
gitops/environments/staging/environment.json
```

Render and validate:

```bash
make gitops-render ENV=staging
make gitops-validate ENV=staging
```

## Add An Application

Add a chart or manifest directory:

```text
gitops/apps/my-app/chart/
```

Add a component entry:

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

Add the environment config:

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

Add environment-specific Helm values:

```yaml
image:
  repository: "AWS_ACCOUNT_ID.dkr.ecr.AWS_REGION.amazonaws.com/my-app-dev"
  tag: "latest"

ingress:
  host: "my-app.dev.example.com"
```

Render:

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

Render and validate:

```bash
make gitops-render ENV=dev
make gitops-validate ENV=dev
```

## Destroy Safely

Delete ArgoCD-managed workloads first so cloud resources created by controllers, such as ALBs, are removed before Terraform destroys the VPC:

```bash
kubectl -n argocd delete application dev-root
```

Wait for controller-created AWS resources to disappear, then destroy Terraform-managed infrastructure:

```bash
make destroy ENV=dev
```

Delete the Terraform backend only after infrastructure is destroyed and state is no longer needed:

```bash
./bootstrap/destroy-bootstrap.sh my-platform dev us-east-1 DELETE_TERRAFORM_BACKEND
```

## Limitations

- Helm chart versions should be pinned before long-lived production use.
- Production config keeps `automated.prune` disabled by default.
- The example app is only a workflow example; replace it with your application.
- ArgoCD repo credentials are intentionally not managed here.
- No CI workflow is included; add one for your organization’s branch and approval model.
- `terraform.tfvars`, state files, private keys, kubeconfigs, and real secrets must stay out of Git.
