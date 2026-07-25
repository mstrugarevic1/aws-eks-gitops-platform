#!/usr/bin/env python3
import json
import os
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPONENTS_FILE = ROOT / "gitops/base/components.json"
REGISTRY_FILE = ROOT / "gitops/environments/environments.json"


def load_json(path):
    with path.open() as fh:
        return json.load(fh)


def env_dir(env):
    return ROOT / "gitops/environments" / env


def env_config(env):
    path = env_dir(env) / "environment.json"
    if not path.is_file():
        raise SystemExit(f"missing environment config: {path}")
    return load_json(path)


def components():
    return load_json(COMPONENTS_FILE)["components"]


def registered_envs():
    return load_json(REGISTRY_FILE)["environments"]


def nested_get(data, dotted):
    value = data
    for part in dotted.split("."):
        value = value[part]
    return value


def yaml_scalar(value):
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if value == "*":
        return '"*"'
    return json.dumps(value)


def to_yaml(value, indent=0):
    pad = " " * indent
    if isinstance(value, dict):
        lines = []
        for key, item in value.items():
            if isinstance(item, dict | list):
                lines.append(f"{pad}{key}:")
                lines.append(to_yaml(item, indent + 2))
            else:
                lines.append(f"{pad}{key}: {yaml_scalar(item)}")
        return "\n".join(lines)
    if isinstance(value, list):
        lines = []
        for item in value:
            if isinstance(item, dict | list):
                lines.append(f"{pad}-")
                lines.append(to_yaml(item, indent + 2))
            else:
                lines.append(f"{pad}- {yaml_scalar(item)}")
        return "\n".join(lines)
    return f"{pad}{yaml_scalar(value)}"


