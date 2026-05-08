# KWeaver Model Configuration

AnyBackup uses one LLM role and two small-model roles during integrated
deployment:

- `primary` LLM
- `embedding` small model
- `reranker` small model

The customer-facing non-secret model configuration lives in:

```text
deploy/deploy_package/kweaver-llm-config/models.json
```

Start from the template:

```text
deploy/deploy_package/kweaver-llm-config/models.json.template
```

The bundled DashScope reranker adapter template is:

```text
deploy/deploy_package/kweaver-llm-config/small-model/small-model-adapter.txt.template
```

It must contain all information needed to create one LLM and the two required
small-model roles from scratch, except secrets:

KWeaver's LLM creation command requires these fields:

```bash
kweaver-admin llm add \
  --name <model_name> \
  --series <model_series> \
  --api-model <api_model> \
  --api-base <api_url> \
  --api-key <api_key>
```

Therefore `models.json.llm` must contain:

- `model_name`: maps to `kweaver-admin llm add --name`.
- `model_series`: maps to `--series`.
- `api_url`: maps to `--api-base`.
- `api_model`: maps to `--api-model`.
- `api_key` or `api_key_env`: maps to `--api-key`.

The current KWeaver 0.6.0 model manager API expects `model_config.api_url`
in the request body. Keep this body shape even though the CLI option is named
`--api-base`.

```json
{
  "model_name": "<model_name>",
  "model_series": "<model_series>",
  "model_config": {
    "api_model": "<api_model>",
    "api_url": "<api_url>",
    "api_key": "<api_key>"
  }
}
```

KWeaver's normal small-model creation command requires:

```bash
kweaver-admin small-model add \
  --name <model_name> \
  --type <embedding|reranker> \
  --api-url <api_url> \
  --api-model <api_model> \
  --api-key <api_key> \
  --batch-size <batch_size> \
  --max-tokens <max_tokens> \
  --embedding-dim <embedding_dim>
```

When updating an existing small model and replacing `model_config.api_key`, the
KWeaver Core API also requires `change: true` in the edit body. Without this
flag, Core intentionally preserves the previous key even if a new `api_key` is
included in `model_config`.

Therefore `models.json.small_models.<role>` with `kind: "api"` must contain:

- `model_name`: maps to `kweaver-admin small-model add --name`.
- `model_type`: maps to `--type`, usually `embedding` or `reranker`.
- `api_url`: maps to `--api-url`.
- `api_model`: maps to `--api-model`.
- `api_key` or `api_key_env`: optional for KWeaver CLI but required by most
  real providers.
- `batch_size`, `max_tokens`, `embedding_dim`: optional KWeaver CLI flags with
  defaults; configure them when the provider or exported model requires exact
  values.

`kind: "adapter"` is not a generic KWeaver CLI `small-model add` mode. It is
the current KWeaver adapter-code compatibility path used for non-standard rerank
providers. AnyBackup requires:

- `model_name`
- `model_type`
- `adapter_code_file`
- `api_key` or `api_key_env` when the adapter template contains
  `__ANYBACKUP_RERANKER_API_KEY__`

```json
{
  "version": 1,
  "llm": {
    "role": "primary",
    "model_name": "v9-codingplan",
    "model_series": "others",
    "model_type": "llm",
    "api_url": "https://ark.cn-beijing.volces.com/api/coding/v3/chat/completions",
    "api_model": "deepseek-v3.2",
    "max_model_len": 256,
    "api_key_env": "ANYBACKUP_LLM_API_KEY"
  },
  "small_models": {
    "embedding": {
      "kind": "api",
      "model_name": "embedding",
      "model_type": "embedding",
      "api_url": "https://dashscope.aliyuncs.com/compatible-mode/v1/embeddings",
      "api_model": "text-embedding-v4",
      "batch_size": 10,
      "max_tokens": 8192,
      "embedding_dim": 1024,
      "api_key_env": "ANYBACKUP_EMBEDDING_API_KEY"
    },
    "reranker": {
      "kind": "adapter",
      "model_name": "qwen3-vl-rerank",
      "model_type": "reranker",
      "adapter": true,
      "adapter_code_file": "small-model/small-model-adapter.txt.template",
      "batch_size": 100,
      "api_key_env": "ANYBACKUP_RERANKER_API_KEY"
    }
  }
}
```

Customers do not need to provide KWeaver-generated model IDs from the source
export environment. KWeaver model creation does not require those IDs. The
installer writes an internal role-to-target model map after creating or reusing
models in the target KWeaver environment. Agent import then rewrites exported
LLM references to the single configured target LLM.

Do not package exported KWeaver model snapshots such as `llm/*.json` or
`small-model-list.json`. They are environment-specific exports and are not the
customer deployment source. The customer flow is always:
`models.json.template` -> local ignored `models.json`.

Only one LLM is allowed. Both `embedding` and `reranker` small-model entries are
required.

Model API keys must not be written to JSON, adapter code, docs, values, or
logs. Provide them through process environment before running the installer:

```bash
read -rsp "LLM API key: " ANYBACKUP_LLM_API_KEY; echo
export ANYBACKUP_LLM_API_KEY

read -rsp "Embedding API key: " ANYBACKUP_EMBEDDING_API_KEY; echo
export ANYBACKUP_EMBEDDING_API_KEY

read -rsp "Reranker API key: " ANYBACKUP_RERANKER_API_KEY; echo
export ANYBACKUP_RERANKER_API_KEY
```

Optional model-name overrides:

```bash
export ANYBACKUP_LLM_NAME="v9-codingplan"
export ANYBACKUP_EMBEDDING_MODEL_NAME="embedding"
export ANYBACKUP_RERANKER_MODEL_NAME="qwen3-vl-rerank"
```

For alpha-only local validation, `models.json` also accepts `api_key` directly
inside `llm`, `small_models.embedding`, or `small_models.reranker`. Do not put
real keys in templates, committed files, shared docs, or command examples.

Small-model modes:

- `kind: "api"` uses KWeaver's standard `small-model add` / `small-model edit`
  API. It requires `api_url`, `api_model`, and an `api_key_env`. This is the
  normal path for embedding models and can also be used for reranker models if
  the provider exposes a compatible endpoint.
- `kind: "adapter"` uses adapter code. It requires `adapter_code_file` and
  `api_key_env`. The adapter file must use the placeholder
  `__ANYBACKUP_RERANKER_API_KEY__`; the installer injects the environment value
  in memory before writing the KWeaver adapter record. The package provides a
  DashScope rerank adapter template; ordinary customers only need to fill
  `models.json`, while advanced customers may replace `adapter_code_file` for a
  different provider.

Behavior:

- Existing same-name models are reused and mapped.
- Missing same-name models are created from `models.json`.
- If `ANYBACKUP_EMBEDDING_API_KEY` is set, an existing normal small model is
  updated in place through the KWeaver small-model edit API.
- After model updates, the integrated Ansible flow clears KWeaver small-model
  runtime Redis cache keys for both source and target model names/IDs, then
  restarts `mf-model-api`. This prevents BKN push from reusing a stale
  embedding key during repeated deployments.
- If the reranker uses adapter mode, the configured adapter file must contain
  the placeholder `__ANYBACKUP_RERANKER_API_KEY__`; the installer injects the
  environment value in memory before writing the KWeaver adapter record.
- If a selected model is missing and its key is unavailable or masked, the
  installer fails with a clear message instead of guessing.
