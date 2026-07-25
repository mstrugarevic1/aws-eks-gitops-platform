#!/usr/bin/env bash
# Read-only checks that an environment is actually running: AWS identity,
# cluster reachability, ArgoCD applications, secrets, workload and observability.
# Every check fails loudly; nothing is suppressed with `|| true` and no secret
# value is ever printed.
#
# Usage: scripts/verify.sh <env>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <env>" >&2
  exit 1
fi

env="$1"
tf_dir="terraform/stack"
env_json="gitops/environments/${env}/environment.json"

for tool in aws kubectl jq python3; do
  command -v "$tool" >/dev/null || {
    echo "${tool} is required" >&2
    exit 1
  }
done

[ -f "$env_json" ] || {
  echo "No such environment: ${env_json}" >&2
  exit 1
}

failures=0

pass() { printf 'ok    %s\n' "$1"; }
fail() {
  printf 'FAIL  %s\n' "$1"
  failures=$((failures + 1))
}

json_get() { python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)
' "$env_json" "$1"; }

argocd_ns="$(json_get argocdNamespace)"
app_ns="$(json_get namespaces.app)"
eso_ns="$(json_get namespaces.externalSecrets)"
obs_ns="$(json_get namespaces.observability)"
app_secret="$(json_get exampleApp.secretName)"
cluster_name="$(json_get aws.clusterName)"
expected_region="$(json_get aws.region)"

echo "== AWS =="
if identity="$(aws sts get-caller-identity --output json 2>/dev/null)"; then
  pass "AWS identity: $(printf '%s' "$identity" | jq -r '.Arn')"
else
  fail "aws sts get-caller-identity failed"
fi

# The Terraform output is the truth; environment.json should already match it.
if tf_region="$(terraform -chdir="$tf_dir" output -raw aws_region 2>/dev/null)"; then
  if [ "$tf_region" = "$expected_region" ]; then
    pass "region matches Terraform: ${tf_region}"
  else
    fail "region mismatch: environment.json=${expected_region} terraform=${tf_region}"
  fi
else
  echo "note  Terraform outputs unavailable, skipping region cross-check"
fi

echo "== Cluster =="
if context="$(kubectl config current-context 2>/dev/null)"; then
  case "$context" in
    *"$cluster_name"*) pass "kubectl context: ${context}" ;;
    *) fail "kubectl context ${context} does not look like ${cluster_name}; run make kubeconfig ENV=${env}" ;;
  esac
else
  fail "no current kubectl context"
fi

if nodes="$(kubectl get nodes -o json 2>/dev/null)"; then
  total="$(printf '%s' "$nodes" | jq '.items | length')"
  ready="$(printf '%s' "$nodes" | jq '[.items[] | select(.status.conditions[] | select(.type=="Ready" and .status=="True"))] | length')"
  if [ "$total" -gt 0 ] && [ "$total" = "$ready" ]; then
    pass "nodes Ready: ${ready}/${total}"
  else
    fail "nodes Ready: ${ready}/${total}"
  fi
else
  fail "kubectl get nodes failed"
fi

echo "== ArgoCD =="
if kubectl get namespace "$argocd_ns" >/dev/null 2>&1; then
  pass "namespace ${argocd_ns} exists"
else
  fail "namespace ${argocd_ns} missing"
fi

root_app="${env}-root"
if kubectl -n "$argocd_ns" get application "$root_app" >/dev/null 2>&1; then
  pass "root Application ${root_app} exists"
else
  fail "root Application ${root_app} missing; run make apply-argocd-apps ENV=${env}"
fi

if apps="$(kubectl -n "$argocd_ns" get applications -o json 2>/dev/null)"; then
  while read -r name sync health; do
    [ -n "$name" ] || continue
    if [ "$sync" = "Synced" ] && [ "$health" = "Healthy" ]; then
      pass "Application ${name}: ${sync}/${health}"
    else
      fail "Application ${name}: ${sync}/${health}"
    fi
  done < <(printf '%s' "$apps" | jq -r '.items[] | "\(.metadata.name) \(.status.sync.status // "Unknown") \(.status.health.status // "Unknown")"')
