import pathlib
import unittest


DEPLOY_ROOT = pathlib.Path(__file__).resolve().parents[2]


class DeployTmpHygieneTests(unittest.TestCase):
    def test_tmp_directory_is_ignored_and_package_script_excludes_it(self):
        gitignore = (DEPLOY_ROOT / ".gitignore").read_text(encoding="utf-8")
        package_script = (DEPLOY_ROOT / "package-repo.sh").read_text(encoding="utf-8")

        self.assertIn("/tmp/", gitignore)
        self.assertIn("Anybackup/deploy/tmp", package_script)
        self.assertIn("Anybackup/.git", package_script)

    def test_large_runtime_archives_do_not_live_in_deploy_source_paths(self):
        forbidden = [
            DEPLOY_ROOT / "anybackup-deploy-package-20260506-235740.tar",
            DEPLOY_ROOT / "anybackup-deploy-temp-20260430-205144.tar",
            DEPLOY_ROOT / "anybackup-deploy-temp-20260430-205910.tar",
            DEPLOY_ROOT / "deploy_package/images/api-gateway-service-traefik-v3.6.13.tar",
            DEPLOY_ROOT / "deploy_package/images/auth-service-keycloak-26.5.1.tar",
            DEPLOY_ROOT / "deploy_package/images/conversation-service-alpha1.tar",
            DEPLOY_ROOT / "deploy_package/images/core-agent-service-alpha1.tar",
            DEPLOY_ROOT / "deploy_package/images/web-service-alpha1.tar",
            DEPLOY_ROOT / "deploy_package/helm-chart/anybackup-agent/charts/core-agent-service-real/core-agent-service.tar",
            DEPLOY_ROOT / "helm/core_agent/core-agent-service.tar",
            DEPLOY_ROOT / "helm/web/web-service-0.1.0-local-20260425-2207-codex.tar",
        ]

        existing = [str(path) for path in forbidden if path.exists()]
        self.assertEqual([], existing)


if __name__ == "__main__":
    unittest.main()