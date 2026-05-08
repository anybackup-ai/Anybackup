# KWeaver 模型配置说明

这个目录是 AnyBackup Agent 一体化部署时的模型配置入口。部署脚本会读取本目录下的：

```text
models.json
```

注意：`models.json.template` 只是模板文件，部署脚本不会直接读取它。用户在执行
`deploy/install.sh` 前，必须先复制或重命名模板，生成本地真实配置文件：

```bash
cd deploy/deploy_package/kweaver-llm-config
cp models.json.template models.json
```

然后编辑 `models.json`，填入当前客户环境实际使用的大模型和小模型信息。

## 需要配置的模型

当前 AnyBackup Agent 部署要求配置：

- 1 个大模型：`llm`
- 1 个 embedding 小模型：`small_models.embedding`
- 1 个 reranker 小模型：`small_models.reranker`

也就是说，客户不需要在部署时选择多个 LLM。当前一体化部署主路径是：

```text
一个主 LLM + 一个 embedding 小模型 + 一个 reranker 小模型
```

## 大模型字段

`models.json.llm` 至少需要填写：

- `model_name`：在目标 KWeaver 环境中创建或复用的大模型名称。
- `model_series`：KWeaver 模型系列，例如 `others`。
- `api_url`：模型供应商的接口地址。
- `api_model`：模型供应商侧的模型名称。
- `api_key` 或 `api_key_env`：模型访问凭证。

生产环境建议使用 `api_key_env`，部署前通过环境变量注入 key。Alpha 验证阶段可以直接在
`models.json` 中填写 `api_key`，但 `models.json` 不能提交到代码仓库。

## 小模型字段

`models.json.small_models.embedding` 和 `models.json.small_models.reranker`
至少需要填写：

- `model_name`：在目标 KWeaver 环境中创建或复用的小模型名称。
- `model_type`：通常是 `embedding` 或 `reranker`。
- `kind`：小模型创建方式。
- `api_key` 或 `api_key_env`：模型访问凭证。

当 `kind` 为 `api` 时，表示使用 KWeaver 标准小模型 API 创建或更新模型，还需要填写：

- `api_url`
- `api_model`
- `batch_size`
- `max_tokens`
- `embedding_dim`

当 `kind` 为 `adapter` 时，表示通过 adapter 代码创建或更新小模型，还需要填写：

- `adapter_code_file`
- `batch_size`

## small-model 目录的用途

本目录下的：

```text
small-model/
```

专门用于存放通过 adapter 方式创建小模型时需要的 adapter 代码模板。

当前默认提供：

```text
small-model/small-model-adapter.txt.template
```

这个文件用于 reranker 小模型的 adapter 模式。普通 `kind: "api"` 的小模型不需要在
`small-model/` 下面放 JSON 文件，直接在 `models.json` 里配置即可。

如果继续使用默认 adapter 模板，`models.json` 中保持如下配置即可：

```json
{
  "kind": "adapter",
  "adapter_code_file": "small-model/small-model-adapter.txt.template"
}
```

adapter 模板中必须保留占位符：

```text
__ANYBACKUP_RERANKER_API_KEY__
```

部署脚本会在运行时从 `models.json` 或 `ANYBACKUP_RERANKER_API_KEY` 取值，并把 key 注入到
adapter 代码中，再写入 KWeaver。不要把真实 key 写进 adapter 模板文件。

## 推荐的凭证输入方式

生产环境建议在运行一体化部署脚本前，通过隐藏输入设置环境变量：

```bash
read -rsp "LLM API key: " ANYBACKUP_LLM_API_KEY; echo
export ANYBACKUP_LLM_API_KEY

read -rsp "Embedding API key: " ANYBACKUP_EMBEDDING_API_KEY; echo
export ANYBACKUP_EMBEDDING_API_KEY

read -rsp "Reranker API key: " ANYBACKUP_RERANKER_API_KEY; echo
export ANYBACKUP_RERANKER_API_KEY
```

然后在 `models.json` 中保留：

```json
{
  "api_key": "",
  "api_key_env": "ANYBACKUP_LLM_API_KEY"
}
```

对应 embedding 和 reranker 也使用各自的 `api_key_env`。

## 不要提交的文件

以下文件属于客户本地部署输入或临时导出物，不要提交到代码仓库：

```text
models.json
llm/
small-model/small-model-list.json
small-model/small-model-adapter.txt
```

仓库中只应该保留模板和说明文档：

```text
README.md
models.json.template
small-model/small-model-adapter.txt.template
```

## 关于模型 ID

客户不需要填写 KWeaver 生成的模型 ID，也不需要填写 Agent 导出环境里的旧模型 ID。

KWeaver 创建大模型和小模型时不需要这些旧 ID。部署脚本会在模型创建或复用完成后生成内部映射，并在导入 Agent 时按当前“一个主 LLM”的规则自动替换模型引用。

一句话：用户部署前先把 `models.json.template` 复制成 `models.json`，填好模型信息和凭证来源，然后再执行一体化部署脚本。
