import pathlib
import unittest


DEPLOY_ROOT = pathlib.Path(__file__).resolve().parents[2]


def read_text(relative_path: str) -> str:
    return (DEPLOY_ROOT / relative_path).read_text(encoding="utf-8")


class AuthRealmConfigJobTests(unittest.TestCase):
    def test_realm_config_job_uses_forwarded_https_admin_rest(self):
        job = read_text("helm/auth/templates/realm-config-job.yaml")
        values = read_text("helm/auth/values.yaml")

        self.assertNotIn("kcadm.sh config credentials", job)
        self.assertIn("X-Forwarded-Proto", job)
        self.assertIn('"https"', job)
        self.assertIn("protocol/openid-connect/token", job)
        self.assertIn("/admin/realms/", job)
        self.assertIn("urllib.request", job)
        self.assertIn(".Values.keycloak.realmConfig.image", job)
        self.assertIn("realmConfig:", values)
        self.assertIn("repository: base/python", values)


if __name__ == "__main__":
    unittest.main()