else
  fail "cannot list ArgoCD Applications"
fi

echo "== Secrets =="
if kubectl -n "$eso_ns" get deployment external-secrets -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -qE '^[1-9]'; then
  pass "External Secrets Operator available in ${eso_ns}"
else
  fail "External Secrets Operator not available in ${eso_ns}"
fi

es_status="$(kubectl -n "$app_ns" get externalsecret "$app_secret" \
  -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || printf '')"
if [ "$es_status" = "True" ]; then
  pass "ExternalSecret ${app_ns}/${app_secret} Ready"
else
  fail "ExternalSecret ${app_ns}/${app_secret} not Ready (status='${es_status:-missing}')"
fi

# Only the key names are read; values are never fetched or printed.
if keys="$(kubectl -n "$app_ns" get secret "$app_secret" -o jsonpath='{.data}' 2>/dev/null | jq -r 'keys | join(",")')"; then
  pass "Secret ${app_ns}/${app_secret} exists with keys: ${keys}"
else
  fail "Secret ${app_ns}/${app_secret} missing"
fi

echo "== Workload =="
deployments="$(kubectl -n "$app_ns" get deployments -o json 2>/dev/null || printf '{"items":[]}')"
if [ "$(printf '%s' "$deployments" | jq '.items | length')" -eq 0 ]; then
  fail "no Deployment in ${app_ns}"
else
  while read -r name ready desired; do
    if [ "$ready" = "$desired" ] && [ "$ready" != "0" ]; then
      pass "Deployment ${name}: ${ready}/${desired} available"
    else
      fail "Deployment ${name}: ${ready}/${desired} available"
    fi
  done < <(printf '%s' "$deployments" | jq -r '.items[] | "\(.metadata.name) \(.status.availableReplicas // 0) \(.spec.replicas // 0)"')
fi

if [ "$(kubectl -n "$app_ns" get services -o json 2>/dev/null | jq '.items | length')" -gt 0 ]; then
  pass "Service present in ${app_ns}"
else
  fail "no Service in ${app_ns}"
fi

ingresses="$(kubectl -n "$app_ns" get ingress -o json 2>/dev/null || printf '{"items":[]}')"
if [ "$(printf '%s' "$ingresses" | jq '.items | length')" -eq 0 ]; then
  echo "note  no Ingress in ${app_ns} (expected when ingress.enabled is false)"
else
  while read -r name address; do
    if [ -n "$address" ] && [ "$address" != "null" ]; then
      pass "Ingress ${name} has an address: ${address}"
    else
      fail "Ingress ${name} has no ALB address yet"
    fi
  done < <(printf '%s' "$ingresses" | jq -r '.items[] | "\(.metadata.name) \(.status.loadBalancer.ingress[0].hostname // "")"')
fi

echo "== Observability =="
if kubectl get namespace "$obs_ns" >/dev/null 2>&1; then
  bad="$(kubectl -n "$obs_ns" get pods -o json | jq -r '[.items[] | select(.status.phase != "Running" and .status.phase != "Succeeded") | .metadata.name] | join(", ")')"
  if [ -z "$bad" ]; then
    pass "all pods Running in ${obs_ns}"
  else
    fail "pods not Running in ${obs_ns}: ${bad}"
  fi

  pending="$(kubectl -n "$obs_ns" get pvc -o json | jq -r '[.items[] | select(.status.phase != "Bound") | .metadata.name] | join(", ")')"
  if [ -z "$pending" ]; then
    pass "all PVCs Bound in ${obs_ns}"
  else
    fail "PVCs not Bound in ${obs_ns}: ${pending}"
  fi
else
  echo "note  namespace ${obs_ns} does not exist (expected when observability is disabled)"
fi

echo
if [ "$failures" -gt 0 ]; then
  echo "${failures} check(s) failed"
  exit 1
fi
echo "All checks passed for ${env}"
