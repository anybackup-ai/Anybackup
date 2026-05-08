import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


class SandboxOverlayTests(unittest.TestCase):
    def test_dockerfile_avoids_copy_chmod_for_old_docker(self):
        role = (ROOT / "ansible/roles/internal/sandbox_overlay/tasks/main.yml").read_text(encoding="utf-8")

        dockerfile_block = role.split("Render sandbox overlay Dockerfile", 1)[1].split("- name: Print sandbox overlay summary", 1)[0]

        self.assertIn("FROM {{ sandbox_image_resolved }}", dockerfile_block)
        self.assertIn("USER root", dockerfile_block)
        self.assertIn("COPY foundation-cli /usr/local/bin/foundation-cli", dockerfile_block)
        self.assertIn("RUN chmod 0755 /usr/local/bin/foundation-cli", dockerfile_block)
        self.assertNotIn("COPY --chmod", dockerfile_block)


if __name__ == "__main__":
    unittest.main()