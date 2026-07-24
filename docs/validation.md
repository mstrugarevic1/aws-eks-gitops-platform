# Validation

Two layers: static checks that need nothing but the repository, and live checks
that need a running cluster.

## Static: `make check`

```bash
make check
```

| Step | What it proves |
| ---- | -------------- |
| `terraform fmt -check -recursive` | Terraform is formatted |
| `py_compile` | `scripts/gitops.py` and `app/main.py` parse |
| `json.tool` on every config | the registries and environment files are valid JSON |
| render every environment | the renderer runs for each registered environment |
| render twice, compare hashes | rendering is deterministic |
| `python -m unittest discover -s tests` | the renderer's rules hold |
| `shellcheck` | the bootstrap and operational scripts are sound |
| `helm lint` and `helm template` per environment | the chart renders with every environment's values |

It does not run `terraform init`, call AWS, apply anything, or contact a cluster.

Environment names come from `gitops/environments/environments.json`. Adding an
environment there extends every loop; nothing else needs editing.

## Unit tests

`tests/test_gitops.py` covers the renderer's rules:

- every registered environment has a config whose `name` matches its directory
- enabling and disabling a component adds or removes its Application
- Application names are unique per environment
- placeholder detection, including nested structures
- committed environments still carry placeholders, so an unconfigured
  environment cannot validate
- `production` does not enable automated prune
- no environment references another environment's name
- image tags are never `latest`
- namespaces come from the environment's mapping, and `CreateNamespace=true` is
  set only where declared
- the root Application points at the rendered `apps/` directory
- the ExternalSecret uses the configured Secrets Manager path, and its target
  name matches the chart's `secret.name`
- an invalid dotted value path raises
- component source paths and per-environment values files exist
- YAML scalars are quoted so `0.1.0` is never reinterpreted as a number

Run them alone:

```bash
python3 -m unittest discover -s tests -v
```

## CI

The `Checks` workflow runs on pull requests and pushes to `main`, with read-only
permissions and no AWS credentials.

| Job | Contents |
| --- | -------- |
| `discover` | reads the environment list once and feeds it to the matrices |
| `terraform` | per environment: `fmt -check`, `init -backend=false`, `validate`, `tflint` |
| `terraform-foundation` | the same for the optional OIDC/ECR module |
| `terraform-security` | Checkov. Only one scanner, so findings are not reported twice |
| `shell` | `shellcheck` and `shfmt -d` |
| `python` | `py_compile`, `ruff check`, unit tests |
| `gitops` | every JSON parses; rendered manifests match the committed inputs (`git diff --exit-code`) |
| `kubernetes` | `helm lint`, `helm template` per environment, `kubeconform -strict` over the rendered output and the committed manifests |
| `repository` | `actionlint`, markdownlint, local documentation links, Gitleaks |

`kubeconform` resolves CRD schemas (ArgoCD `Application`, `ExternalSecret`,
`VMServiceScrape`) from the community CRD catalog, so ArgoCD Applications and
External Secrets are validated without a cluster.

Tool versions are pinned in the workflow so a run today and a run next month
behave the same.

## Live: `make verify`

```bash
make verify ENV=dev
```

| Group | Checks |
| ----- | ------ |
| AWS | `sts get-caller-identity` succeeds; the region in `environment.json` matches the Terraform output |
| Cluster | a kubectl context is selected and looks like this environment's cluster; every node is `Ready` |
| ArgoCD | the `argocd` namespace exists; the root Application exists; every Application is `Synced` and `Healthy` |
| Secrets | External Secrets Operator has an available replica; the `ExternalSecret` is `Ready`; the Kubernetes Secret exists |
| Workload | every Deployment in the application namespace has its replicas available; a Service exists; each Ingress has an ALB address |
| Observability | every pod in the namespace is `Running`; every PVC is `Bound` |

Each check prints `ok` or `FAIL` and the script exits non-zero if anything
failed. Nothing is suppressed with `|| true`.

Only the *names* of the Secret's keys are read, never the values.

Optional components are reported as notes rather than failures: no Ingress when
`ingress.enabled` is false, no observability namespace when the add-on is
disabled.

## Smoke test by hand

```bash
# Cluster
kubectl get nodes
kubectl get pods -A --field-selector=status.phase!=Running

# ArgoCD
kubectl -n argocd get applications
argocd app list
argocd app get dev-root

# Secrets, without printing any value
kubectl -n example-app get externalsecret
kubectl -n example-app get secret example-app -o jsonpath='{.data}' | jq 'keys'

# Workload
kubectl -n example-app get deploy,pod,svc,ingress
kubectl -n example-app logs deploy/dev-example-app-example-app --tail=50

# The application itself
kubectl -n example-app port-forward svc/dev-example-app-example-app 8080:80
curl -s localhost:8080/healthz
curl -s localhost:8080/readyz
curl -s localhost:8080/metrics | head

# Through the ALB
kubectl -n example-app get ingress -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'
```

An ALB takes two to three minutes to become reachable after the Ingress reports
an address.
