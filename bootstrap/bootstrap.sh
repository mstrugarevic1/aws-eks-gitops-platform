#!/usr/bin/env bash
# Creates the remote Terraform backend for an environment: an S3 bucket for
# state and a DynamoDB table for state locking. Run once per environment before
# `terraform init`. Safe to re-run; existing resources are left in place.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <project> <env> <aws-region>" >&2
  exit 1
fi

project="$1"
env="$2"
region="$3"

# Resource names are derived so each account/env gets a unique, predictable set.
# The account ID keeps the bucket name globally unique.
account_id="$(aws sts get-caller-identity --query Account --output text)"
bucket="${project}-${env}-tfstate-${account_id}"
lock_table="${project}-${env}-tf-locks"
backend_file="$(dirname "$0")/backend-${env}.hcl"

echo "Bootstrapping Terraform backend for ${project}/${env} in ${region}"

# Create the state bucket. us-east-1 rejects a LocationConstraint, so it needs
# a separate call from every other region.
if aws s3api head-bucket --bucket "$bucket" 2>/dev/null; then
  echo "S3 bucket already exists: ${bucket}"
else
  echo "Creating S3 bucket: ${bucket}"
  if [ "$region" = "us-east-1" ]; then
    aws s3api create-bucket --bucket "$bucket" --region "$region"
  else
    aws s3api create-bucket \
      --bucket "$bucket" \
      --region "$region" \
      --create-bucket-configuration LocationConstraint="$region"
  fi
fi

# Versioning lets you recover a previous state file if one is corrupted.
echo "Enabling bucket versioning"
aws s3api put-bucket-versioning \
  --bucket "$bucket" \
  --versioning-configuration Status=Enabled

# State can contain sensitive values, so encrypt at rest and block all public access.
echo "Enabling bucket encryption"
aws s3api put-bucket-encryption \
  --bucket "$bucket" \
  --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

echo "Blocking public access on state bucket"
aws s3api put-public-access-block \
  --bucket "$bucket" \
  --public-access-block-configuration BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

# DynamoDB table holds the state lock so two applies cannot run at once.
if aws dynamodb describe-table --table-name "$lock_table" --region "$region" >/dev/null 2>&1; then
  echo "DynamoDB lock table already exists: ${lock_table}"
else
  echo "Creating DynamoDB lock table: ${lock_table}"
  aws dynamodb create-table \
    --table-name "$lock_table" \
    --region "$region" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --billing-mode PAY_PER_REQUEST
  aws dynamodb wait table-exists --table-name "$lock_table" --region "$region"
fi

# Write the generated values into the backend config that `terraform init` reads.
cat >"$backend_file" <<EOF
bucket         = "${bucket}"
key            = "${project}/${env}/terraform.tfstate"
region         = "${region}"
dynamodb_table = "${lock_table}"
encrypt        = true
EOF

echo
echo "Backend config written to ${backend_file}"
echo
echo "Next steps:"
echo "  make init ENV=${env} AWS_REGION=${region}"
echo "  make plan ENV=${env} AWS_REGION=${region}"
