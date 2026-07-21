"""Tests for scripts/gitops.py.

These run without AWS, without a cluster, and without writing to the repository:
rendering to disk is covered by `make check`, which renders every environment and
fails if the committed output changes.
"""

import copy
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import gitops  # noqa: E402


def env_fixture(name="dev"):
    """A real committed environment with placeholders resolved."""
    env = copy.deepcopy(gitops.env_config(name))
    env["aws"]["accountId"] = "123456789012"
    env["aws"]["vpcId"] = "vpc-0123456789abcdef0"
    for role, arn in env["aws"]["roles"].items():
        env["aws"]["roles"][role] = arn.replace("AWS_ACCOUNT_ID", "123456789012")
    env["exampleApp"]["image"]["repository"] = "123456789012.dkr.ecr.us-east-1.amazonaws.com/my-platform-dev"
    return env


def component(name):
    for item in gitops.components():
        if item["name"] == name:
            return item
    raise AssertionError(f"no such component: {name}")


class RegistryTest(unittest.TestCase):
    def test_every_registered_environment_has_a_config(self):
        for name in gitops.registered_envs():
            self.assertIn("name", gitops.env_config(name))

    def test_registered_environment_name_matches_directory(self):
        for name in gitops.registered_envs():
            self.assertEqual(gitops.env_config(name)["name"], name)

    def test_unknown_environment_fails_clearly(self):
        with self.assertRaises(SystemExit):
            gitops.env_config("does-not-exist")


class ComponentToggleTest(unittest.TestCase):
    def enabled_names(self, env):
        return [c["name"] for c in gitops.components() if gitops.nested_get(env, c["enabledKey"])]

    def test_disabling_an_addon_drops_its_components(self):
        env = env_fixture()
        env["addons"]["observability"] = False
        names = self.enabled_names(env)
        self.assertNotIn("observability-vm-stack", names)
        self.assertNotIn("observability-loki", names)
        self.assertIn("metrics-server", names)

    def test_disabling_the_example_app_drops_only_the_app(self):
        env = env_fixture()
        env["apps"]["exampleApp"] = False
        names = self.enabled_names(env)
        self.assertNotIn("example-app", names)
        self.assertIn("external-secrets", names)


class ManifestTest(unittest.TestCase):
    def test_application_name_is_environment_prefixed(self):
        env = env_fixture()
        self.assertEqual(gitops.app_name(env, component("metrics-server")), "dev-metrics-server")

    def test_namespace_comes_from_the_environment_mapping(self):
        env = env_fixture()
        manifest = gitops.app_manifest(env, component("external-secrets"))
        self.assertEqual(manifest["spec"]["destination"]["namespace"], env["namespaces"]["externalSecrets"])

    def test_namespace_creation_is_requested_only_where_declared(self):
        env = env_fixture()
        with_ns = gitops.app_manifest(env, component("external-secrets"))
        without_ns = gitops.app_manifest(env, component("metrics-server"))
        self.assertIn("CreateNamespace=true", with_ns["spec"]["syncPolicy"]["syncOptions"])
        self.assertNotIn("syncOptions", without_ns["spec"]["syncPolicy"])

    def test_helm_chart_component_pins_a_target_revision(self):
        env = env_fixture()
        manifest = gitops.app_manifest(env, component("metrics-server"))
        chart = manifest["spec"]["sources"][0]
        self.assertTrue(chart["targetRevision"])
        self.assertNotIn(chart["targetRevision"], ("", "*", "latest"))

    def test_image_is_passed_as_a_helm_parameter(self):
        env = env_fixture()
        manifest = gitops.app_manifest(env, component("example-app"))
        parameters = {p["name"]: p["value"] for p in manifest["spec"]["source"]["helm"]["parameters"]}
        self.assertEqual(parameters["image.repository"], env["exampleApp"]["image"]["repository"])
        self.assertEqual(parameters["image.tag"], env["exampleApp"]["image"]["tag"])

    def test_root_application_points_at_the_rendered_apps_directory(self):
        env = env_fixture()
        root = gitops.root_manifest(env)
        self.assertEqual(root["metadata"]["name"], "dev-root")
        self.assertEqual(root["spec"]["source"]["path"], "gitops/environments/dev/apps")
        self.assertEqual(root["spec"]["source"]["repoURL"], env["repoURL"])


