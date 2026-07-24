# Configuration

## AWS Accounts

Each environment deploys into the AWS account declared in its tfvars file:

```hcl
aws_account_id = "111111111111"

deployment_role_arn = (
  "arn:aws:iam::111111111111:role/platform-terraform-deploy"
)
```

The deployment role must already exist in the target account. The EKS stack
assumes it; it does not create or bootstrap its own cross-account role.

Terraform also checks the caller identity after assuming the role. If the
resolved account does not match `aws_account_id`, the plan fails with:

```text
Terraform authenticated against an unexpected AWS account.
```
