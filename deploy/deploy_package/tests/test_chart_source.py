import pathlib
import unittest


DEPLOY_ROOT = pathlib.Path(__file__).resolve().parents[2]
PACKAGE_ROOT = DEPLOY_ROOT / "deploy_package"


class ChartSourceTests(unittest.TestCase):
    def test_roles_copy_charts_from_canonical_deploy_helm(self):
        release = (PACKAGE_ROOT / "ansible/roles/internal/release/tasks/main.yml").read_text(encoding="utf-8")
        v9_infra = (PACKAGE_ROOT / "ansible/roles/internal/v9_infra/tasks/main.yml").read_text(encoding="utf-8")
        group_vars = (PACKAGE_ROOT / "ansible/group_vars/all.yml").read_text(encoding="utf-8")

        self.assertIn("deployment_chart_source_root", group_vars)
        self.assertIn("package_root ~ '/../helm'", group_vars)
        self.assertIn("deployment_chart_source_root", release)
        self.assertIn("deployment_chart_source_root", v9_infra)
        self.assertIn("src: api_gateway", release)
        self.assertIn("dest: api-gateway-service", release)
        self.assertIn("src: core_agent", release)
        self.assertIn("dest: core-agent-service-real", release)
        self.assertNotIn("package_root }}/helm-chart", release)
        self.assertNotIn("package_root }}/helm-chart", v9_infra)

    def test_legacy_packaged_chart_copy_is_not_in_deploy_source(self):
        self.assertFalse((PACKAGE_ROOT / "helm-chart/anybackup-agent").exists())

    def test_remote_chart_copy_removes_stale_chart_files(self):
        release = (PACKAGE_ROOT / "ansible/roles/internal/release/tasks/main.yml").read_text(encoding="utf-8")
        v9_infra = (PACKAGE_ROOT / "ansible/roles/internal/v9_infra/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("Remove stale copied service chart directories", release)
        self.assertIn("state: absent", release)
        self.assertIn("dest: agent-web", release)
        self.assertIn("Remove stale copied v9-infra chart directory", v9_infra)
        self.assertIn("state: absent", v9_infra)


if __name__ == "__main__":
    unittest.main()