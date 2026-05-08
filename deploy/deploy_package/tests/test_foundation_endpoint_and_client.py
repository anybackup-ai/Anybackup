import pathlib
import unittest


ROOT = pathlib.Path(__file__).resolve().parents[1]


def read_text(relative_path: str) -> str:
    return (ROOT / relative_path).read_text(encoding="utf-8")


class FoundationEndpointAndClientTests(unittest.TestCase):
    def test_install_sh_exposes_foundation_endpoint_and_client_options(self):
        install_sh = read_text("install.sh")

        self.assertIn("FOUNDATION_ACCESS_HOST", install_sh)
        self.assertIn("FOUNDATION_ENDPOINT", install_sh)
        self.assertIn("--foundation-access-host", install_sh)
        self.assertIn("--foundation-endpoint", install_sh)
        self.assertIn("--foundation-package-url", install_sh)
        self.assertIn("--foundation-work-dir", install_sh)
        self.assertIn("--foundation-cli-endpoint", install_sh)
        self.assertIn("--foundation-cli-ak", install_sh)
        self.assertIn("--foundation-cli-sk", install_sh)

        self.assertIn("FOUNDATION_CLIENT_ENABLED", install_sh)
        self.assertIn("--skip-foundation-client", install_sh)
        self.assertIn("--foundation-client-package-url", install_sh)
        self.assertIn("--foundation-client-package-path", install_sh)
        self.assertIn("--foundation-client-install-root", install_sh)
        self.assertIn("--foundation-client-force-reinstall", install_sh)
        self.assertIn("--agent-content-foundation-vega-host", install_sh)
        self.assertIn("--agent-content-foundation-vega-port", install_sh)
        self.assertIn("--agent-content-foundation-vega-username", install_sh)
        self.assertIn("AGENT_CONTENT_FOUNDATION_OPENSEARCH_PASSWORD", install_sh)

    def test_group_vars_define_foundation_endpoint_and_same_host_client_defaults(self):
        group_vars = read_text("ansible/group_vars/all.yml")

        self.assertIn("endpoint_port", group_vars)
        self.assertIn("foundation_endpoint", group_vars)
        self.assertIn("FOUNDATION_CLI_ENDPOINT", group_vars)
        self.assertIn("FoundationServer-Linux_el7_x64-9.0.0.0-alpha1-20260430-release-zh_CN-3.tar.gz", group_vars)
        self.assertIn("/opt/backupsoft", group_vars)
        self.assertIn("package_url", group_vars)
        self.assertIn("skip_kweaver_data_views: \"{{ agent_content_vega_skip_kweaver_data_views | default(false) }}\"", group_vars)

        self.assertIn("foundation_client:", group_vars)
        self.assertIn("arch_dir", group_vars)
        self.assertIn("basic_archive_path", group_vars)
        self.assertIn("mysql_package_filename", group_vars)
        self.assertIn("target_host", group_vars)
        self.assertIn("foundation.access_host", group_vars)
        self.assertIn("default('sdba')", group_vars)
        self.assertIn("AGENT_CONTENT_FOUNDATION_VEGA_PASSWORD", group_vars)
        self.assertIn("    - kweaver", group_vars)
        self.assertNotIn("    - kweave\n", group_vars)

    def test_deploy_services_runs_foundation_client_before_sandbox_overlay(self):
        deploy_services = read_text("ansible/roles/deploy-services/tasks/main.yml")

        foundation = deploy_services.index("Install or verify Foundation")
        foundation_client = deploy_services.index("Install or verify FoundationClient")
        sandbox = deploy_services.index("Overlay foundation-cli into sandbox image")

        self.assertLess(foundation, foundation_client)
        self.assertLess(foundation_client, sandbox)
        self.assertIn("internal/foundation_client", deploy_services)

    def test_deploy_services_installs_etrino_before_foundation_and_agent_content(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        deploy_services = read_text("ansible/roles/deploy-services/tasks/main.yml")
        etrino_role = read_text("ansible/roles/internal/kweaver_etrino_optional/tasks/main.yml")

        kweaver_core = deploy_services.index("Install KWeaver Core from upstream source")
        etrino = deploy_services.index("Install or verify KWeaver Etrino optional services")
        foundation = deploy_services.index("Install or verify Foundation")

        self.assertLess(kweaver_core, etrino)
        self.assertLess(etrino, foundation)
        self.assertIn("kweaver_etrino:", group_vars)
        self.assertIn("scripts/services/etrino.sh", group_vars)
        self.assertIn("Install KWeaver Etrino optional services through official script", etrino_role)
        self.assertIn("NAMESPACE", etrino_role)
        self.assertIn("CONFIG_FILE", etrino_role)
        self.assertIn("kubectl rollout status", etrino_role)

    def test_core_agent_release_injects_foundation_endpoint_and_aksk(self):
        values = read_text("ansible/roles/internal/release/templates/core-agent-real-values.yaml.j2")
        tasks = read_text("ansible/roles/internal/release/tasks/main.yml")
        chart_values = (ROOT.parent / "helm/core_agent/values.yaml").read_text(encoding="utf-8")
        chart_deployment = (ROOT.parent / "helm/core_agent/templates/deployment.yaml").read_text(encoding="utf-8")
        chart_secret = (ROOT.parent / "helm/core_agent/templates/secret.yaml").read_text(encoding="utf-8")

        self.assertIn("foundationEndpoint", values)
        self.assertIn("foundationAk", values)
        self.assertIn("foundationSk", values)
        self.assertIn("effective_kweaver_runtime_base_url | default", values)
        self.assertIn("kweaver_internal_base_url", values)

        self.assertIn("Resolve KWeaver runtime networking for service release", tasks)
        self.assertIn("internal/network_runtime", tasks)
        self.assertIn("Prompt for Foundation CLI AK", tasks)
        self.assertIn("Prompt for Foundation CLI SK", tasks)
        self.assertIn("core_agent_foundation_endpoint_effective", tasks)

        self.assertIn("foundationEndpoint", chart_values)
        self.assertIn("foundationAkKey", chart_values)
        self.assertIn("foundationSkKey", chart_values)
        self.assertIn("FOUNDATION_ENDPOINT", chart_deployment)
        self.assertIn("FOUNDATION_AK", chart_deployment)
        self.assertIn("FOUNDATION_SK", chart_deployment)
        self.assertIn("foundationAkKey", chart_secret)
        self.assertIn("foundationSkKey", chart_secret)

    def test_foundation_client_role_follows_basicrunner_mysql_flow(self):
        role = read_text("ansible/roles/internal/foundation_client/tasks/main.yml")

        self.assertIn("Resolve FoundationClient architecture", role)
        self.assertIn("Linux_el7_x64", role)
        self.assertIn("Basic-", role)
        self.assertIn("-latest.tar.gz', true)", role)
        self.assertIn("FoundationServer to provide", role)
        self.assertIn("MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz", role)
        self.assertIn("foundation_client_effective_arch_dir", role)
        self.assertIn("https://ftp.anybackup.ai/MySQL-Linux_el7_x64-8.0.9.0-20251231-release-zh_CN-ABNormal-378.tar.gz", role)
        self.assertIn("BasicRunner/all_runner_info.config", role)
        self.assertIn("runner_list=MySQL;", role)
        self.assertIn("- bash", role)
        self.assertIn("- ./install.sh", role)
        self.assertIn("client_cli", role)
        self.assertIn("install MySQL", role)
        self.assertIn("- sh", role)

    def test_foundation_opensearch_password_can_come_from_environment(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        self.assertIn("AGENT_CONTENT_FOUNDATION_OPENSEARCH_PASSWORD", group_vars)
        self.assertIn("Prompt for Foundation OpenSearch password when needed", role)
        self.assertIn("echo: false", role)
        self.assertIn("Assert Foundation OpenSearch password is ready", role)
        self.assertIn("agent_content_foundation_opensearch_password", role)

    def test_agent_content_reuses_resolved_kweaver_base_url(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        self.assertIn("agent_content_effective_base_url:", group_vars)
        self.assertIn("agent_content_kweaver_base_url", group_vars)
        self.assertIn("Resolve Agent content KWeaver API base URL", role)
        self.assertIn("kweaver_cli_effective_base_url", role)
        self.assertIn("agent_content_effective_base_url", role)
        self.assertNotIn('--base-url "{{ agent_content.contextloader.base_url }}"', role)

    def test_model_config_task_exports_kweaver_token_for_admin_cli(self):
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        self.assertIn("TOKEN=\"${KWEAVER_ADMIN_TOKEN:-${KWEAVER_TOKEN:-}}\"", role)
        self.assertIn("kweaver token", role)
        self.assertIn("kweaver auth token", role)
        self.assertIn('export KWEAVER_TOKEN="$TOKEN"', role)
        self.assertIn('export KWEAVER_ADMIN_TOKEN="$TOKEN"', role)
        self.assertIn('export KWEAVER_BASE_URL="{{ agent_content_effective_base_url }}"', role)
        self.assertIn('export KWEAVER_BUSINESS_DOMAIN="{{ agent_content.business_domain }}"', role)

    def test_agent_content_grants_required_kweaver_platform_roles(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")
        script = read_text("agent-content/anybackup-agent/kweaver-permissions/ensure-role-membership.sh")

        self.assertIn("ensure_kweaver_role_memberships", group_vars)
        self.assertIn("数据管理员", group_vars)
        self.assertIn("AI管理员", group_vars)
        self.assertIn("应用管理员", group_vars)
        self.assertIn("Ensure KWeaver content deployment user has required platform roles", role)
        self.assertIn("ensure-role-membership.sh", role)
        self.assertIn("kweaver auth whoami --json", script)
        self.assertIn("t_role_member", script)
        self.assertIn("Tokens and", script)

    def test_agent_content_reconciles_bkn_business_domain_binding(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        self.assertIn("bkn_business_domain:", group_vars)
        self.assertIn("business-system-service", group_vars)
        self.assertIn("disable_when_service_absent", group_vars)
        self.assertIn("Reconcile BKN business-domain binding mode", role)
        self.assertIn("BUSINESS_DOMAIN_ENABLED=$desired", role)
        self.assertIn("kubectl rollout status", role)
        self.assertIn("kweaver bkn list", role)

    def test_agent_content_enables_bkn_default_small_model_usage(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        model_config = role.index("Deploy KWeaver LLM and small-model config")
        small_model_cache = role.index("Clear KWeaver small-model runtime cache after model config changes")
        model_api_restart = role.index("Restart KWeaver model API after model config changes")
        small_model = role.index("Enable BKN default small-model usage for ContextLoader")
        backup_bkn = role.index("Deploy backup BKNs with deploy-orchestrator")
        contextloader = role.index("Import ContextLoader toolbox")

        self.assertLess(model_config, small_model_cache)
        self.assertLess(small_model_cache, model_api_restart)
        self.assertLess(model_config, model_api_restart)
        self.assertLess(model_api_restart, small_model)
        self.assertLess(small_model, backup_bkn)
        self.assertLess(small_model, contextloader)
        self.assertIn("bkn_small_model:", group_vars)
        self.assertIn("bkn-backend-cm", group_vars)
        self.assertIn("bkn-backend-config.yaml", group_vars)
        self.assertIn("defaultSmallModelEnabled", role)
        self.assertIn("mf-model-api", role)
        self.assertIn("clear_small_model_cache", group_vars)
        self.assertIn("dip:model-api:small-model:", role)
        self.assertIn("tr -d '\\r'", role)
        self.assertIn("redis-cli", role)
        self.assertIn("warn_small_model_cache_clear_failed", role)
        self.assertIn("failed_when: false", role)
        self.assertIn("ignore_errors: true", role)
        self.assertIn("kubectl patch configmap", role)
        self.assertIn("kubectl rollout restart", role)

    def test_agent_content_reconciles_agent_operator_business_domain_binding(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")
        contextloader = read_text("agent-content/anybackup-agent/context-loader/install.sh")

        self.assertIn("agent_operator_business_domain:", group_vars)
        self.assertIn("agent-operator-integration", group_vars)
        self.assertIn("business-system-service", group_vars)
        self.assertIn("Reconcile Agent operator business-domain binding mode", role)
        self.assertIn("BUSINESS_DOMAIN_ENABLED=$desired", role)
        self.assertIn("reconciled_agent_operator_business_domain_binding", role)
        self.assertIn("CONTEXTLOADER_IMPORT_RETRIES", contextloader)
        self.assertIn("ContextLoader import returned HTTP", contextloader)

    def test_agent_content_reconciles_agent_factory_business_domain_binding(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        reconcile = role.index("Reconcile Agent factory business-domain binding mode")
        deploy_agent = role.index("Deploy Agents from exported KWeaver Agent config")

        self.assertLess(reconcile, deploy_agent)
        self.assertIn("agent_factory_business_domain:", group_vars)
        self.assertIn("agent-factory", group_vars)
        self.assertIn("agent-factory-yaml", group_vars)
        self.assertIn("agent-factory.yaml", group_vars)
        self.assertIn("business-system-service", group_vars)
        self.assertIn("disable_biz_domain", role)
        self.assertIn("kubectl patch configmap", role)
        self.assertIn("kubectl rollout restart", role)
        self.assertIn("reconciled_agent_factory_business_domain_binding", role)
        self.assertIn("when: agent_content.agent_factory_business_domain.reconcile | bool", role)

    def test_agent_content_normalizes_packaged_shell_scripts(self):
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        self.assertIn("Normalize packaged Agent install scripts and make them executable", role)
        self.assertIn("perl -pi -e 's/\\015$//'", role)
        self.assertIn("chmod 0755", role)
        self.assertIn("executable: /bin/bash", role)

    def test_model_config_reuses_kweaver_cli_token_for_admin_calls(self):
        model_config = read_text("agent-content/anybackup-agent/model-config/install.sh")

        self.assertIn("resolve_kweaver_token", model_config)
        self.assertIn("kweaver token", model_config)
        self.assertIn("kweaver auth token", model_config)
        self.assertIn('export KWEAVER_TOKEN="$value"', model_config)
        self.assertIn('"KWEAVER_ADMIN_TOKEN", "KWEAVER_TOKEN"', model_config)

    def test_model_config_uses_role_file_and_environment_secrets(self):
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")
        model_config = read_text("agent-content/anybackup-agent/model-config/install.sh")
        template = read_text("kweaver-llm-config/models.json.template")
        adapter_template = read_text("kweaver-llm-config/small-model/small-model-adapter.txt.template")
        readme = read_text("kweaver-llm-config/README.md")

        self.assertIn("ANYBACKUP_LLM_API_KEY", role)
        self.assertIn("ANYBACKUP_EMBEDDING_API_KEY", role)
        self.assertIn("ANYBACKUP_RERANKER_API_KEY", role)
        self.assertIn("Multiple LLM configs are packaged", model_config)
        self.assertIn("selected_small_model_names", model_config)
        self.assertIn("small-model/edit", model_config)
        self.assertIn('"change": True', model_config)
        self.assertIn("role_api_key", model_config)
        self.assertIn("redact_secrets(model_roles)", model_config)
        self.assertIn("models.json", model_config)
        self.assertIn('"kind": "api"', template)
        self.assertIn('"kind": "adapter"', template)
        self.assertNotIn("source_model_id", template)
        self.assertIn("ANYBACKUP_LLM_API_KEY", template)
        self.assertIn("small-model/small-model-adapter.txt.template", template)
        self.assertNotIn("sk-", template)
        self.assertIn("DASHSCOPE_RERANK_URL", adapter_template)
        self.assertIn("__ANYBACKUP_RERANKER_API_KEY__", adapter_template)
        self.assertNotIn("sk-", adapter_template)
        self.assertIn("model_config", model_config)
        self.assertIn("models.json.template", readme)
        self.assertIn("models.json", readme)
        self.assertIn("客户不需要填写 KWeaver 生成的模型 ID", readme)
        self.assertIn("len(llm_by_id) == 1", read_text("agent-content/anybackup-agent/agent-export/install.sh"))

    def test_recovery_dataviews_create_hyperbackup_by_default(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")
        recovery_vega = read_text("agent-content/anybackup-agent/recovery-install/vega/install.sh")

        self.assertIn("skip_kweaver_data_views: \"{{ agent_content_vega_skip_kweaver_data_views | default(false) }}\"", group_vars)
        self.assertIn("KWEAVER_SKIP_DATA_VIEWS", role)
        self.assertIn("Prompt for Foundation MariaDB password when recovery DataViews need it", role)
        self.assertIn("agent_content_foundation_vega_password_effective", role)
        self.assertIn("HyperBackupMgmServiceDB-protectobject", recovery_vega)
        self.assertIn('--view "protect_object=HyperBackupMgmServiceDB.protect_object"', recovery_vega)

    def test_recovery_dataviews_require_etrino_optional_services(self):
        group_vars = read_text("ansible/group_vars/all.yml")
        role = read_text("ansible/roles/internal/agent_content/tasks/main.yml")

        self.assertIn("require_optional_services_for_dataviews", group_vars)
        self.assertIn("optional_service_workloads", group_vars)
        self.assertIn("vega-calculate-coordinator", group_vars)
        self.assertIn("vega-calculate-worker", group_vars)
        self.assertIn("vega-metadata", group_vars)
        self.assertIn("vega-datanode", group_vars)
        self.assertIn("vega-namenode-master", group_vars)

        self.assertIn("Check KWeaver Etrino optional services before recovery DataViews", role)
        self.assertIn("KWeaver DataView creation requires Etrino optional services", role)
        self.assertIn("deployment statefulset", role)
        self.assertIn("--agent-content-vega-skip-kweaver-data-views true", role)
