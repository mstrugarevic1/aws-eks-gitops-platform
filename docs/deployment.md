# EKS GitOps Platform: Deployment Guide

This is the single deployment guide for one environment. The examples use
`dev`; repeat the same flow with `ENV=staging` or `ENV=production` after
creating the matching `terraform/environments/<env>.tfvars` file.

## Table Of Contents

1. [Prerequisites](#1-prerequisites)
2. [Credentials And Permissions](#2-credentials-and-permissions)
3. [Networking Requirements](#3-networking-requirements)
4. [Environment-Specific Values](#4-environment-specific-values)
5. [Bootstrap Terraform State](#5-bootstrap-terraform-state)
6. [Plan And Apply AWS Infrastructure](#6-plan-and-apply-aws-infrastructure)
7. [Configure kubectl](#7-configure-kubectl)
8. [Fill The Application Secret](#8-fill-the-application-secret)
9. [Build And Point The Example App Image](#9-build-and-point-the-example-app-image)
10. [Install ArgoCD](#10-install-argocd)
11. [Configure GitOps Values](#11-configure-gitops-values)
12. [Give ArgoCD Repository Access](#12-give-argocd-repository-access)
13. [Apply The Root Application](#13-apply-the-root-application)
14. [Expected Deployment Flow](#14-expected-deployment-flow)
15. [Verify The Deployment](#15-verify-the-deployment)
16. [Destroy](#16-destroy)
17. [Deployment Verification Checklist](#17-deployment-verification-checklist)

## 1. Prerequisites

Run the local prerequisite check first:

```bash
make prerequisites
```

This checks for `aws`, `terraform`, `kubectl`, `helm`, `jq`, `python3`,
`openssl`, and working AWS STS credentials.

Required before continuing:

- AWS credentials in the shell that can call `aws sts get-caller-identity`.
- Terraform CLI and the command-line tools checked by `make prerequisites`.
- A target AWS account where the deployment role already exists.
- ACM certificate ARNs if AWS Client VPN is enabled.

Optional:

- Docker, if building the example application image locally with
  `make build-app`.
- A GitHub Actions environment and ECR push role, if using
  `.github/workflows/build-app.yml` instead of local image builds.

If `make prerequisites` fails on AWS credentials, fix the local AWS profile or
session before running Terraform.

## 2. Credentials And Permissions

Terraform uses two identities:

- The current shell identity bootstraps the Terraform backend and starts the
  run.
- Terraform then assumes `deployment_role_arn` from the environment tfvars file
  before creating the stack.

Required values:

```hcl
aws_account_id = "111111111111"

deployment_role_arn = (
  "arn:aws:iam::111111111111:role/platform-terraform-deploy"
)
```

The stack checks that the assumed identity resolves to `aws_account_id`.

If `make plan` reports an unexpected AWS account, check the active identity:

```bash
aws sts get-caller-identity
```

If Terraform cannot assume the deployment role, check the role trust policy:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::<account-id>:role/platform-terraform-deploy \
  --role-session-name terraform-check \
  --query AssumedRoleUser.Arn \
  --output text
```

ArgoCD repository access is configured later in
[Give ArgoCD Repository Access](#12-give-argocd-repository-access).

## 3. Networking Requirements

Choose non-overlapping CIDRs for environments that may later be connected
through peering, Transit Gateway, VPN, Direct Connect, shared services, or
centralized operations access.

Required subnet layout:

- Public subnets: internet-facing load balancers and NAT gateways.
- Private subnets: EKS nodes and Client VPN target network associations.
- Database subnets: isolated RDS subnet group with no default route.

Use a CIDR calculator when choosing ranges:

```bash
ipcalc 10.10.0.0/16
```

The example environment keeps the EKS API private:

```hcl
eks_endpoint_public_access = false
eks_public_access_cidrs    = []
```

With private EKS access, operators must connect through AWS Client VPN before
using `kubectl`.

Optional public EKS access:

```hcl
eks_endpoint_public_access = true
eks_public_access_cidrs    = ["203.0.113.10/32"]
```

Only use public access with real operator or VPN egress CIDRs.

## 4. Environment-Specific Values

Create the ignored tfvars file for the environment:

```bash
cp terraform/environments/dev.tfvars.example terraform/environments/dev.tfvars
```

Edit `terraform/environments/dev.tfvars`. This is the authoritative example for
the required environment values:

```hcl
project     = "my-platform"
environment = "dev"

aws_region = "us-east-1"
azs        = ["us-east-1a", "us-east-1b"]

aws_account_id = "111111111111"

deployment_role_arn = (
  "arn:aws:iam::111111111111:role/platform-terraform-deploy"
)

vpc_cidr              = "10.10.0.0/16"
public_subnet_cidrs   = ["10.10.1.0/24", "10.10.2.0/24"]
private_subnet_cidrs  = ["10.10.11.0/24", "10.10.12.0/24"]
database_subnet_cidrs = ["10.10.21.0/24", "10.10.22.0/24"]

nat_gateway_strategy = "single"

eks_endpoint_public_access = false
eks_public_access_cidrs    = []

client_vpn = {
  enabled                    = true
  client_cidr_block          = "10.255.0.0/22"
  server_certificate_arn     = "arn:aws:acm:us-east-1:111111111111:certificate/server-certificate-id"
  root_certificate_chain_arn = "arn:aws:acm:us-east-1:111111111111:certificate/client-root-certificate-id"
  split_tunnel               = true
  dns_servers                = []
}

kubernetes_version  = "1.35"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4

rds_instance_class        = "db.t4g.micro"
rds_allocated_storage     = 20
rds_backup_retention_days = 3
rds_username              = "app"
rds_db_name               = "app"
rds_multi_az              = false
rds_deletion_protection   = false
rds_skip_final_snapshot   = true

ecr_force_delete         = true
app_secret_recovery_days = 0

alarm_email = ""
```

`project` and `environment` form names such as `my-platform-dev` and
`my-platform/dev/example-app`. `project` must match `PROJECT` when running
`make bootstrap`.

For environments that hold data, use safer lifecycle values:

```hcl
ecr_force_delete         = false
app_secret_recovery_days = 30
rds_deletion_protection  = true
rds_skip_final_snapshot  = false
```

Optional Client VPN connection logging requires an existing CloudWatch log group
and stream:

```hcl
client_vpn_connection_logging = {
  enabled               = true
  cloudwatch_log_group  = "/aws/client-vpn/my-platform-production"
  cloudwatch_log_stream = "connections"
}
```

Keep the Cluster Autoscaler image in `gitops/base/components.json` aligned with
the Kubernetes minor version.

### Client VPN Certificates

Terraform references ACM certificate ARNs; it does not create or store private
keys. If you do not already have Client VPN certificates, generate them outside
this repository and import them into ACM in the same Region as the VPN endpoint:

```bash
git clone https://github.com/OpenVPN/easy-rsa.git /tmp/easy-rsa
cd /tmp/easy-rsa/easyrsa3
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa --san=DNS:server build-server-full server nopass
./easyrsa build-client-full client1.domain.tld nopass

mkdir -p /tmp/client-vpn-pki
cp pki/ca.crt /tmp/client-vpn-pki/
cp pki/issued/server.crt /tmp/client-vpn-pki/
cp pki/private/server.key /tmp/client-vpn-pki/
cp pki/issued/client1.domain.tld.crt /tmp/client-vpn-pki/
cp pki/private/client1.domain.tld.key /tmp/client-vpn-pki/
cd /tmp/client-vpn-pki

aws acm import-certificate \
  --certificate fileb://server.crt \
  --private-key fileb://server.key \
  --certificate-chain fileb://ca.crt
```

Use the returned ACM certificate ARN for both `server_certificate_arn` and
`root_certificate_chain_arn` when the server and client certificates are signed
by the same CA. Keep client certificate and private key files outside git.

## 5. Bootstrap Terraform State

Run once per environment:

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
```

This creates or reuses:

- S3 bucket: Terraform state
- DynamoDB table: Terraform state locking
- `bootstrap/backend-dev.hcl`: ignored backend config read by `make init`

If `make init ENV=dev` later cannot read `bootstrap/backend-dev.hcl`, rerun the
bootstrap command above.

## 6. Plan And Apply AWS Infrastructure

Initialize, validate, review, and apply:

```bash
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
make apply ENV=dev
```

Read the plan before applying. A new environment should show VPC, subnets,
routing, EKS, managed node groups, Client VPN when enabled, RDS, ECR, IAM,
IRSA roles, Secrets Manager entries, and CloudWatch resources.

If Terraform fails because the backend is missing, return to
[Bootstrap Terraform State](#5-bootstrap-terraform-state).

## 7. Configure kubectl

If the EKS endpoint is private, export and import the Client VPN profile after
Terraform creates the endpoint:

```bash
aws ec2 export-client-vpn-client-configuration \
  --client-vpn-endpoint-id "$(cd terraform/stack && terraform output -raw client_vpn_endpoint_id)" \
  --output text > /tmp/client-vpn-dev.ovpn

cat >> /tmp/client-vpn-dev.ovpn <<'EOF'
cert /tmp/client-vpn-pki/client1.domain.tld.crt
key /tmp/client-vpn-pki/client1.domain.tld.key
EOF
```

Import `/tmp/client-vpn-dev.ovpn` into AWS VPN Client, then connect the VPN.
The exported VPN profile does not include a client private key, so keep the
client certificate and key files outside this repository.

Write kubeconfig for the cluster:

```bash
make kubeconfig ENV=dev
kubectl get nodes
```

The Makefile reads cluster name and region from Terraform outputs.

If `kubectl` times out, check the cluster endpoint mode and Client VPN endpoint:

```bash
aws eks describe-cluster --name my-platform-dev \
  --query 'cluster.resourcesVpcConfig'
aws ec2 describe-client-vpn-endpoints \
  --query 'ClientVpnEndpoints[].ClientVpnEndpointId'
aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id cvpn-endpoint-id
```

Confirm the VPN is connected, `client_vpn.enabled = true`, the certificate ARNs
are real, and the endpoint has target network associations.

## 8. Fill The Application Secret

Terraform creates the application secret empty so database credentials do not
land in Terraform state. Fill it from the RDS-managed master secret:

```bash
make configure-app-secret ENV=dev
```

The script writes `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`,
`DATABASE_URL`, and `APP_SECRET_KEY` to the existing Secrets Manager secret. It
does not print secret values.

## 9. Build And Point The Example App Image

Build and push the example app image:

```bash
make build-app ENV=dev TAG=0.1.0
```

Then point the environment at that immutable ECR tag:

```bash
make set-image-tag ENV=dev TAG=0.1.0
```

`set-image-tag` updates GitOps environment config and renders manifests.

Optional CI path: `.github/workflows/build-app.yml` can build and push the image
manually through GitHub Actions. It requires GitHub variables for
`AWS_ECR_PUSH_ROLE_ARN`, `AWS_REGION`, and `ECR_REPOSITORY_NAME`.

## 10. Install ArgoCD

Install ArgoCD with Helm:

```bash
make deploy-argocd ENV=dev
```

ArgoCD is installed first by Helm. After that, ArgoCD manages add-ons and
workloads from the GitOps files.

## 11. Configure GitOps Values

Write Terraform outputs into GitOps environment config and validate the render:

```bash
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
```

This updates `gitops/environments/dev/environment.json` with values such as
cluster name, region, VPC ID, role ARNs, ECR URL, and the application secret
path.

Production GitOps tracks the `production` branch by default. Create that branch
or change `targetRevision` in `gitops/environments/production/environment.json`
to the release tag or commit SHA you want ArgoCD to reconcile.

Commit and push the GitOps changes:

```bash
git add gitops/
git commit -m "Configure dev GitOps values"
git push
```

ArgoCD reconciles from the remote Git repository, not the local working tree.

## 12. Give ArgoCD Repository Access

Required for private repositories. Create a deploy key outside this repository
and register it:

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

The private key is read by `kubectl` and is not written to the repository.

For a public HTTPS repository, repository credentials are not required. Make
sure `repoURL` in `gitops/environments/dev/environment.json` uses the public
HTTPS URL.

If ArgoCD Applications stay `Unknown`, check repository credentials:

```bash
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository
kubectl -n argocd logs deploy/argocd-repo-server --tail=50
```

## 13. Apply The Root Application

Apply the root ArgoCD Application:

```bash
make apply-argocd-apps ENV=dev
```

This applies `gitops/environments/dev/root-app.yaml`. ArgoCD then reconciles the
child Applications for add-ons and workloads.

If the application pod is missing database environment variables, check the
ExternalSecret:

```bash
kubectl get externalsecrets -A
kubectl -n external-secrets logs deploy/external-secrets --tail=50
kubectl -n example-app describe externalsecret example-app
```

If it is not ready, rerun:

```bash
make configure-app-secret ENV=dev
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
git add gitops/
git commit -m "Refresh dev GitOps values"
git push
```

Then let ArgoCD sync again.

## 14. Expected Deployment Flow

The expected flow is:

1. Local tooling and AWS identity pass prerequisite checks.
2. Environment tfvars exists and contains real account, role, network, EKS,
   Client VPN, node, RDS, ECR, and secret lifecycle values.
3. Terraform backend exists and `make init` can read `bootstrap/backend-dev.hcl`.
4. Terraform applies the AWS infrastructure.
5. Operators connect to the cluster through Client VPN when the EKS endpoint is
   private.
6. The application secret is populated from RDS outputs and the RDS-managed
   master secret.
7. The app image is pushed to ECR and the GitOps image tag is updated.
8. ArgoCD is installed, reads the remote Git repository, and reconciles child
   Applications.
9. `make verify ENV=dev` passes.

## 15. Verify The Deployment

Run the read-only verification script:

```bash
make verify ENV=dev
```

Useful direct checks:

```bash
kubectl get nodes
kubectl get pods -A
kubectl get applications -n argocd
kubectl get externalsecrets -A
kubectl get ingress -A
```

`make verify` checks AWS identity, Terraform region output, kubectl context,
node readiness, ArgoCD Applications, External Secrets, application Deployment,
Service, optional Ingress, and observability pods/PVCs.

## 16. Destroy

Destroy Kubernetes-managed AWS resources before Terraform tears down the VPC:

```bash
make destroy-gitops ENV=dev
kubectl get ingress -A
make destroy ENV=dev
```

Wait until ingresses and load balancers are gone before destroying Terraform
resources.

If RDS deletion protection blocks destroy, set these values, apply them, then
destroy:

```hcl
rds_deletion_protection = false
rds_skip_final_snapshot = true
```

```bash
make plan ENV=dev
make apply ENV=dev
make destroy ENV=dev
```

Use a final snapshot for environments that hold data.

Useful post-destroy checks:

```bash
aws elbv2 describe-load-balancers
aws rds describe-db-instances
aws eks list-clusters
```

Destroy the Terraform backend only after the environment state is no longer
needed:

```bash
./bootstrap/destroy-bootstrap.sh my-platform dev us-east-1 DELETE_TERRAFORM_BACKEND
```

## 17. Deployment Verification Checklist

- [ ] `make prerequisites` passes.
- [ ] `terraform/environments/dev.tfvars` exists and contains real values.
- [ ] `make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform` wrote
      `bootstrap/backend-dev.hcl`.
- [ ] `make init ENV=dev`, `make validate ENV=dev`, `make plan ENV=dev`, and
      `make apply ENV=dev` completed.
- [ ] AWS Client VPN is connected when the EKS endpoint is private.
- [ ] `make kubeconfig ENV=dev` completed and `kubectl get nodes` returns Ready
      nodes.
- [ ] `make configure-app-secret ENV=dev` completed without printing secrets.
- [ ] `make build-app ENV=dev TAG=0.1.0` pushed an image, or the GitHub Actions
      build workflow pushed one.
- [ ] `make set-image-tag ENV=dev TAG=0.1.0` updated rendered GitOps files.
- [ ] `make deploy-argocd ENV=dev` installed ArgoCD.
- [ ] `make configure-gitops-values ENV=dev` and
      `make gitops-validate ENV=dev` completed.
- [ ] GitOps changes under `gitops/` were committed and pushed.
- [ ] Private repository access was registered with
      `make configure-argocd-repository ENV=dev SSH_KEY_FILE=...`, or the repo
      is public over HTTPS.
- [ ] `make apply-argocd-apps ENV=dev` applied the root Application.
- [ ] `make verify ENV=dev` passes.
