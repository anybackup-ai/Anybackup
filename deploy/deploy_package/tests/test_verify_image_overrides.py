import unittest
from pathlib import Path

DEPLOY_ROOT = Path(__file__).resolve().parents[2]


class VerifyImageOverridesTests(unittest.TestCase):
    def test_verify_uses_bracket_access_for_items_key(self):
        verify = DEPLOY_ROOT / "deploy_package" / "ansible" / "roles" / "internal" / "verify" / "tasks" / "main.yml"
        text = verify.read_text(encoding="utf-8")

        self.assertIn("kweaver_image_overrides['items']", text)
        self.assertNotIn("kweaver_image_overrides.items", text)


if __name__ == "__main__":
    unittest.main()