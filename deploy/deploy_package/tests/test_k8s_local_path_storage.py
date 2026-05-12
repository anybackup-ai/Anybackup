import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class K8sLocalPathStorageTests(unittest.TestCase):
    def test_preflight_does_not_require_storageclass_before_k8s_bootstrap(self):
        preflight = read_text("ansible/roles/internal/preflight/tasks/main.yml")

        self.assertNotIn("kubectl get storageclass", preflight)
        self.assertNotIn("Required StorageClass", preflight)

    def test_k8s_cluster_installs_local_path_after_cluster_is_ready(self):
        tasks = read_text("ansible/roles/k8s-cluster/tasks/main.yml")
        group_vars = read_text("ansible/group_vars/all.yml")

        ready = tasks.index("Verify Kubernetes has Ready nodes")
        local_path = tasks.index("Check local-path StorageClass exists")
        install = tasks.index("Install local-path provisioner when StorageClass is missing")
        deployment_check = tasks.index("Check local-path provisioner deployment exists")
        availability = tasks.index("Check local-path provisioner availability")
        primary_rollout = tasks.index("Wait for local-path provisioner rollout with primary image")
        fallback_probe = tasks.index("Check local-path fallback image endpoint before switching image")
        fallback_pull = tasks.index("Pull fallback local-path provisioner image before switching")
        fallback_image = tasks.index("Use fallback local-path provisioner image")
        helper_pull = tasks.index("Pull local-path helper image before PVC provisioning")
        helper_config = tasks.index("Configure local-path helper pod image")
        helper_restart = tasks.index("Restart local-path provisioner after helper image change")
        verify = tasks.index("Verify local-path StorageClass is available")

        self.assertLess(ready, local_path)
        self.assertLess(local_path, install)
        self.assertLess(install, deployment_check)
        self.assertLess(deployment_check, availability)
        self.assertLess(availability, primary_rollout)
        self.assertLess(primary_rollout, fallback_probe)
        self.assertLess(fallback_probe, fallback_pull)
        self.assertLess(fallback_pull, fallback_image)
        self.assertLess(fallback_image, helper_pull)
        self.assertLess(helper_pull, helper_config)
        self.assertLess(helper_config, helper_restart)
        self.assertLess(helper_restart, verify)
        self.assertIn("private_image_registry_prefix ~ '/k8s/local-path-provisioner:v0.0.31'", group_vars)
        self.assertIn("private_image_registry_prefix ~ '/thirdparty/busybox:1.36'", group_vars)
        self.assertIn("k8s_cluster_local_path_deployment_check", tasks)
        self.assertIn("k8s_cluster_local_path_available.stdout", tasks)
        self.assertIn("curl -k -sS -o /dev/null -w '%{http_code}'", tasks)
        self.assertIn("ctr -n k8s.io images pull", tasks)
        self.assertIn("helperPod.yaml", tasks)
        self.assertIn("storageclass.kubernetes.io/is-default-class", tasks)


if __name__ == "__main__":
    unittest.main()