def write_yaml(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if isinstance(data, list) and all(isinstance(item, dict) and "apiVersion" in item for item in data):
        path.write_text("\n---\n".join(to_yaml(item) for item in data) + "\n")
        return
    path.write_text(f"{to_yaml(data)}\n")


def app_name(env, component):
    return f"{env['name']}-{component['name']}"


def repo_path(env, path):
    if path.startswith(("values/", "manifests/")):
        return f"gitops/environments/{env['name']}/{path}"
    return path


def sync_policy(env, create_namespace=False):
    policy = json.loads(json.dumps(env["syncPolicy"]))
    if create_namespace:
        policy["syncOptions"] = ["CreateNamespace=true"]
    return policy


def app_manifest(env, component):
    source = component["source"]
    namespace = env["namespaces"][component["namespaceKey"]]
    spec = {
        "project": "default",
        "destination": {
            "server": env["destinationServer"],
            "namespace": namespace,
        },
        "syncPolicy": sync_policy(env, component.get("createNamespace", False)),
    }
    value_files = [repo_path(env, p) for p in component.get("valueFiles", [])]
    value_files += [nested_get(env, p) for p in component.get("valueFilesFromEnv", [])]
    parameters = [
        {"name": p["name"], "value": nested_get(env, p["valueRef"])}
        for p in component.get("helmParametersFromEnv", [])
    ]

    if "chart" in source:
        chart_source = {
            "repoURL": source["repoURL"],
            "chart": source["chart"],
            "targetRevision": source["targetRevision"],
        }
        helm = {}
        if value_files:
            helm["valueFiles"] = [f"$values/{p}" for p in value_files]
        if parameters:
            helm["parameters"] = parameters
        if helm:
            chart_source["helm"] = helm
        spec["sources"] = [
            chart_source,
            {
                "repoURL": env["repoURL"],
                "targetRevision": env["targetRevision"],
                "ref": "values",
            },
        ]
    else:
        app_source = {
            "repoURL": env["repoURL"],
            "targetRevision": env["targetRevision"],
            "path": repo_path(env, source["path"]),
        }
        if "include" in source:
            app_source["directory"] = {"include": source["include"]}
        helm = {}
        if value_files:
            helm["valueFiles"] = value_files
        if parameters:
            helm["parameters"] = parameters
        if helm:
            app_source["helm"] = helm
        spec["source"] = app_source

    return {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "metadata": {
            "name": app_name(env, component),
            "namespace": env["argocdNamespace"],
            "annotations": {"argocd.argoproj.io/sync-wave": str(component["wave"])},
            "finalizers": ["resources-finalizer.argocd.argoproj.io"],
        },
        "spec": spec,
    }


def root_manifest(env):
    return {
        "apiVersion": "argoproj.io/v1alpha1",
        "kind": "Application",
        "metadata": {
            "name": f"{env['name']}-root",
            "namespace": env["argocdNamespace"],
            "finalizers": ["resources-finalizer.argocd.argoproj.io"],
        },
        "spec": {
            "project": "default",
            "source": {
                "repoURL": env["repoURL"],
                "targetRevision": env["targetRevision"],
                "path": f"gitops/environments/{env['name']}/apps",
            },
            "destination": {
                "server": env["destinationServer"],
                "namespace": env["argocdNamespace"],
            },
            "syncPolicy": sync_policy(env, True),
        },
    }


def external_secret_manifests(env):
    store_name = f"{env['name']}-aws-secretsmanager"
    return [
        {
            "apiVersion": "external-secrets.io/v1",
            "kind": "ClusterSecretStore",
            "metadata": {"name": store_name},
            "spec": {
                "provider": {
                    "aws": {
                        "service": "SecretsManager",
                        "region": env["aws"]["region"],
                        "auth": {
                            "jwt": {
                                "serviceAccountRef": {
                                    "name": "external-secrets",
                                    "namespace": env["namespaces"]["externalSecrets"],
                                }
                            }
                        },
                    }
                }
            },
        },
        {
            "apiVersion": "external-secrets.io/v1",
            "kind": "ExternalSecret",
            "metadata": {
                "name": env["exampleApp"]["secretName"],
                "namespace": env["namespaces"]["app"],
            },
            "spec": {
                "refreshInterval": "1h",
                "secretStoreRef": {"name": store_name, "kind": "ClusterSecretStore"},
                "target": {"name": env["exampleApp"]["secretName"], "creationPolicy": "Owner"},
                "dataFrom": [{"extract": {"key": env["exampleApp"]["secretManagerPath"]}}],
            },
        },
    ]


def addon_values(env):
    roles = env["aws"]["roles"]
    return {
        "aws-load-balancer-controller-values.yaml": {
            "clusterName": env["aws"]["clusterName"],
            "region": env["aws"]["region"],
            "vpcId": env["aws"]["vpcId"],
            "serviceAccount": {
                "create": True,
                "name": "aws-load-balancer-controller",
                "annotations": {
                    "eks.amazonaws.com/role-arn": roles["awsLoadBalancerController"]
                },
            },
        },
        "cluster-autoscaler-values.yaml": {
            "autoDiscovery": {"clusterName": env["aws"]["clusterName"]},
            "awsRegion": env["aws"]["region"],
            "rbac": {
                "serviceAccount": {
                    "create": True,
                    "name": "cluster-autoscaler",
                    "annotations": {
                        "eks.amazonaws.com/role-arn": roles["clusterAutoscaler"]
                    },
                }
            },
        },
        "external-secrets-values.yaml": {
            "installCRDs": True,
            "serviceAccount": {
                "annotations": {"eks.amazonaws.com/role-arn": roles["externalSecrets"]}
            },
        },
        "vm-stack-values.yaml": {
            "grafana": {
                "serviceAccount": {
                    "annotations": {
                        "eks.amazonaws.com/role-arn": roles["grafanaCloudWatch"]
                    }
                }
            }
        },
    }


def render(env_name):
    env = env_config(env_name)
    apps_dir = env_dir(env_name) / "apps"
    if apps_dir.exists():
        shutil.rmtree(apps_dir)

    write_yaml(env_dir(env_name) / "root-app.yaml", root_manifest(env))
    enabled_components = [component for component in components() if nested_get(env, component["enabledKey"])]
    for component in enabled_components:
        write_yaml(apps_dir / f"{component['name']}.yaml", app_manifest(env, component))
    for name, values in addon_values(env).items():
        write_yaml(env_dir(env_name) / "values" / name, values)
    if env["addons"]["externalSecrets"]:
        write_yaml(
            env_dir(env_name) / "manifests/external-secrets/external-secrets.yaml",
            external_secret_manifests(env),
        )


def unresolved(value):
    if isinstance(value, dict):
        return any(unresolved(v) for v in value.values())
    if isinstance(value, list):
        return any(unresolved(v) for v in value)
    if isinstance(value, str):
        placeholders = (
            "AWS_ACCOUNT_ID",
            "AWS_REGION",
            "VPC_ID",
            "CERTIFICATE_ID",
            "ECR_REPOSITORY_URL",
            "REPLACE_ME",
        )
        return value == "" or "<" in value or "replace-me" in value or any(p in value for p in placeholders)
    return False


def validate(env_name):
    errors = []
    env = env_config(env_name)
    if env_name not in registered_envs():
        errors.append(f"{env_name} is not registered in {REGISTRY_FILE}")

    required = [
        "repoURL",
        "targetRevision",
        "destinationServer",
        "argocdNamespace",
        "aws.accountId",
        "aws.region",
        "aws.clusterName",
        "aws.vpcId",
        "aws.roles.awsLoadBalancerController",
        "aws.roles.clusterAutoscaler",
        "aws.roles.externalSecrets",
        "aws.roles.grafanaCloudWatch",
        "namespaces.system",
        "namespaces.externalSecrets",
        "namespaces.observability",
        "namespaces.app",
        "exampleApp.valuesFile",
        "exampleApp.secretName",
        "exampleApp.secretManagerPath",
        "exampleApp.image.repository",
        "exampleApp.image.tag",
    ]
    for path in required:
        try:
            value = nested_get(env, path)
        except KeyError:
            value = None
        if value in (None, ""):
            errors.append(f"missing required value: {path}")

    # ECR repositories are created with IMMUTABLE tags, so a moving tag cannot be
    # re-pushed and ArgoCD could never tell one rollout from the next.
    if env.get("exampleApp", {}).get("image", {}).get("tag") == "latest":
        errors.append("exampleApp.image.tag must be an explicit version, not latest")

    env_words = set(registered_envs()) | {"dev", "staging", "production"}
    for other in sorted(env_words - {env_name}):
        for path in ("aws.clusterName", "exampleApp.secretManagerPath", "exampleApp.valuesFile"):
            value = nested_get(env, path)
            if other in value:
                errors.append(f"{env_name} references {other}: {path}={value}")

    if env_name == "production":
        if env["syncPolicy"].get("automated", {}).get("prune", False):
            errors.append("production must not enable automated prune by default")
        if env["aws"].get("accountId") in ("", "AWS_ACCOUNT_ID"):
            errors.append("production must set a real aws.accountId")

    app_names = set()
    enabled_components = [component for component in components() if nested_get(env, component["enabledKey"])]
    for component in enabled_components:
        name = app_name(env, component)
        if name in app_names:
            errors.append(f"duplicate ArgoCD Application name: {name}")
        app_names.add(name)

        rendered = env_dir(env_name) / "apps" / f"{component['name']}.yaml"
        if not rendered.is_file():
            errors.append(f"missing rendered Application: {rendered}")
        else:
            text = rendered.read_text()
            expected_ns = env["namespaces"][component["namespaceKey"]]
            if f"name: {json.dumps(name)}" not in text:
                errors.append(f"Application name mismatch in {rendered}")
            if f"namespace: {json.dumps(expected_ns)}" not in text:
                errors.append(f"namespace mismatch in {rendered}: expected {expected_ns}")

        source = component["source"]
        if "path" in source:
            path = repo_path(env, source["path"])
            if not (ROOT / path).exists():
                errors.append(f"invalid source path for {component['name']}: {path}")
        for value_file in component.get("valueFiles", []):
            path = repo_path(env, value_file).removeprefix("../../")
            if not (ROOT / path).is_file():
                errors.append(f"invalid Helm values file for {component['name']}: {path}")
        for value_ref in component.get("valueFilesFromEnv", []):
            path = nested_get(env, value_ref)
            if not (ROOT / "gitops/apps/example-app/chart" / path).is_file():
                errors.append(f"invalid env Helm values file for {component['name']}: {path}")

    if unresolved(env):
        errors.append(f"unresolved placeholder in {env_dir(env_name) / 'environment.json'}")

    root_app = env_dir(env_name) / "root-app.yaml"
    if not root_app.is_file():
        errors.append(f"missing rendered root Application: {root_app}")

    if errors:
        raise SystemExit("\n".join(errors))
    print(f"GitOps validation OK for {env_name}")


def main():
    if len(sys.argv) < 2 or sys.argv[1] not in {"render", "validate"}:
        raise SystemExit("usage: scripts/gitops.py render|validate [env]")
    env_name = sys.argv[2] if len(sys.argv) > 2 else os.environ.get("ENV", "dev")
    if sys.argv[1] == "render":
        render(env_name)
    else:
        validate(env_name)


if __name__ == "__main__":
    main()
