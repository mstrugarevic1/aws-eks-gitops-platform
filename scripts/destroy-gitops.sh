#!/usr/bin/env bash
# Removes everything ArgoCD manages, in the order Terraform needs.
#
# The AWS Load Balancer Controller creates ALBs and target groups outside
# Terraform's state. If Terraform destroys the VPC while they still exist, the
# destroy fails on dependency violations and leaves orphaned AWS resources
# behind. Deleting the root Application first lets the controllers clean up
# their own cloud resources.
#
# Usage: scripts/destroy-gitops.sh <env>
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "Usage: $0 <env>" >&2
  exit 1
fi

env="$1"
env_json="gitops/environments/${env}/environment.json"
[ -f "$env_json" ] || { echo "No such environment: ${env_json}" >&2; exit 1; }

for tool in kubectl jq python3; do
  command -v "$tool" >/dev/null || { echo "${tool} is required" >&2; exit 1; }
done

json_get() { python3 -c '
import json, sys
value = json.load(open(sys.argv[1]))
for key in sys.argv[2].split("."):
    value = value[key]
print(value)
' "$env_json" "$1"; }

argocd_ns="$(json_get argocdNamespace)"
app_ns="$(json_get namespaces.app)"
obs_ns="$(json_get namespaces.observability)"
root_app="${env}-root"

# How long to wait for controllers to finish. ALB deletion is the slow part.
timeout="${DESTROY_TIMEOUT:-600}"

wait_for() {
  local label="$1" deadline
  shift
  deadline=$(( $(date +%s) + timeout ))
  echo "Waiting for ${label} (timeout ${timeout}s)"
  while ! "$@"; do
    if [ "$(date +%s)" -ge "$deadline" ]; then
      echo "Timed out waiting for ${label}" >&2
      return 1
    fi
    sleep 10
  done
  echo "Done: ${label}"
}

no_child_apps() {
  local remaining
  remaining="$(kubectl -n "$argocd_ns" get applications -o json | jq -r '[.items[].metadata.name] | join(", ")')"
  [ -z "$remaining" ] || { echo "  still present: ${remaining}"; return 1; }
}

no_ingresses() {
  local remaining
  remaining="$(kubectl get ingress --all-namespaces -o json | jq -r '[.items[] | "\(.metadata.namespace)/\(.metadata.name)"] | join(", ")')"
  [ -z "$remaining" ] || { echo "  still present: ${remaining}"; return 1; }
}

no_lb_services() {
  local remaining
  remaining="$(kubectl get services --all-namespaces -o json \
    | jq -r '[.items[] | select(.spec.type == "LoadBalancer") | "\(.metadata.namespace)/\(.metadata.name)"] | join(", ")')"
  [ -z "$remaining" ] || { echo "  still present: ${remaining}"; return 1; }
}

if ! kubectl -n "$argocd_ns" get application "$root_app" >/dev/null 2>&1; then
  echo "Root Application ${root_app} not found; nothing to delete"
else
  echo "Deleting root Application ${root_app}"
  # The resources-finalizer on the Application cascades the delete to children.
  kubectl -n "$argocd_ns" delete application "$root_app" --wait=false
fi

wait_for "ArgoCD Applications to be deleted" no_child_apps
wait_for "Ingresses (ALBs) to be deleted" no_ingresses
wait_for "LoadBalancer Services to be deleted" no_lb_services

# Anything left here blocks or orphans the Terraform destroy. Report it instead
# of force-removing finalizers: that would leak the AWS resource silently.
leftovers=0
for ns in "$app_ns" "$obs_ns"; do
  kubectl get namespace "$ns" >/dev/null 2>&1 || continue

  pvcs="$(kubectl -n "$ns" get pvc -o json | jq -r '[.items[].metadata.name] | join(", ")')"
  if [ -n "$pvcs" ]; then
    echo "WARNING ${ns} still has PVCs (EBS volumes): ${pvcs}"
    leftovers=1
  fi

  stuck="$(kubectl -n "$ns" get all -o json \
    | jq -r '[.items[] | select(.metadata.deletionTimestamp != null and (.metadata.finalizers | length) > 0) | .metadata.name] | join(", ")')"
  if [ -n "$stuck" ]; then
    echo "WARNING ${ns} has resources stuck on finalizers: ${stuck}"
    leftovers=1
  fi
done

echo
if [ "$leftovers" -ne 0 ]; then
  echo "Resources remain. Review the warnings above before running: make destroy ENV=${env}"
  exit 1
fi
echo "ArgoCD-managed resources are gone. Next: make destroy ENV=${env}"
