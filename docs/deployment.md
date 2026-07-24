# Deployment

This is the complete path for one environment. The examples use `dev`.

## 1. Check Local Tools

```bash
make prerequisites
```

This checks the CLI tools and whether the current shell can call AWS STS.

## 2. Configure The Environment

```bash
cp terraform/environments/dev.tfvars.example terraform/environments/dev.tfvars
```

Edit `terraform/environments/dev.tfvars` and set real values:

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

The deployment role must already exist in the target AWS account.

## 3. Bootstrap Terraform State

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
```

This creates or reuses the S3 bucket and DynamoDB lock table for Terraform
state, then writes `bootstrap/backend-dev.hcl`. That generated file is ignored.

## 4. Plan And Apply AWS Infrastructure

```bash
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
make apply ENV=dev
```

Read the plan before applying. A new environment should show the VPC, EKS, RDS,
ECR, IAM and CloudWatch resources that match the stack configuration.

## 5. Configure kubectl

```bash
make kubeconfig ENV=dev
kubectl get nodes
```

The Makefile reads cluster name and region from Terraform outputs.

## 6. Fill The Application Secret

```bash
make configure-app-secret ENV=dev
```

Terraform creates the app secret empty. This command reads the RDS-managed
master secret and writes the fields consumed by the example application. It does
not print secret values.

## 7. Build And Point The Example App Image

```bash
make build-app ENV=dev TAG=0.1.0
make set-image-tag ENV=dev TAG=0.1.0
```

`set-image-tag` updates GitOps environment config and renders manifests.

## 8. Install ArgoCD

```bash
make deploy-argocd ENV=dev
```

ArgoCD is installed by Helm first. After that, ArgoCD manages add-ons and
workloads.

## 9. Configure GitOps Values

```bash
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
```

This writes Terraform outputs such as cluster name, region, VPC ID, role ARNs,
ECR URL and the secret path into `gitops/environments/dev/environment.json`.

Commit and push the GitOps changes:

```bash
git add gitops/
git commit -m "chore: configure dev GitOps values"
git push
```

ArgoCD reconciles from the remote Git repository.

## 10. Give ArgoCD Repository Access

For a private repository, create a deploy key outside this repo and register it:

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

For a public repository over HTTPS, repository credentials are not required.

## 11. Apply The Root Application

```bash
make apply-argocd-apps ENV=dev
```

This applies `gitops/environments/dev/root-app.yaml`. ArgoCD then reconciles the
child Applications for add-ons and workloads.

## 12. Verify

```bash
make verify ENV=dev
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
kubectl get externalsecrets -A
kubectl get ingress -A
```

## Destroy

Destroy Kubernetes-managed AWS resources before Terraform tears down the VPC:

```bash
make destroy-gitops ENV=dev
make destroy ENV=dev
```

Useful post-destroy checks:

```bash
aws elbv2 describe-load-balancers
aws rds describe-db-instances
aws eks list-clusters
```
