# Deployment guide

Deploying one environment end to end. `dev` is used throughout; the same
sequence applies to `staging` and `production`.

Nothing here has a rollback button. Read every `terraform plan` before applying.

## 0. Prerequisites

```bash
make prerequisites
```

Checks for `aws`, `terraform`, `kubectl`, `helm`, `jq`, `python3`, `openssl` and
working AWS credentials. It fails on the first missing one instead of half way
through the deploy.

Also needed: a Git remote that ArgoCD can read. See [gitops.md](gitops.md).

## 1. Configure the environment

```bash
cp terraform/envs/dev/terraform.tfvars.example terraform/envs/dev/terraform.tfvars
```

`terraform.tfvars` is gitignored. At minimum set:

```hcl
project     = "my-platform"
environment = "dev"
aws_region  = "us-east-1"

# Replace with the address that will reach the EKS API. 203.0.113.0/24 is the
# RFC 5737 documentation range and matches nothing real.
eks_public_access_cidrs = ["203.0.113.10/32"]
```

`project` must match `PROJECT` in the Makefile. AWS resource names, the ECR
repository and the Secrets Manager path are all derived from it.

## 2. Create the Terraform backend

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
```

Creates the state S3 bucket and the DynamoDB lock table, and writes
`bootstrap/backend-dev.hcl`. Safe to re-run.

## 3. Apply Terraform

```bash
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
make apply ENV=dev
```

Roughly 15-20 minutes, most of it the EKS control plane and the RDS instance.

## 4. Get cluster access

```bash
make kubeconfig ENV=dev
kubectl get nodes
```

The region comes from the Terraform output, not from `AWS_REGION`, so the
kubeconfig always matches the environment that was applied.

## 5. Fill the application secret

```bash
make configure-app-secret ENV=dev
```

Terraform creates the Secrets Manager entry empty on purpose. This reads the
RDS-managed master secret and the RDS endpoint and writes the keys the
application expects. Idempotent, and no password is printed. See
[secrets.md](secrets.md).

## 6. Build and push the application image

```bash
make build-app ENV=dev TAG=0.1.0
make set-image-tag ENV=dev TAG=0.1.0
```

ECR repositories use immutable tags, so every build needs a new tag.
`set-image-tag` writes the tag into `environment.json` and re-renders.

CI can do the same through the `Build app image` workflow.

## 7. Install ArgoCD

```bash
make deploy-argocd ENV=dev
```

Installs the pinned `argo-cd` chart version into the `argocd` namespace.
ArgoCD itself is not managed by GitOps: something has to run first.

## 8. Render the GitOps configuration

```bash
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
```

`configure-gitops-values` reads the Terraform outputs and replaces the
placeholders in `gitops/environments/dev/environment.json`: account ID, VPC ID,
cluster name, region, the four IRSA role ARNs, the ECR repository URL and the
Secrets Manager path. Then it re-renders the ArgoCD manifests.

`gitops-validate` fails if any placeholder is left, if a rendered Application is
missing or misnamed, or if an image tag is `latest`.

## 9. Commit and push

```bash
git add gitops/
git commit -m "chore: configure dev GitOps values"
git push
```

**This step is not optional.** ArgoCD reconciles the remote Git repository, not
the working copy. Anything uncommitted is invisible to it.

Nothing written by `configure-gitops-values` is secret: it is account IDs, ARNs
and resource names. The database password never leaves Secrets Manager.

## 10. Give ArgoCD access to the repository

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

Skip for a public repository over HTTPS. See [gitops.md](gitops.md) for how to
create the deploy key.

## 11. Register the root Application

```bash
make apply-argocd-apps ENV=dev
```

Applies only `gitops/environments/dev/root-app.yaml`. ArgoCD discovers the child
Applications in `gitops/environments/dev/apps/` and applies them in sync-wave
order.

## 12. Verify

```bash
make verify ENV=dev
```

See [validation.md](validation.md) for what it checks and for the raw
`kubectl`/`argocd` smoke test.

## Full sequence

```bash
make prerequisites
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
make init ENV=dev
make validate ENV=dev
make plan ENV=dev
make apply ENV=dev
make kubeconfig ENV=dev
make configure-app-secret ENV=dev
make build-app ENV=dev TAG=0.1.0
make set-image-tag ENV=dev TAG=0.1.0
make deploy-argocd ENV=dev
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
git add gitops/ && git commit -m "chore: configure dev GitOps values" && git push
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
make apply-argocd-apps ENV=dev
make verify ENV=dev
```

## Adding an environment

```bash
cp -R terraform/envs/dev terraform/envs/sandbox
cp -R gitops/environments/dev gitops/environments/sandbox
```

Register it in `gitops/environments/environments.json`:

```json
{ "environments": ["dev", "staging", "production", "sandbox"] }
```

Then update `terraform/envs/sandbox/terraform.tfvars.example` (a non-overlapping
`vpc_cidr`) and `gitops/environments/sandbox/environment.json` (`name`,
`aws.clusterName`, `exampleApp.secretManagerPath`, `exampleApp.valuesFile`), add
`gitops/apps/example-app/chart/values-sandbox.yaml`, and render:

```bash
make gitops-render ENV=sandbox
```

Validation rejects an environment that still references another one, so the
copied values must all be updated.

## Cleanup

See [cleanup.md](cleanup.md). Do not run `terraform destroy` first.
