# EKS GitOps Platform: Configuration

Environment-specific values live in `terraform/environments/*.tfvars`.
The shared Terraform root is `terraform/stack`.

Create a real, ignored tfvars file from an example:

```bash
cp terraform/environments/dev.tfvars.example terraform/environments/dev.tfvars
```

## Environment Identity

These values define naming, region and the target AWS account:

```hcl
project     = "my-platform"
environment = "dev"
aws_region  = "us-east-1"

aws_account_id = "111111111111"

deployment_role_arn = (
  "arn:aws:iam::111111111111:role/platform-terraform-deploy"
)
```

`project` and `environment` form names such as `my-platform-dev` and
`my-platform/dev/example-app`.

Terraform assumes `deployment_role_arn` before creating resources. The role must
already exist and trust the credentials used to run Terraform. The stack checks
that the assumed identity resolves to `aws_account_id`.

## Network

Configure CIDRs and Availability Zones explicitly:

```hcl
azs = [
  "us-east-1a",
  "us-east-1b",
]

vpc_cidr = "10.10.0.0/16"

public_subnet_cidrs = [
  "10.10.1.0/24",
  "10.10.2.0/24",
]

private_subnet_cidrs = [
  "10.10.11.0/24",
  "10.10.12.0/24",
]
```

`nat_gateway_strategy = "single"` is the lower-cost dev path. Use `per_az` when
you want one NAT gateway per Availability Zone.

## EKS

The EKS API is public by default and restricted by CIDR:

```hcl
eks_endpoint_public_access = true
eks_public_access_cidrs    = ["203.0.113.10/32"]
```

Replace the documentation CIDR with your operator or VPN address. The example
CIDR does not match a real client address.

Node group sizing is also explicit:

```hcl
kubernetes_version  = "1.35"
node_instance_types = ["t3.medium"]
node_desired_size   = 2
node_min_size       = 1
node_max_size       = 4
```

Keep the Cluster Autoscaler image in GitOps config aligned with the Kubernetes
minor version.

## Database

The current stack provisions one PostgreSQL RDS instance:

```hcl
rds_instance_class        = "db.t4g.micro"
rds_allocated_storage     = 20
rds_backup_retention_days = 3
rds_username              = "app"
rds_db_name               = "app"
rds_multi_az              = false
rds_deletion_protection   = false
rds_skip_final_snapshot   = true
```

The RDS master password is managed by AWS and stored in Secrets Manager. The app
secret is filled later by:

```bash
make configure-app-secret ENV=dev
```

## Application Image And Secret Safety

For disposable dev environments:

```hcl
ecr_force_delete         = true
app_secret_recovery_days = 0
```

For environments that hold data, use safer values:

```hcl
ecr_force_delete         = false
app_secret_recovery_days = 30
rds_deletion_protection  = true
rds_skip_final_snapshot  = false
```

## GitOps Add-ons

Add-ons are enabled per environment in
`gitops/environments/<env>/environment.json`.

The example app workload type is selected in
`gitops/apps/example-app/chart/values-<env>.yaml`:

```yaml
workload:
  mode: stateless
```

Supported values:

- `stateless`: renders a Kubernetes `Deployment`.
- `stateful`: renders a Kubernetes `StatefulSet` with one `gp3` persistent
  volume claim per pod.

Keep `stateless` for the first deployment. Use `stateful` when you specifically
want to test persistent workload behavior and storage cleanup.

After Terraform apply, run:

```bash
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
```

Commit and push the changed GitOps files. ArgoCD reads the remote repository,
not your working tree.
