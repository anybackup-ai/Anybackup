# AnyBackup Integrated Deployment Guide

This guide explains how to run the integrated AnyBackup deployment from a complete repository checkout. The deployment entrypoint is:

```text
deploy/install.sh
```

Recommended flow:

1. Prepare the model configuration.
2. Prepare the credentials required during deployment.
3. Run the integrated deployment script.
4. Follow the installer prompts to finish credential input and validation.

## 1. Prepare Model Configuration

AnyBackup Agent uses LLM and small-model resources in KWeaver. Before deployment, copy the model configuration template:

```bash
cd deploy/deploy_package/kweaver-llm-config
cp models.json.template models.json
```

Then edit `models.json` according to the actual model services:

- `llm`: the primary LLM.
- `small_models.embedding`: the embedding model.
- `small_models.reranker`: the reranker model.

The following fields are usually required:

- Model name.
- Model service endpoint.
- Provider-side model name.
- Model credential source.
- Small-model parameters such as embedding dimension, max token count, and batch size.

The `small-model/` directory stores adapter code templates for small models created through the adapter mode. The default reranker model uses:

```text
small-model/small-model-adapter.txt.template
```

For model field details, see:

```text
deploy/deploy_package/kweaver-llm-config/README.md
```

## 2. Prepare Credentials

The deployment may require the following credentials:

| Credential | Purpose | How to provide it |
|---|---|---|
| Model API key | Create or update LLM and small models | Fill it in `models.json`, or provide it through environment variables |
| KWeaver admin password | Log in to KWeaver and configure models, BKN, and Agent | For a new deployment, set the final admin password; for an existing KWeaver environment, provide the current admin password |
| Foundation AK/SK | Allow Agent services to call Foundation capabilities | Obtain it from the Foundation web console, then enter it during deployment |
| Foundation OpenSearch password | Create the KWeaver Vega catalog | Enter it when prompted |
| Foundation database password | Create Foundation DataViews | Enter it when prompted |

There are two ways to provide model API keys.

Option 1: fill them directly in `models.json`. For example:

```json
{
  "llm": {
    "api_key": "<your-llm-api-key>"
  },
  "small_models": {
    "embedding": {
      "api_key": "<your-embedding-api-key>"
    },
    "reranker": {
      "api_key": "<your-reranker-api-key>"
    }
  }
}
```

Option 2: keep `api_key_env` in `models.json`, and set environment variables in the terminal:

```bash
read -rsp "LLM API key: " ANYBACKUP_LLM_API_KEY; echo
export ANYBACKUP_LLM_API_KEY

read -rsp "Embedding API key: " ANYBACKUP_EMBEDDING_API_KEY; echo
export ANYBACKUP_EMBEDDING_API_KEY

read -rsp "Reranker API key: " ANYBACKUP_RERANKER_API_KEY; echo
export ANYBACKUP_RERANKER_API_KEY
```

Choose either method. Environment variables are useful when the API keys should not be written into the configuration file.

To provide the KWeaver admin password before running the installer:

```bash
read -rsp "KWeaver password: " KWEAVER_CLI_PASSWORD; echo
export KWEAVER_CLI_PASSWORD
```

This password is not the KWeaver default password.

For a new integrated deployment, KWeaver admin has an initial password. The installer uses its built-in initial password to complete the first login and the required password change. The value provided here is the final admin password after deployment, namely `KWEAVER_CLI_PASSWORD`.

For an existing KWeaver environment, provide the current usable admin password.

Foundation AK/SK must be obtained from the Foundation web console after Foundation is installed. After obtaining them, they can be entered before continuing the deployment:

```bash
read -rsp "Foundation AK: " FOUNDATION_CLI_AK; echo
export FOUNDATION_CLI_AK

read -rsp "Foundation SK: " FOUNDATION_CLI_SK; echo
export FOUNDATION_CLI_SK
```

They can also be left unset. The installer will pause and prompt for hidden input when they are required.

## 3. Run Integrated Deployment

Enter the `deploy` directory and run the installer:

```bash
cd deploy
./install.sh \
  --local \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip>
```

### Common Install Options

The integrated deployment entrypoint is:

```bash
./install.sh [options]
```

Common options:

