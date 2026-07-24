# Troubleshooting

Each entry: symptom, likely cause, how to confirm, how to fix.

## AWS and Terraform

### Invalid or expired AWS credentials

**Symptom.** `ExpiredToken`, `InvalidClientTokenId`, or
`make prerequisites` reporting `MISSING aws credentials`.

**Cause.** No profile exported, an expired SSO session, or the wrong account.

**Verify.**

```bash
aws sts get-caller-identity
echo "$AWS_PROFILE $AWS_REGION"
```

**Fix.** Re-authenticate (`aws sso login --profile <profile>`) and confirm the
account ID is the one you intend to deploy into. Terraform reads the same
environment, so a shell that cannot call `sts` cannot plan either.

### Backend bucket already exists in another account

**Symptom.** `bootstrap.sh` fails with `BucketAlreadyExists`, or
`terraform init` reports `AccessDenied` on the state bucket.

**Cause.** S3 bucket names are globally unique. The name is
`<project>-<env>-tfstate-<account-id>`, so this means either another account
already used that exact name or you are authenticated to the wrong account.

**Verify.**

```bash
aws sts get-caller-identity --query Account --output text
aws s3api head-bucket --bucket my-platform-dev-tfstate-<account-id>
```

**Fix.** Confirm the account, or change `project` in `terraform.tfvars` and in
the `make bootstrap` invocation.

### Deployment role cannot be assumed

**Symptom.** `make plan` fails with `Cannot assume IAM Role`.

**Cause.** `deployment_role_arn` does not exist in the target account, or the
current AWS identity is not trusted to assume it.

**Verify.**

```bash
aws sts get-caller-identity
aws sts assume-role \
  --role-arn arn:aws:iam::<account-id>:role/platform-terraform-deploy \
  --role-session-name terraform-check \
  --query AssumedRoleUser.Arn \
  --output text
```

**Fix.** Create or update the deployment role in the target account before
running Terraform. The EKS stack assumes that role; it does not create it.

### Terraform reached the wrong AWS account

**Symptom.** `make plan` fails with
`Terraform authenticated against an unexpected AWS account.`

**Cause.** The assumed role resolved to an account other than `aws_account_id`.

**Verify.**

```bash
aws sts get-caller-identity --query Account --output text
```

**Fix.** Correct `aws_account_id`, `deployment_role_arn`, or the AWS credentials
used before running `make plan`.

### Cannot reach the EKS API

**Symptom.** `kubectl` times out, or `Unauthorized` right after `make apply`.

**Cause.** Your address is not in `eks_public_access_cidrs`. The example value
`203.0.113.10/32` is from the RFC 5737 documentation range and matches nothing.

**Verify.**

```bash
curl -s https://checkip.amazonaws.com
aws eks describe-cluster --name my-platform-dev \
  --query 'cluster.resourcesVpcConfig.publicAccessCidrs'
```

**Fix.** Put your real address in `terraform.tfvars` and re-apply. On a
residential connection the address changes; a `/32` will need updating.

### kubectl is talking to the wrong cluster

**Symptom.** Resources appear in the wrong environment, or `make verify` reports
that the context does not look like the cluster.

**Verify.**

```bash
kubectl config current-context
kubectl config get-contexts
```

**Fix.**

```bash
make kubeconfig ENV=dev
```

It uses the cluster name and region from the Terraform outputs, so it always
matches the environment that was applied.

### AWS quota exceeded

**Symptom.** Apply fails on `VpcLimitExceeded`, `AddressLimitExceeded`,
`Elastic IP address limit`, or an EKS cluster limit.

**Cause.** Default per-region quotas: 5 VPCs, 5 Elastic IPs. `per_az` NAT
gateways consume one EIP per AZ.

**Verify.**

```bash
aws ec2 describe-vpcs --query 'length(Vpcs)'
aws ec2 describe-addresses --query 'length(Addresses)'
```

**Fix.** Delete unused VPCs and release unused EIPs, use
`nat_gateway_strategy = "single"`, or request a quota increase.

## ArgoCD

### Repository authentication failure

**Symptom.** The root Application shows `Unknown` with
`repository not accessible`, `permission denied (publickey)`, or
`could not read Username`.

**Cause.** No credential registered, or a `repoURL` that does not match the URL
in the credential Secret exactly. ArgoCD matches by URL string, so the SSH and
HTTPS forms of the same repository are different entries.

**Verify.**

```bash
kubectl -n argocd get secret -l argocd.argoproj.io/secret-type=repository
kubectl -n argocd logs deploy/argocd-repo-server --tail=50
python3 -c 'import json; print(json.load(open("gitops/environments/dev/environment.json"))["repoURL"])'
```

**Fix.**

```bash
make configure-argocd-repository ENV=dev SSH_KEY_FILE=~/.ssh/argocd_deploy_key
```

See [gitops.md](gitops.md). For a public repository use an HTTPS `repoURL` and no
credential at all.

### Application is OutOfSync forever

**Symptom.** `Synced` never sticks; the diff reappears immediately.

**Cause.** Usually a controller writing to a field the chart also sets. The
classic one is the HPA and a fixed `replicas` in the Deployment: `selfHeal`
resets it, the HPA scales it back, forever. This chart omits `replicas` when
autoscaling is enabled for exactly that reason.

**Verify.**

```bash
argocd app diff dev-example-app
kubectl -n argocd get application dev-example-app -o jsonpath='{.status.conditions}'
```

**Fix.** Remove the contested field from the chart, or add an
`ignoreDifferences` entry for it. Do not turn off `selfHeal`.

