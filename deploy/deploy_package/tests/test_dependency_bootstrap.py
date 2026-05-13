import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class DependencyBootstrapTests(unittest.TestCase):
    def test_install_script_attempts_ansible_auto_install_before_failing(self):
        common = read_text("scripts/lib/ansible-common.sh")

        self.assertIn("attempt_install_ansible_playbook", common)
        self.assertIn("dnf install -y ansible-core", common)
        self.assertIn("yum install -y ansible-core", common)
        self.assertIn("apt-get install -y ansible", common)
        self.assertIn("python3 -m pip install --user ansible", common)
        self.assertIn("ansible-playbook was not found in PATH after automatic install attempts", common)

    def test_tooling_role_installs_docker_and_kweaver_clis_lazily(self):
        tooling = read_text("ansible/roles/internal/tooling/tasks/main.yml")
        deploy_services = read_text("ansible/roles/deploy-services/tasks/main.yml")
        deploy_agent_content = read_text("ansible/roles/deploy-agent-content/tasks/main.yml")

        self.assertIn("Ensure Docker is installed when local image builds are enabled", tooling)
        self.assertIn("business_image_build_enabled | default(false) | bool", tooling)
        self.assertIn("sandbox_overlay_enabled | default(true) | bool", tooling)
        self.assertIn("Ensure curl is installed for deployment tooling", tooling)
        self.assertIn("npm install -g @kweaver-ai/kweaver-sdk", tooling)
        self.assertIn("npm install -g @kweaver-ai/kweaver-admin", tooling)
        self.assertIn("internal/tooling", deploy_services)
        self.assertIn("internal/tooling", deploy_agent_content)


if __name__ == "__main__":
    unittest.main()
