#!/usr/bin/env bash
# Deletes the Terraform backend created by bootstrap.sh (the state S3 bucket and
# the DynamoDB lock table). Run only after `terraform destroy`, once the state is
# no longer needed. Requires DELETE_TERRAFORM_BACKEND as the last argument.
set -euo pipefail

if [ "$#" -ne 4 ]; then
  echo "Usage: $0 <project> <env> <aws-region> DELETE_TERRAFORM_BACKEND" >&2
  echo "This deletes Terraform backend resources only. It is for disposable-environment cleanup." >&2
  exit 1
fi

project="$1"
env="$2"
region="$3"
confirmation="$4"

if [ "$confirmation" != "DELETE_TERRAFORM_BACKEND" ]; then
  echo "Refusing to delete backend. Pass DELETE_TERRAFORM_BACKEND as the final argument." >&2
  exit 1
fi

account_id="$(aws sts get-caller-identity --query Account --output text)"
bucket="${project}-${env}-tfstate-${account_id}"
lock_table="${project}-${env}-tf-locks"

echo "WARNING: deleting Terraform state is dangerous."
echo "This removes only backend resources created by bootstrap, not application infrastructure."
echo "Bucket: ${bucket}"
echo "Lock table: ${lock_table}"

if aws dynamodb describe-table --table-name "$lock_table" --region "$region" >/dev/null 2>&1; then
  aws dynamodb delete-table --table-name "$lock_table" --region "$region"
  aws dynamodb wait table-not-exists --table-name "$lock_table" --region "$region"
  echo "Deleted DynamoDB lock table: ${lock_table}"
else
  echo "DynamoDB lock table not found: ${lock_table}"
fi

if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  echo "Emptying and deleting S3 bucket: ${bucket}"
  aws s3 rm "s3://${bucket}" --recursive
  aws s3api delete-bucket --bucket "$bucket" --region "$region"
else
  echo "S3 bucket not found: ${bucket}"
fi