### Application is Degraded

**Symptom.** `Healthy` never arrives.

**Verify.**

```bash
argocd app get dev-example-app
kubectl -n example-app get pods
kubectl -n example-app describe pod <pod>
kubectl -n example-app logs <pod> --previous
```

Common causes: `ImagePullBackOff` (the tag was never pushed, or the node role
cannot read ECR), `CreateContainerConfigError` (the Secret does not exist yet),
`CrashLoopBackOff` (the app fails at startup), pods `Pending` (no capacity).

### Changes are not picked up

**Symptom.** A local edit produces no effect.

**Cause.** ArgoCD reconciles the remote Git repository. Uncommitted or unpushed
work is invisible to it.

**Verify.**

```bash
git status --short gitops/
git log origin/main..HEAD --oneline
```

**Fix.** Commit and push, then `argocd app sync dev-root` if you do not want to
wait for the poll interval.

### Helm chart version incompatibility

**Symptom.** A component sync fails with `unable to recognize`, an unknown field,
or `chart not found`.

**Cause.** The pinned `targetRevision` in `components.json` does not exist any
more, or the chart requires a newer Kubernetes version than the cluster runs.

**Verify.**

```bash
helm repo add eks https://aws.github.io/eks-charts && helm repo update
helm search repo eks/aws-load-balancer-controller --versions | head
kubectl version --short
```

**Fix.** Pin a version that supports your `kubernetes_version`. Cluster
Autoscaler in particular tracks the Kubernetes minor version: the chart's app
version should match the cluster's minor version.

## Secrets

### ExternalSecret reports SecretSyncedError

**Symptom.** The `ExternalSecret` is not `Ready`; the workload pod sits in
`CreateContainerConfigError` because its Secret does not exist.

**Verify.**

```bash
kubectl -n example-app get externalsecret example-app -o yaml | tail -30
kubectl -n external-secrets logs deploy/external-secrets --tail=50
aws secretsmanager describe-secret --secret-id my-platform/dev/example-app
```

**Fix by message.**

- `ResourceNotFoundException` — the secret path is wrong, or
  `make configure-app-secret ENV=dev` was never run.
- `AccessDeniedException` — the IRSA role cannot read that ARN. See below.
- `unable to find secret data` — the entry exists but is empty. Run
  `make configure-app-secret ENV=dev`.

### IRSA subject or namespace is wrong

**Symptom.** `AccessDenied` from a controller even though the IAM policy looks
correct, or `WebIdentityErr`.

**Cause.** The IAM role's trust policy pins the exact
`system:serviceaccount:<namespace>:<name>`. Moving a controller to another
namespace, or renaming its service account, breaks it silently.

**Verify.**

```bash
kubectl -n external-secrets get sa external-secrets -o jsonpath='{.metadata.annotations}'
aws iam get-role --role-name my-platform-dev-external-secrets \
  --query 'Role.AssumeRolePolicyDocument'
```

The annotation ARN and the trust policy's `sub` condition must both match the
namespace and service account actually in use.

**Fix.** Change the namespace back, or update the Terraform trust policy and
re-apply. The namespaces are declared in `environment.json` under `namespaces`.

## Workloads

### The ALB never appears

**Symptom.** The Ingress exists but `ADDRESS` stays empty.

**Verify.**

```bash
kubectl -n example-app describe ingress
kubectl -n kube-system logs deploy/aws-load-balancer-controller --tail=50
```

**Common causes.**

- The controller is not running or its IRSA role is missing.
- Public subnets are not tagged `kubernetes.io/role/elb=1`. Terraform tags them;
  a hand-edited VPC may not be.
- `ingressClassName` is not `alb`.
- Fewer than two subnets in different AZs. An ALB needs at least two.

### PVC stays Pending

**Symptom.** Observability pods stay `Pending`; the PVC is not `Bound`.

**Verify.**

```bash
kubectl get pvc -A
kubectl describe pvc -n observability <name>
kubectl get storageclass
```

**Common causes.**

- The `gp3` StorageClass does not exist. It is sync wave -10; check that the
  `storageclass` component is enabled.
- The EBS CSI driver add-on is missing or its IRSA role is wrong.
- No default StorageClass and the chart did not name one.

### Pods are Pending with insufficient cpu or memory

**Symptom.** `0/2 nodes are available: insufficient cpu`.

**Verify.**

```bash
kubectl top nodes
kubectl -n kube-system logs deploy/cluster-autoscaler --tail=50
```

**Fix.** Raise `node_max_size` or use a larger `node_instance_types`, or lower
the workload's requests. Confirm the autoscaler is actually running: without it
nothing scales out.

## Cost

### The bill is higher than expected

The recurring charges in this platform, largest first:

- **NAT gateways.** Hourly per gateway plus per-GB processing.
  `nat_gateway_strategy = "per_az"` multiplies that by the number of AZs. Use
  `single` for anything non-production.
- **RDS.** Hourly, doubled by `rds_multi_az = true`, plus storage and backups.
- **EKS control plane.** A flat hourly charge per cluster.
- **ALBs.** Hourly per load balancer plus capacity units, whether or not traffic
  flows.
- **EC2 nodes.** `node_min_size` is the floor; the autoscaler will not go below
  it.

**Verify.**

```bash
aws ec2 describe-nat-gateways --filter Name=state,Values=available \
  --query 'NatGateways[].{Id:NatGatewayId,Vpc:VpcId}'
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
```

An environment left running overnight costs real money. Tear demo environments
down with [cleanup.md](cleanup.md).
