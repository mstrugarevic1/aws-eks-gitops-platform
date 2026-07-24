# Cleanup

## Order matters

The AWS Load Balancer Controller creates ALBs, target groups and security group
rules that Terraform does not know about. If `terraform destroy` runs while they
still exist, it fails on dependency violations part way through and leaves both
orphaned AWS resources and a half-destroyed state file.

Delete what ArgoCD manages first, let the controllers clean up their own cloud
resources, then destroy Terraform's.

## 1. Remove ArgoCD-managed resources

```bash
make destroy-gitops ENV=dev
```

`scripts/destroy-gitops.sh`:

1. Deletes the root Application. Its `resources-finalizer` cascades to the child
   Applications.
2. Waits for every ArgoCD Application to disappear.
3. Waits for every Ingress to disappear, which is what deletes the ALBs.
4. Waits for every `LoadBalancer` Service to disappear.
5. Reports remaining PVCs (EBS volumes) and anything stuck on a finalizer.

Each wait has a timeout, `DESTROY_TIMEOUT` seconds, 600 by default. ALB deletion
is the slow part.

The script exits non-zero if anything is left. It never force-removes a
finalizer: that would make the Kubernetes object disappear while the AWS resource
it represents keeps running and billing.

## 2. Destroy the infrastructure

```bash
make destroy ENV=dev
```

Review the plan. It removes the VPC, EKS, node groups, RDS, ECR, IAM roles, the
Secrets Manager entry and the CloudWatch alarms.

This does **not** touch the Terraform backend. The state bucket and lock table
survive, so a failed destroy can be retried.

## 3. Delete the backend, only when you are done

```bash
./bootstrap/destroy-bootstrap.sh my-platform dev us-east-1 DELETE_TERRAFORM_BACKEND
```

The literal `DELETE_TERRAFORM_BACKEND` argument is required; the script refuses
without it. Run this only after step 2 succeeded and the state is no longer
needed. Once the bucket is gone, the state is gone.

## Destructive defaults

These behave differently per environment on purpose:

| Setting | dev | production | Effect |
| ------- | --- | ---------- | ------ |
| `ecr_force_delete` | `true` | `false` | dev deletes the repository with images still in it; production refuses |
| `app_secret_recovery_days` | `0` | `30` | dev hard-deletes the secret so it can be recreated under the same name immediately; production keeps a recovery window |
| `rds_skip_final_snapshot` | `true` | `false` | production takes a final snapshot before deleting the instance |
| `rds_deletion_protection` | `false` | `true` | production refuses to delete the database until protection is turned off |
| `rds_multi_az` | `false` | `true` | availability versus cost |

The dev defaults exist so a demo environment can be torn down in one pass. Do not
copy them into anything holding real data.

## When destroy fails

**RDS deletion protection blocks it.** Expected in production. Turn it off
deliberately:

```bash
aws rds modify-db-instance --db-instance-identifier my-platform-production \
  --no-deletion-protection --apply-immediately
```

**Final snapshot name already exists.** Snapshot identifiers are unique per
account and region. Delete the old snapshot or rename the new one:

```bash
aws rds describe-db-snapshots --query 'DBSnapshots[].DBSnapshotIdentifier'
aws rds delete-db-snapshot --db-snapshot-identifier <name>
```

**The VPC will not delete.** Something is still attached, almost always an ALB or
an ENI the controller created. Find it:

```bash
aws ec2 describe-network-interfaces --filters Name=vpc-id,Values=<vpc-id> \
  --query 'NetworkInterfaces[].{Id:NetworkInterfaceId,Desc:Description}'
aws elbv2 describe-load-balancers --query 'LoadBalancers[?VpcId==`<vpc-id>`].LoadBalancerArn'
```

Step 1 exists to prevent this. If you skipped it, run `make destroy-gitops` now,
while the cluster is still up.

**The ECR repository is not empty.** Only with `ecr_force_delete = false`. Delete
the images first, or set the flag and re-apply.

**A secret with the same name is pending deletion.** Only with
`app_secret_recovery_days > 0`. Either wait out the recovery window or force it:

```bash
aws secretsmanager delete-secret --secret-id my-platform/dev/example-app \
  --force-delete-without-recovery
```

## Verify nothing is left

```bash
aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName'
aws ec2 describe-vpcs --filters Name=tag:Project,Values=my-platform
aws rds describe-db-instances --query 'DBInstances[].DBInstanceIdentifier'
aws ec2 describe-nat-gateways --filter Name=state,Values=available
```

NAT gateways and idle ALBs bill by the hour whether or not anything uses them.
They are the usual cause of a surprising bill after a demo.
