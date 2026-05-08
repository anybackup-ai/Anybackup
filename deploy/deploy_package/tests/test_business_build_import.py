import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def existing_build_import_roles():
    candidates = [
        ROOT / "ansible/roles/internal/build_import/tasks/main.yml",
        ROOT / ".codex-remote/package-sync-20260501-093132/deploy/deploy_package/ansible/roles/internal/build_import/tasks/main.yml",
        pathlib.Path("E:/Code/Service/Anybackup/deploy/deploy_package/ansible/roles/internal/build_import/tasks/main.yml"),
    ]
    return [path for path in candidates if path.exists()]


class BusinessBuildImportTests(unittest.TestCase):
    def test_agent_web_nginx_template_uses_agent_web_source_dir(self):
        checked = 0
        for path in existing_build_import_roles():
            role = path.read_text(encoding="utf-8")
            if "Ensure agent-web nginx template directory exists" not in role:
                continue

            checked += 1
            nginx_section = role.split("Ensure agent-web nginx template directory exists", 1)[1].split("- name: Build business service images", 1)[0]
            self.assertNotIn("{{ anybackup_repo_root", nginx_section)
            self.assertIn("agent_web_build", nginx_section)
            self.assertIn("source_dir", nginx_section)
            self.assertIn("/ops/nginx", nginx_section)

        self.assertGreater(checked, 0, "No source-based build_import role found to validate.")
    def test_group_vars_define_business_image_build_defaults(self):
        group_vars = (ROOT / "ansible/group_vars/all.yml").read_text(encoding="utf-8")

        self.assertIn("anybackup_repo_root", group_vars)
        self.assertIn("business_image_builds:", group_vars)
        self.assertIn("{{ anybackup_repo_root }}/Agent/service/conversation", group_vars)
        self.assertIn("{{ anybackup_repo_root }}/Agent/service/core_agent", group_vars)
        self.assertIn("{{ anybackup_repo_root }}/Agent/portal", group_vars)
        self.assertIn("image_repository: conversation-service", group_vars)
        self.assertIn("image_repository: core-agent-service", group_vars)
        self.assertIn("image_repository: agent-web", group_vars)

    def test_build_import_fails_clearly_when_business_image_builds_empty(self):
        role = (ROOT / "ansible/roles/internal/build_import/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("Assert business image build list is configured", role)
        self.assertIn("business_image_builds is empty", role)
        self.assertIn("deploy/install.sh", role)

    def test_build_import_imports_images_without_preflight_fact(self):
        role = (ROOT / "ansible/roles/internal/build_import/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("image_import_command | default('', true)", role)
        self.assertIn("k3s ctr images import", role)
        self.assertIn("ctr -n k8s.io images import", role)
        self.assertIn("nerdctl --namespace k8s.io load -i", role)
        self.assertIn("docker load --input", role)
        self.assertIn("No supported cluster image import tool found", role)
