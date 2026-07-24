#!/usr/bin/env bash
# Fills the application secret in AWS Secrets Manager from the RDS-managed
# master secret and the RDS endpoint. Terraform creates the secret empty on
# purpose, so no database credential ever lands in Terraform state.
#
# Usage: scripts/configure-app-secret.sh <env>
#
# Idempotent: re-running overwrites the database fields with the current RDS
# values and keeps the existing APP_SECRET_KEY, so application sessions and
# signatures survive a re-run. Nothing secret is printed.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <env>" >&2
  exit 1
fi

env="$1"
tf_dir="terraform/envs/${env}"

if [ ! -d "$tf_dir" ]; then
  echo "No such environment: ${tf_dir}" >&2
  exit 1
fi

for tool in aws jq; do
  command -v "$tool" >/dev/null || { echo "${tool} is required" >&2; exit 1; }
done

# Read every Terraform output up front so a missing one fails before anything is
# written. An empty value means the environment has not been applied yet.
tf_output() {
  local name="$1" value
  if ! value="$(terraform -chdir="$tf_dir" output -raw "$name" 2>/dev/null)" || [ -z "$value" ]; then
    echo "Terraform output '${name}' is not available. Run 'make apply ENV=${env}' first." >&2
    exit 1
  fi
  printf '%s' "$value"
}

app_secret_name="$(tf_output app_secret_name)"
master_secret_arn="$(tf_output rds_master_secret_arn)"
# rds_endpoint is "host:port"; the app wants them separately.
db_host="$(tf_output rds_endpoint)"
db_host="${db_host%%:*}"
db_port="$(tf_output rds_port)"
db_name="$(tf_output rds_db_name)"
db_user="$(tf_output rds_username)"
region="$(tf_output aws_region)"

echo "Configuring application secret ${app_secret_name} in ${region}"

# The RDS-managed secret holds {"username": ..., "password": ...}.
master_json="$(aws secretsmanager get-secret-value \
  --secret-id "$master_secret_arn" \
  --region "$region" \
  --query SecretString \
  --output text)"

db_password="$(printf '%s' "$master_json" | jq -r '.password')"
if [ -z "$db_password" ] || [ "$db_password" = "null" ]; then
  echo "RDS master secret has no password field" >&2
  exit 1
fi

# Keep the existing signing key if the secret was already populated; generate
# one otherwise. Rotating it on every run would invalidate live sessions.
existing_json="$(aws secretsmanager get-secret-value \
  --secret-id "$app_secret_name" \
  --region "$region" \
  --query SecretString \
  --output text 2>/dev/null || true)"

app_secret_key="$(printf '%s' "$existing_json" | jq -r '.APP_SECRET_KEY // empty' 2>/dev/null || true)"
if [ -z "$app_secret_key" ]; then
  app_secret_key="$(openssl rand -hex 32)"
  echo "Generated a new APP_SECRET_KEY"
else
  echo "Keeping the existing APP_SECRET_KEY"
fi

# jq builds the payload so passwords with shell or URL metacharacters survive.
payload="$(jq -n \
  --arg host "$db_host" \
  --arg port "$db_port" \
  --arg name "$db_name" \
  --arg user "$db_user" \
  --arg password "$db_password" \
  --arg key "$app_secret_key" \
  '{
    DB_HOST: $host,
    DB_PORT: $port,
    DB_NAME: $name,
    DB_USER: $user,
    DB_PASSWORD: $password,
    APP_SECRET_KEY: $key,
    DATABASE_URL: ("postgresql://" + ($user | @uri) + ":" + ($password | @uri) + "@" + $host + ":" + $port + "/" + $name)
  }')"

# put-secret-value creates a new version of an existing secret; Terraform owns
# the secret itself. Output is discarded because it echoes the payload.
aws secretsmanager put-secret-value \
  --secret-id "$app_secret_name" \
  --region "$region" \
  --secret-string "$payload" \
  --output text >/dev/null

unset payload db_password app_secret_key master_json existing_json

echo "Wrote keys DB_HOST, DB_PORT, DB_NAME, DB_USER, DB_PASSWORD, DATABASE_URL, APP_SECRET_KEY"
echo "External Secrets copies them into the Kubernetes Secret named in exampleApp.secretName"
