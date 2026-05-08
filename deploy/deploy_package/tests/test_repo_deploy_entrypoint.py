import pathlib
import unittest


PACKAGE_ROOT = pathlib.Path(__file__).resolve().parents[1]
DEPLOY_ROOT = PACKAGE_ROOT.parent


class RepoDeployEntrypointTests(unittest.TestCase):
    def test_deploy_install_delegates_to_deploy_package(self):
        text = (DEPLOY_ROOT / "install.sh").read_text(encoding="utf-8")

        self.assertIn("deploy_package/install.sh", text)
        self.assertIn('exec bash "${PACKAGE_INSTALL}" "$@"', text)
        self.assertNotIn("scripts/lib/ansible-common.sh", text)
        self.assertNotIn('ANSIBLE_DIR="${ROOT_DIR}/ansible"', text)

    def test_deploy_uninstall_delegates_to_deploy_package(self):
        text = (DEPLOY_ROOT / "uninstall.sh").read_text(encoding="utf-8")

        self.assertIn("deploy_package/uninstall.sh", text)
        self.assertIn('exec bash "${PACKAGE_UNINSTALL}" "$@"', text)

    def test_full_install_runs_agent_content_before_verify(self):
        text = (PACKAGE_ROOT / "install.sh").read_text(encoding="utf-8")

        deploy_services = text.index("run_stage deploy-services")
        deploy_agent_content = text.index("run_stage deploy-agent-content", deploy_services)
        app_services = text.index("run_stage app-services", deploy_agent_content)
        verify = text.index("run_stage verify", app_services)

        self.assertLess(deploy_services, deploy_agent_content)
        self.assertLess(deploy_agent_content, app_services)
        self.assertLess(app_services, verify)
        self.assertIn('if [[ "${DEPLOYMENT_PROFILE}" == "full" ]]', text)

    def test_business_services_are_released_after_agent_content(self):
        deploy_services = (PACKAGE_ROOT / "ansible/roles/deploy-services/tasks/main.yml").read_text(encoding="utf-8")
        app_services = (PACKAGE_ROOT / "ansible/roles/app-services/tasks/main.yml").read_text(encoding="utf-8")
        site = (PACKAGE_ROOT / "ansible/site.yml").read_text(encoding="utf-8")

        self.assertNotIn("internal/build_import", deploy_services)
        self.assertNotIn("internal/release", deploy_services)
        self.assertIn("internal/build_import", app_services)
        self.assertIn("internal/release", app_services)
        self.assertIn("role: app-services", site)

    def test_agent_content_wrapper_is_static_for_start_at_task_resume(self):
        wrapper = (PACKAGE_ROOT / "ansible/roles/deploy-agent-content/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("ansible.builtin.import_role", wrapper)
        self.assertIn("name: internal/agent_content", wrapper)
        self.assertNotIn("ansible.builtin.include_role", wrapper)


if __name__ == "__main__":
    unittest.main()
