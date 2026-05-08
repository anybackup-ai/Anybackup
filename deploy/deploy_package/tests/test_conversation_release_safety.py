import unittest
from pathlib import Path

DEPLOY_ROOT = Path(__file__).resolve().parents[2]


class ConversationReleaseSafetyTests(unittest.TestCase):
    def test_conversation_secret_is_not_a_helm_hook(self):
        secret = DEPLOY_ROOT / "helm" / "conversation" / "templates" / "secret.yaml"
        text = secret.read_text(encoding="utf-8")

        self.assertIn("kind: Secret", text)
        self.assertIn("meta.helm.sh/release-name", text)
        self.assertIn("meta.helm.sh/release-namespace", text)
        self.assertNotIn("helm.sh/hook", text)
        self.assertNotIn("before-hook-creation", text)

    def test_conversation_release_recovers_pending_helm_state(self):
        tasks = DEPLOY_ROOT / "deploy_package" / "ansible" / "roles" / "internal" / "release" / "tasks" / "main.yml"
        text = tasks.read_text(encoding="utf-8")

        self.assertIn("Recover pending service Helm releases before upgrade", text)
        self.assertIn("pending-upgrade", text)
        self.assertIn("helm rollback", text)
        self.assertIn("conversation-service", text)

    def test_conversation_secret_is_precreated_for_migration_hook(self):
        tasks = DEPLOY_ROOT / "deploy_package" / "ansible" / "roles" / "internal" / "release" / "tasks" / "main.yml"
        text = tasks.read_text(encoding="utf-8")
        task = text.split("- name: Pre-create conversation service Secret for migration hook", 1)[1].split("- name:", 1)[0]

        self.assertIn("--show-only templates/secret.yaml", task)
        self.assertIn("kubectl apply", task)
        self.assertIn("no_log: true", task)


if __name__ == "__main__":
    unittest.main()
