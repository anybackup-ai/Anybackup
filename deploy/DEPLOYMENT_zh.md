# Anybackup 一体化部署指南

本文说明如何从完整仓库执行 Anybackup 一体化部署。部署入口位于：

```text
deploy/install.sh
```

推荐流程是：

1. 准备模型配置。
2. 准备部署过程中需要的凭证。
3. 执行一体化部署脚本。
4. 按安装程序提示完成后续输入和验证。

## 1. 准备模型配置

Anybackup Agent 需要使用 KWeaver 中的大模型和小模型。部署前先复制模型配置模板：

```bash
cd deploy/deploy_package/kweaver-llm-config
cp models.json.template models.json
```

然后编辑 `models.json`，按实际模型服务填写：

- `llm`：大模型。
- `small_models.embedding`：向量化小模型。
- `small_models.reranker`：重排小模型。

通常需要填写的内容包括：

- 模型名称。
- 模型服务接口地址。
- 供应商侧模型名。
- 模型访问凭证来源。
- embedding 维度、最大 token 数、批大小等小模型参数。

`small-model/` 目录用于保存 adapter 方式创建小模型时使用的 adapter 代码模板。默认 reranker 小模型使用：

```text
small-model/small-model-adapter.txt.template
```

模型字段说明见：

```text
deploy/deploy_package/kweaver-llm-config/README.md
```

## 2. 准备凭证

部署过程中可能需要以下凭证：

| 凭证 | 用途 | 提供方式 |
|---|---|---|
| 模型 API key | 创建或更新大模型、小模型 | 可填写在 `models.json`，也可使用环境变量 |
| KWeaver admin 密码 | 登录 KWeaver 并完成模型、BKN、Agent 配置 | 全新部署时指定最终密码；已有环境填写当前密码 |
| Foundation AK/SK | Agent 调用 Foundation 能力 | Foundation 页面获取，安装时输入 |
| Foundation OpenSearch 密码 | 创建 KWeaver Vega catalog | 安装时按提示输入 |
| Foundation 数据库密码 | 创建 Foundation DataView | 安装时按提示输入 |

模型 API key 有两种提供方式。

方式一：直接填写在 `models.json` 中。例如：

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

方式二：在 `models.json` 中保留 `api_key_env`，并在终端中设置环境变量：

```bash
read -rsp "LLM API key: " ANYBACKUP_LLM_API_KEY; echo
export ANYBACKUP_LLM_API_KEY

read -rsp "Embedding API key: " ANYBACKUP_EMBEDDING_API_KEY; echo
export ANYBACKUP_EMBEDDING_API_KEY

read -rsp "Reranker API key: " ANYBACKUP_RERANKER_API_KEY; echo
export ANYBACKUP_RERANKER_API_KEY
```

两种方式任选一种即可。环境变量方式适合不希望把 key 写入配置文件的场景。

如果需要提前提供 KWeaver admin 密码，可以使用：

```bash
read -rsp "KWeaver password: " KWEAVER_CLI_PASSWORD; echo
export KWEAVER_CLI_PASSWORD
```

这里的密码不是 KWeaver 的默认密码。

全新一体化部署时，KWeaver admin 存在初始密码，安装程序会使用内置初始密码完成首次登录和必要的改密。这里需要提供的是部署完成后 admin 使用的最终密码，也就是上面的 `KWEAVER_CLI_PASSWORD`。

如果目标环境已经存在 KWeaver，则填写该环境当前可用的 admin 密码。

Foundation AK/SK 需要在 Foundation 安装完成后登录 Foundation 页面获取。获取后可以在继续安装前输入：

```bash
read -rsp "Foundation AK: " FOUNDATION_CLI_AK; echo
export FOUNDATION_CLI_AK

read -rsp "Foundation SK: " FOUNDATION_CLI_SK; echo
export FOUNDATION_CLI_SK
```

也可以不提前设置，安装程序会在需要时暂停并隐藏输入。

## 3. 执行一体化部署

进入 `deploy` 目录执行安装：

```bash
cd deploy
./install.sh \
  --local \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip>
```

### 常用安装选项

一体化部署入口是：

```bash
./install.sh [选项]
```

常用选项如下。

