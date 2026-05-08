import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class FoundationInstallIdempotenceTests(unittest.TestCase):
    def test_foundation_install_downloads_default_package_when_missing(self):
        role = (ROOT / "ansible/roles/internal/foundation_install/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("foundation_effective_package_url", role)
        self.assertIn("foundation_effective_package_pattern", role)
        self.assertIn("Resolve Foundation package archive from explicit path or default pattern", role)
        self.assertIn("FoundationServer-Linux_el7_x64-9.0.0.0*.tar.gz", role)
        self.assertIn("find \"$work_dir\" -maxdepth 1 -type f -name \"$pattern\"", role)
        self.assertIn("Download Foundation package when missing", role)
        self.assertIn("ansible.builtin.get_url", role)
    def test_foundation_install_detects_cluster_service_before_installing(self):
        role = (ROOT / "ansible/roles/internal/foundation_install/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("Detect existing Foundation ClusterService", role)
        self.assertIn("/etc/init.d/ClusterService", role)
        self.assertIn("systemctl list-unit-files", role)
        self.assertIn("foundation_existing_install_detected", role)
        self.assertIn("foundation_existing_install_reason", role)

    def test_foundation_install_treats_installer_cluster_service_error_as_existing(self):
        role = (ROOT / "ansible/roles/internal/foundation_install/tasks/main.yml").read_text(encoding="utf-8")

        self.assertIn("ClusterService already exists", role)
        self.assertIn("failed_when", role)
        self.assertIn("Report Foundation installer found existing ClusterService", role)
        self.assertIn("foundation_install_result.rc == 0", role)

    def test_existing_self_ip_validation_requires_install_cfg(self):
        role = (ROOT / "ansible/roles/internal/foundation_install/tasks/main.yml").read_text(encoding="utf-8")
        task = role.split("- name: Validate existing Foundation self IP", 1)[1].split("- name: Stop when Foundation force reinstall", 1)[0]

        self.assertIn("foundation_install_cfg_stat.stat.exists | default(false)", task)


if __name__ == "__main__":
    unittest.main()