from pathlib import Path
import unittest


ROOT = Path(__file__).resolve().parents[1]


class AgUiResponseSkillDeploymentTest(unittest.TestCase):
    def test_ag_ui_response_skill_is_packaged_as_skill_directory(self):
        skill_dir = ROOT / "agent-content" / "anybackup-agent" / "foundation-cli-skills" / "skills" / "ag-ui-response"

        self.assertTrue((skill_dir / "SKILL.md").is_file())
        self.assertIn("name: ag-ui-response", (skill_dir / "SKILL.md").read_text(encoding="utf-8"))
        self.assertTrue((skill_dir / "scripts" / "ag_ui_mq_core.py").is_file())
        self.assertIn("aio-pika>=9.5.0", (skill_dir / "requirements.txt").read_text(encoding="utf-8"))


    def test_group_vars_imports_ag_ui_skill_and_dependency_defaults(self):
        text = (ROOT / "ansible" / "group_vars" / "all.yml").read_text(encoding="utf-8")

        self.assertIn("agent-content/anybackup-agent/foundation-cli-skills/skills/ag-ui-response", text)
        self.assertIn("deploy_skill_dependencies", text)
        self.assertIn("pypi.tuna.tsinghua.edu.cn/simple", text)


    def test_agent_content_installs_skill_dependencies_after_skill_import(self):
        text = (
            ROOT
            / "ansible"
            / "roles"
            / "internal"
            / "agent_content"
            / "tasks"
            / "main.yml"
        ).read_text(encoding="utf-8")

        skill_import = text.index("- name: Import Foundation CLI skills")
        dependency_install = text.index("- name: Install Python dependencies for sandbox skills")
        agent_export = text.index("- name: Check packaged Agent export config exists")

        self.assertLess(skill_import, dependency_install)
        self.assertLess(dependency_install, agent_export)
        self.assertIn("skill-dependencies/install.sh", text)
        self.assertIn("agent_content.skill_dependencies", text)


    def test_skill_dependency_installer_uses_sandbox_dependency_api(self):
        installer = (
            ROOT
            / "agent-content"
            / "anybackup-agent"
            / "skill-dependencies"
            / "install.sh"
        ).read_text(encoding="utf-8")

        self.assertIn("/dependencies/install", installer)
        self.assertIn("requirements.txt", installer)
        self.assertIn("python_package_index_url", installer)
        self.assertIn("sandbox-control-plane", installer)


    def test_install_sh_exposes_skill_dependency_controls(self):
        text = (ROOT / "install.sh").read_text(encoding="utf-8")

        self.assertIn("--agent-content-deploy-skill-dependencies", text)
        self.assertIn("--agent-content-skill-dependencies-session-id", text)
        self.assertIn("--agent-content-skill-dependencies-python-package-index-url", text)
        self.assertIn("agent_content_deploy_skill_dependencies", text)
        self.assertIn("agent_content_skill_dependencies_python_package_index_url", text)


if __name__ == "__main__":
    unittest.main()