| 选项 | 是否常用 | 说明 |
|---|---|---|
| `--local` | 常用 | 在当前主机执行单节点部署，不需要额外 inventory。 |
| `--inventory <path>` | 可选 | 使用指定 inventory 部署。适合已经准备好目标主机清单的环境。`--local` 和 `--inventory` 通常二选一。 |
| `--foundation-mode integrated` | 常用 | Foundation 与 KWeaver、Agent 服务部署在同一台主机上。 |
| `--foundation-mode separated` | 可选 | Foundation 部署在另一台主机上。需要同时提供可访问的 Foundation 地址。 |
| `--foundation-mode external` | 可选 | 使用已经存在的 Foundation，只配置访问地址和凭证。 |
| `--foundation-self-ip <ip>` | 常用 | Foundation 安装时使用的本机 IP。`integrated` 模式下通常填写当前部署主机的内网 IP。 |
| `--foundation-access-host <host>` | 可选 | Agent、KWeaver DataView 和 FoundationClient 访问 Foundation 时使用的地址。Foundation 不在当前主机上，或访问地址不同于 `foundation-self-ip` 时填写。 |
| `--foundation-endpoint <url>` | 可选 | Foundation 控制面访问地址。未指定时通常按 `https://<foundation-access-host>:9600` 生成。 |
| `--foundation-cli-endpoint <url>` | 可选 | 传递给 Agent 服务使用的 Foundation 控制面地址。多数情况下不需要单独指定。 |
| `--foundation-cli-ak <ak>` | 可选 | Foundation AK。更推荐在安装过程中按提示输入，或使用环境变量 `FOUNDATION_CLI_AK`。 |
| `--foundation-cli-sk <sk>` | 可选 | Foundation SK。更推荐在安装过程中按提示输入，或使用环境变量 `FOUNDATION_CLI_SK`。 |
| `--foundation-package-path <path>` | 可选 | 指定目标主机上已有的 Foundation 安装包路径。一般不需要指定，只有离线安装或包已预置到特定路径时使用。 |
| `--foundation-package-url <url>` | 可选 | 指定 Foundation 安装包下载地址。一般不需要指定，只有需要使用内部镜像源或自有下载地址时使用。 |
| `--kweaver-cli-username <user>` | 可选 | KWeaver 登录用户名。未指定时使用默认管理员用户。 |
| `--kweaver-cli-password <password>` | 常用 | KWeaver admin 密码。全新部署时填写希望部署完成后 admin 使用的最终密码；已有 KWeaver 环境时填写当前可用的 admin 密码。 |
| `--kweaver-cli-new-password <password>` | 可选 | KWeaver 首次登录需要改密时要设置的新密码。一般不需要单独填写；未指定时会使用 `--kweaver-cli-password` 的值。 |
| `--kweaver-cli-initial-password <password>` | 可选 | KWeaver admin 初始密码。通常不需要填写；只有交付环境的初始密码与安装程序内置值不一致时才需要指定。 |

例如：

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

这条命令中：

- `cd .../deploy`：进入部署入口目录。
- `LOG=...` 和 `tee "$LOG"`：把安装输出同时显示在终端并保存到日志文件。
- `mkdir -p .../releases`：创建日志目录。
- `--local`：表示部署当前这台机器。
- `--foundation-mode integrated`：表示 Foundation 和 Agent 运行环境安装在同一台机器。
- `--foundation-self-ip`：填写当前机器用于 Foundation 服务的 IP。
- `--kweaver-cli-password`：填写 KWeaver admin 密码。全新部署时，这是部署完成后 admin 使用的最终密码；已有 KWeaver 环境时，这是当前可登录的 admin 密码。

一般不需要在命令中单独填写 `--kweaver-cli-new-password`。未指定时，安装程序会使用 `--kweaver-cli-password` 的值作为首次改密后的 admin 密码。只有需要把“当前可登录密码”和“首次改密后的密码”分成两个不同值时，才单独指定 `--kweaver-cli-new-password`。

如果不希望把 KWeaver 密码出现在命令行里，可以先在终端隐藏输入：

```bash
read -rsp "KWeaver password: " KWEAVER_CLI_PASSWORD; echo
export KWEAVER_CLI_PASSWORD

bash ./install.sh \
  --local \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip> \
  2>&1 | tee "$LOG"
```

如果使用 inventory：

```bash
cd deploy
./install.sh \
  --inventory deploy_package/ansible/inventory.ini \
  --foundation-mode integrated \
  --foundation-self-ip <foundation-private-ip>
```

## 4. Foundation 部署模式

`--foundation-mode` 支持三种模式：

| 模式 | 说明 |
|---|---|
| `integrated` | Foundation 与 KWeaver、Agent 服务部署在同一台主机上 |
| `separated` | Foundation 部署在单独主机上 |
| `external` | 使用已有 Foundation，只配置访问地址和凭证 |

`integrated` 模式必须提供：

```text
--foundation-self-ip <foundation-private-ip>
```

`separated` 或 `external` 模式下，需要确保安装程序能够访问 Foundation 地址，并在需要时提供 Foundation AK/SK。

## 5. 安装程序会完成什么

一体化部署会按顺序完成：

1. 准备或校验 Kubernetes 基础环境。
2. 部署基础组件。
3. 部署 KWeaver。
4. 部署或校验 Foundation。
5. 部署 FoundationClient。
6. 配置 KWeaver 模型。
7. 导入知识库数据和数据连接。
8. 部署 BKN、ContextLoader、skills 和 Agent。
9. 发布 Anybackup 业务服务。默认从配置的镜像仓库拉取业务镜像。
10. 发布 Web 访问入口。
11. 执行部署后校验。

安装过程中如需要额外凭证，脚本会在对应步骤提示输入。

## 6. 部署后访问

部署完成后，外部访问入口是 Anybackup Web。后端服务默认仅在集群内部访问，不直接对外暴露。

可以使用以下命令查看整体状态：

```bash
kubectl get pods -A
helm list -A
```

也可以查看安装日志确认各阶段是否完成。

## 7. 重新部署或卸载

如需重新部署，可先执行卸载脚本清理本次部署创建的资源：

```bash
cd deploy
./uninstall.sh
```

卸载脚本会保留 Kubernetes 本身，清理 Anybackup 一体化部署创建的运行资源。清理完成后，可以重新执行 `deploy/install.sh`。
