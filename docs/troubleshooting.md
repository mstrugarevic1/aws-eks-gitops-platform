# EKS GitOps Platform: Troubleshooting

## Wrong AWS Account

**Symptom.** `make plan` fails with:

```text
Terraform authenticated against an unexpected AWS account.
```

**Check.**

```bash
aws sts get-caller-identity
```

**Fix.** Correct `aws_account_id`, `deployment_role_arn`, or the AWS profile
used by the shell.

## Deployment Role Cannot Be Assumed

**Symptom.** Terraform fails with `Cannot assume IAM Role`.

**Check.**

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::<account-id>:role/platform-terraform-deploy \
  --role-session-name terraform-check \
  --query AssumedRoleUser.Arn \
  --output text
```

**Fix.** Create the role in the target account or update its trust policy to
allow the current AWS identity to assume it.

## Backend Config Does Not Exist

**Symptom.** `make init ENV=dev` cannot read
`bootstrap/backend-dev.hcl`.

**Fix.**

```bash
make bootstrap ENV=dev AWS_REGION=us-east-1 PROJECT=my-platform
make init ENV=dev
```

## EKS API Access Is Blocked

**Symptom.** `kubectl` times out after `make kubeconfig`.

**Check.**

```bash
aws eks describe-cluster --name my-platform-dev \
  --query 'cluster.resourcesVpcConfig'
aws ec2 describe-client-vpn-endpoints \
  --query 'ClientVpnEndpoints[].ClientVpnEndpointId'
```

**Fix.** Connect the AWS Client VPN and make sure `client_vpn.enabled = true`.
If you intentionally use public EKS access, set `eks_endpoint_public_access =
true` and restrict `eks_public_access_cidrs` to a real operator or VPN egress
CIDR.

## Client VPN Cannot Connect

**Symptom.** AWS VPN Client cannot connect, or connects but `kubectl` still
times out.

**Check.**

```bash
aws ec2 describe-client-vpn-endpoints
aws ec2 describe-client-vpn-target-networks \
  --client-vpn-endpoint-id cvpn-endpoint-id
```

**Fix.** Confirm the ACM server and client root certificate ARNs in
`client_vpn` are real, the VPN endpoint has target network associations, and
the client profile is imported into the VPN client with the matching client
certificate and private key.

## ArgoCD Cannot Read The Repository

**Symptom.** Applications stay `Unknown` or ArgoCD logs show repository
authentication errors.

**Check.**

```bash
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository
kubectl -n argocd logs deploy/argocd-repo-server --tail=50
```

**Fix.** For a private repo, register the deploy key:

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

For a public HTTPS repo, make sure `repoURL` in
`gitops/environments/dev/environment.json` uses the public HTTPS URL.

## ExternalSecret Is Not Ready

**Symptom.** The application pod is missing database environment variables, or:

```bash
kubectl get externalsecrets -A
```

shows `Ready=False`.

**Check.**

```bash
kubectl -n external-secrets logs deploy/external-secrets --tail=50
kubectl -n example-app describe externalsecret example-app
```

**Fix.** Run:

```bash
make configure-app-secret ENV=dev
make configure-gitops-values ENV=dev
make gitops-validate ENV=dev
git add gitops/
git commit -m "Refresh dev GitOps values"
git push
```

Then let ArgoCD sync again.

## ALB Remains During Destroy

**Symptom.** `make destroy ENV=dev` fails because VPC resources are still in
use.

**Fix.**

```bash
make destroy-gitops ENV=dev
kubectl get ingress -A
make destroy ENV=dev
```

Wait until ingresses and load balancers are gone before destroying Terraform
resources.

## Database Deletion Protection Blocks Destroy

**Symptom.** Terraform cannot delete the RDS instance.

**Fix.** Set these values in the environment tfvars, apply the change, then
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
