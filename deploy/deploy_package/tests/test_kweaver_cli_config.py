import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class KweaverCliConfigTests(unittest.TestCase):
    def test_auth_use_is_explicitly_global_for_new_cli(self):
        role = (ROOT / "ansible/roles/internal/kweaver_cli_config/tasks/main.yml").read_text(encoding="utf-8")
        task = role.split("- name: Switch KWeaver CLI current platform to local KWeaver", 1)[1]

        self.assertIn("- use", task)
        self.assertIn("- --global", task)


    def test_bkn_api_probe_retries_until_ready(self):
        role = (ROOT / "ansible/roles/internal/kweaver_cli_config/tasks/main.yml").read_text(encoding="utf-8")
        group_vars = (ROOT / "ansible/group_vars/all.yml").read_text(encoding="utf-8")

        task = role.split("- name: Wait for local KWeaver BKN API through CLI", 1)[1]
        self.assertIn("retries:", task)
        self.assertIn("delay:", task)
        self.assertIn("until: kweaver_cli_bkn_probe.rc == 0", task)
        self.assertIn("bkn_api_retries", group_vars)
        self.assertIn("bkn_api_delay_seconds", group_vars)

    def test_expired_cli_token_forces_relogin_before_bkn_probe(self):
        role = (ROOT / "ansible/roles/internal/kweaver_cli_config/tasks/main.yml").read_text(encoding="utf-8")
        usability_task = role.split("- name: Resolve saved KWeaver CLI login usability", 1)[1].split("- name:", 1)[0]
        assert_task = role.split("- name: Stop when local KWeaver platform has no usable login", 1)[1].split("- name:", 1)[0]

        self.assertIn("Token status: expired", usability_task)
        self.assertIn("refresh failed", usability_task)
        self.assertIn("Token status: expired", assert_task)
        self.assertIn("refresh failed", assert_task)

    def test_login_tasks_retry_before_bkn_probe(self):
        role = (ROOT / "ansible/roles/internal/kweaver_cli_config/tasks/main.yml").read_text(encoding="utf-8")
        group_vars = (ROOT / "ansible/group_vars/all.yml").read_text(encoding="utf-8")

        current_login = role.split("- name: Login to local KWeaver platform with current password when needed", 1)[1].split("- name:", 1)[0]
        initial_login = role.split("- name: Login to local KWeaver platform by rotating the initial password when needed", 1)[1].split("- name:", 1)[0]
        self.assertIn("login_retries", current_login)
        self.assertIn("login_delay_seconds", current_login)
        self.assertIn("until: kweaver_cli_current_password_login.rc == 0", current_login)
        self.assertIn("login_retries", initial_login)
        self.assertIn("login_delay_seconds", initial_login)
        self.assertIn("until: kweaver_cli_initial_password_login.rc == 0", initial_login)
        self.assertIn("login_retries", group_vars)
        self.assertIn("login_delay_seconds", group_vars)

    def test_localhost_inventory_does_not_force_localhost_platform_url(self):
        role = (ROOT / "ansible/roles/internal/kweaver_cli_config/tasks/main.yml").read_text(encoding="utf-8")
        task = role.split("- name: Resolve KWeaver CLI target host", 1)[1].split("- name:", 1)[0]

        self.assertIn("'localhost'", task)
        self.assertIn("'127.0.0.1'", task)
        self.assertIn("ansible_default_ipv4.address", task)
        self.assertIn("ternary", task)
        self.assertNotIn(" if ", task)
if __name__ == "__main__":
    unittest.main()
