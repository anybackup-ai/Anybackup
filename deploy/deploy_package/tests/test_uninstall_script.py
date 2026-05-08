import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class UninstallScriptTests(unittest.TestCase):
    def test_uninstall_script_exists_next_to_install_script(self):
        uninstall = ROOT / "uninstall.sh"

        self.assertTrue(uninstall.exists(), "uninstall.sh should live next to install.sh")

    def test_uninstall_script_keeps_kubernetes_and_requires_yes(self):
        uninstall = (ROOT / "uninstall.sh").read_text(encoding="utf-8")

        self.assertIn("DRY_RUN=true", uninstall)
        self.assertIn("--yes", uninstall)
        self.assertIn("destructive uninstall requires --yes", uninstall)
        self.assertIn("kube-system", uninstall)
        self.assertIn("local-path-storage", uninstall)
        self.assertIn("KEEP_K8S_NAMESPACES", uninstall)
        self.assertNotIn("kubectl delete namespace kube-system", uninstall)
        self.assertNotIn("kubectl delete namespace kube-flannel", uninstall)
        self.assertNotIn("kubectl delete namespace local-path-storage", uninstall)

    def test_uninstall_script_cleans_package_owned_resources(self):
        uninstall = (ROOT / "uninstall.sh").read_text(encoding="utf-8")

        for namespace in ["anybackup-ai", "kweaver", "resource", "v9-system", "ingress-nginx", "middleware"]:
            self.assertIn(namespace, uninstall)

        for path in ["/opt/v9-alpha-deploy", "/opt/v9-sources", "/root/.kweaver", "/root/.kweaver-admin"]:
            self.assertIn(path, uninstall)

        self.assertIn("helm uninstall", uninstall)
        self.assertIn("kubectl delete namespace", uninstall)
        self.assertIn("./uninstall.sh", uninstall)
        self.assertIn("FOUNDATION_INSTALL_ROOT", uninstall)
        self.assertIn("FoundationClient", uninstall)
        self.assertIn("safe_remove_path \"${FOUNDATION_INSTALL_ROOT}\"", uninstall)
        self.assertIn("safe_remove_path \"${FOUNDATION_CLIENT_INSTALL_ROOT}\"", uninstall)
        self.assertIn("remove_systemd_unit ABClientService.service", uninstall)
        self.assertIn("Foundation official uninstall failed; continue removing FoundationServer root.", uninstall)
        self.assertIn("FoundationClient uninstall script failed; continue removing service and root.", uninstall)
        self.assertIn("systemctl daemon-reload", uninstall)


if __name__ == "__main__":
    unittest.main()