| Option | Commonly used | Description |
|---|---|---|
| `--local` | Yes | Run a single-node deployment on the current host. No additional inventory is required. |
| `--inventory <path>` | Optional | Use a specified inventory file. This is suitable when the target host inventory is already prepared. Usually choose either `--local` or `--inventory`. |
| `--foundation-mode integrated` | Yes | Deploy Foundation, KWeaver, and Agent services on the same host. |
| `--foundation-mode separated` | Optional | Deploy Foundation on a separate host. A reachable Foundation address must also be provided. |
| `--foundation-mode external` | Optional | Use an existing Foundation environment and only configure access addresses and credentials. |
| `--foundation-self-ip <ip>` | Yes | The local IP used by Foundation installation. In `integrated` mode, this is usually the private IP of the current deployment host. |
| `--foundation-access-host <host>` | Optional | The address used by Agent, KWeaver DataView, and FoundationClient to access Foundation. Use it when Foundation is not on the current host, or when the access address is different from `foundation-self-ip`. |
| `--foundation-endpoint <url>` | Optional | Foundation control-plane endpoint. If omitted, it is usually generated as `https://<foundation-access-host>:9600`. |
| `--foundation-cli-endpoint <url>` | Optional | Foundation control-plane endpoint passed to Agent services. In most cases this does not need to be specified separately. |
| `--foundation-cli-ak <ak>` | Optional | Foundation AK. It is recommended to enter it when prompted during installation, or provide it through `FOUNDATION_CLI_AK`. |
| `--foundation-cli-sk <sk>` | Optional | Foundation SK. It is recommended to enter it when prompted during installation, or provide it through `FOUNDATION_CLI_SK`. |
| `--foundation-package-path <path>` | Optional | Path to an existing Foundation installation package on the target host. Usually not required, unless the deployment is offline or the package has already been staged in a specific location. |
| `--foundation-package-url <url>` | Optional | URL for downloading the Foundation installation package. Usually not required, unless an internal mirror or custom download address is used. |
| `--kweaver-cli-username <user>` | Optional | KWeaver login username. If omitted, the default administrator account is used. |
| `--kweaver-cli-password <password>` | Yes | KWeaver admin password. For a new deployment, set the final admin password after deployment. For an existing KWeaver environment, provide the current usable admin password. |
| `--kweaver-cli-new-password <password>` | Optional | New password to set when KWeaver requires a first-login password change. Usually not specified separately; if omitted, the value of `--kweaver-cli-password` is used. |
| `--kweaver-cli-initial-password <password>` | Optional | Initial KWeaver admin password. Usually not required. Specify it only when the delivery environment uses an initial password different from the installer built-in value. |

Example:

```bash
cd /root/anybackup-deploy/Anybackup-current/deploy

LOG="/root/anybackup-deploy/releases/install-$(date +%Y%m%d-%H%M%S).log"
mkdir -p /root/anybackup-deploy/releases

bash ./install.sh \
  --local \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip> \
  --kweaver-cli-password '<kweaver-admin-password>' \
  2>&1 | tee "$LOG"
```

In this command:

- `cd .../deploy`: enter the deployment entrypoint directory.
- `LOG=...` and `tee "$LOG"`: show installation output in the terminal and save it to a log file.
- `mkdir -p .../releases`: create the log directory.
- `--local`: deploy on the current host.
- `--foundation-mode integrated`: install Foundation and the Agent runtime on the same host.
- `--foundation-self-ip`: set the IP used by Foundation services on the current host.
- `--kweaver-cli-password`: set the KWeaver admin password. For a new deployment, this is the final admin password after deployment. For an existing KWeaver environment, this is the current login password for admin.

Usually, `--kweaver-cli-new-password` does not need to be specified in the command. If it is omitted, the installer uses the value of `--kweaver-cli-password` as the admin password after the first-login password change. Specify `--kweaver-cli-new-password` only when the current login password and the new password must be different.

If the KWeaver password should not appear in the command line, enter it in the terminal first:

```bash
read -rsp "KWeaver password: " KWEAVER_CLI_PASSWORD; echo
export KWEAVER_CLI_PASSWORD

bash ./install.sh \
  --local \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip> \
  2>&1 | tee "$LOG"
```

To use an inventory file:

```bash
cd deploy
./install.sh \
  --inventory deploy_package/ansible/inventory.ini \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip>
```

## 4. Foundation Deployment Modes

`--foundation-mode` supports three modes:

| Mode | Description |
|---|---|
| `integrated` | Foundation, KWeaver, and Agent services are deployed on the same host |
| `separated` | Foundation is deployed on a separate host |
| `external` | An existing Foundation environment is used; only access addresses and credentials are configured |

`integrated` mode requires:

```text
--foundation-self-ip <foundation-private-ip>
```

In `separated` or `external` mode, make sure the installer can access Foundation, and provide Foundation AK/SK when required.

## 5. What the Installer Does

The integrated deployment completes the following steps in order:

1. Prepare or verify the Kubernetes base environment.
2. Deploy base infrastructure components.
3. Deploy KWeaver.
4. Deploy or verify Foundation.
5. Deploy FoundationClient.
6. Configure KWeaver models.
7. Import knowledge-base data and data connections.
8. Deploy BKN, ContextLoader, skills, and Agent.
9. Publish AnyBackup business services. Service images are pulled from the configured registry by default.
10. Publish the Web access entrypoint.
11. Run post-deployment validation.

If extra credentials are required during installation, the script prompts for them at the corresponding step.

## 6. Access After Deployment

After deployment, the external entrypoint is AnyBackup Web. Backend services are accessed inside the cluster by default and are not directly exposed externally.

Use the following commands to check the overall status:

```bash
kubectl get pods -A
helm list -A
```

The installation log can also be used to confirm whether each stage has completed.

## 7. Redeploy or Uninstall

To redeploy, first run the uninstall script to clean up resources created by the current deployment:

```bash
cd deploy
./uninstall.sh
```

The uninstall script keeps Kubernetes itself and removes runtime resources created by the AnyBackup integrated deployment. After cleanup, run `deploy/install.sh` again.