class SecretTest(unittest.TestCase):
    def test_external_secret_uses_the_configured_secrets_manager_path(self):
        env = env_fixture()
        manifests = gitops.external_secret_manifests(env)
        external_secret = next(m for m in manifests if m["kind"] == "ExternalSecret")
        self.assertEqual(
            external_secret["spec"]["dataFrom"][0]["extract"]["key"],
            env["exampleApp"]["secretManagerPath"],
        )

    def test_secrets_manager_path_is_project_and_environment_scoped(self):
        for name in gitops.registered_envs():
            path = gitops.env_config(name)["exampleApp"]["secretManagerPath"]
            self.assertTrue(path.endswith(f"/{name}/example-app"), path)

    def test_kubernetes_secret_name_matches_the_chart(self):
        env = env_fixture()
        manifests = gitops.external_secret_manifests(env)
        external_secret = next(m for m in manifests if m["kind"] == "ExternalSecret")
        self.assertEqual(external_secret["spec"]["target"]["name"], env["exampleApp"]["secretName"])

    def test_secret_store_lives_in_the_application_namespace(self):
        env = env_fixture()
        manifests = gitops.external_secret_manifests(env)
        external_secret = next(m for m in manifests if m["kind"] == "ExternalSecret")
        self.assertEqual(external_secret["metadata"]["namespace"], env["namespaces"]["app"])


class UnresolvedTest(unittest.TestCase):
    def test_placeholders_are_detected(self):
        for value in (
            "AWS_ACCOUNT_ID",
            "arn:aws:iam::AWS_ACCOUNT_ID:role/x",
            "ECR_REPOSITORY_URL",
            "REPLACE_ME",
            "<fill me in>",
            "replace-me",
            "",
        ):
            self.assertTrue(gitops.unresolved(value), value)

    def test_resolved_values_pass(self):
        for value in ("123456789012", "vpc-0abc", "us-east-1", "0.1.0"):
            self.assertFalse(gitops.unresolved(value), value)

    def test_nested_placeholders_are_detected(self):
        self.assertTrue(gitops.unresolved({"a": {"b": ["ok", "REPLACE_ME"]}}))
        self.assertFalse(gitops.unresolved({"a": {"b": ["ok", "fine"]}}))

    def test_committed_environments_still_carry_placeholders(self):
        # They must: a committed environment.json has no real account ID in it.
        # `make configure-gitops-values` is what resolves them.
        for name in gitops.registered_envs():
            self.assertTrue(gitops.unresolved(gitops.env_config(name)), name)


class ValidationTest(unittest.TestCase):
    """validate() reads from disk, so these check the rules it enforces."""

    def test_every_registered_environment_renders_and_validates_as_committed(self):
        # Committed environments hold placeholders, so validate() must reject
        # them. That is the guard against pushing an unconfigured environment.
        for name in gitops.registered_envs():
            with self.assertRaises(SystemExit):
                gitops.validate(name)

    def test_production_does_not_enable_automated_prune(self):
        prune = gitops.env_config("production")["syncPolicy"]["automated"].get("prune", False)
        self.assertFalse(prune)

    def test_no_environment_references_another_environment(self):
        others = set(gitops.registered_envs())
        for name in gitops.registered_envs():
            env = gitops.env_config(name)
            for path in ("aws.clusterName", "exampleApp.secretManagerPath", "exampleApp.valuesFile"):
                value = gitops.nested_get(env, path)
                for other in others - {name}:
                    self.assertNotIn(other, value, f"{name}: {path}={value}")

    def test_image_tag_is_never_latest(self):
        for name in gitops.registered_envs():
            self.assertNotEqual(gitops.env_config(name)["exampleApp"]["image"]["tag"], "latest")

    def test_duplicate_application_names_are_impossible(self):
        for name in gitops.registered_envs():
            env = gitops.env_config(name)
            enabled = [c for c in gitops.components() if gitops.nested_get(env, c["enabledKey"])]
            names = [gitops.app_name(env, c) for c in enabled]
            self.assertEqual(len(names), len(set(names)), names)

    def test_component_source_paths_exist(self):
        env = env_fixture()
        for item in gitops.components():
            source = item["source"]
            if "path" in source:
                self.assertTrue((gitops.ROOT / gitops.repo_path(env, source["path"])).exists(), item["name"])

    def test_env_helm_values_files_exist(self):
        for name in gitops.registered_envs():
            env = gitops.env_config(name)
            values = gitops.ROOT / "gitops/apps/example-app/chart" / env["exampleApp"]["valuesFile"]
            self.assertTrue(values.is_file(), str(values))

    def test_invalid_value_path_raises(self):
        with self.assertRaises(KeyError):
            gitops.nested_get(env_fixture(), "aws.roles.doesNotExist")


class YamlTest(unittest.TestCase):
    def test_scalars_are_quoted_so_yaml_never_reinterprets_them(self):
        self.assertEqual(gitops.yaml_scalar("0.1.0"), '"0.1.0"')
        self.assertEqual(gitops.yaml_scalar(True), "true")
        self.assertEqual(gitops.yaml_scalar(20), "20")

    def test_rendering_is_deterministic(self):
        env = env_fixture()
        manifest = gitops.app_manifest(env, component("example-app"))
        self.assertEqual(gitops.to_yaml(manifest), gitops.to_yaml(json.loads(json.dumps(manifest))))


if __name__ == "__main__":
    unittest.main()
