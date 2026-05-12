import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class PrivateImageRegistryTests(unittest.TestCase):
    def test_group_vars_default_to_volces_public_registry_for_packaged_images(self):
        group_vars = read_text("ansible/group_vars/all.yml")

        self.assertIn("private_image_registry_host_default: anybackup-v9-cn-beijing.cr.volces.com", group_vars)
        self.assertIn("private_image_registry_namespace_default: anybackup-ai", group_vars)
        self.assertIn('private_image_registry_prefix: "{{ private_image_registry_host_effective }}/{{ private_image_registry_namespace_effective }}"', group_vars)
        self.assertIn("private_image_registry_prefix ~ '/k8s/local-path-provisioner:v0.0.31'", group_vars)
        self.assertIn("private_image_registry_prefix ~ '/thirdparty/busybox:1.36'", group_vars)
        self.assertIn("image: \"{{ private_image_registry_prefix }}/infra/postgres:17\"", group_vars)
        self.assertIn("image: \"{{ private_image_registry_prefix }}/infra/rabbitmq:3-management\"", group_vars)
        self.assertIn("image: \"{{ private_image_registry_prefix }}/infra/redis:7\"", group_vars)
        self.assertIn("image: \"{{ private_image_registry_prefix }}/infra/opensearch:3.6.0\"", group_vars)
        self.assertIn("init_image: \"{{ private_image_registry_prefix }}/thirdparty/busybox:latest\"", group_vars)
        self.assertIn('v9_services_image_registry: "{{ private_image_registry_prefix }}"', group_vars)

    def test_release_templates_use_volces_registry_variables(self):
        api_gateway = read_text("ansible/roles/internal/release/templates/api-gateway-values.yaml.j2")
        auth = read_text("ansible/roles/internal/release/templates/auth-service-values.yaml.j2")
        conversation = read_text("ansible/roles/internal/release/templates/conversation-service-values.yaml.j2")
        core_agent = read_text("ansible/roles/internal/release/templates/core-agent-real-values.yaml.j2")
        web = read_text("ansible/roles/internal/release/templates/agent-web-values.yaml.j2")

        self.assertIn("private_image_registry_prefix", api_gateway)
        self.assertIn("thirdparty/traefik", api_gateway)
        self.assertIn("v3.6.13", api_gateway)
        self.assertIn("private_image_registry_prefix", auth)
        self.assertIn("thirdparty/keycloak", auth)
        self.assertIn("{{ v9_services_image_registry }}", conversation)
        self.assertIn("svc/conversation-service", conversation)
        self.assertIn("core_agent_service.image_repository", core_agent)
        self.assertIn("svc/core-agent-service", core_agent)
        self.assertIn("v9_services_image_registry", web)
        self.assertIn("svc/agent-web", web)

    def test_kweaver_official_image_overrides_stay_on_upstream_registry(self):
        group_vars = read_text("ansible/group_vars/all.yml")

        self.assertIn("swr.cn-east-3.myhuaweicloud.com/kweaver-ai/dip/mf-model-api:0.6.0", group_vars)
