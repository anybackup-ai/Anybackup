# Anybackup

<p align="center">
  <a href="https://github.com/anybackup-ai/Anybackup/blob/main/LICENSE"><img src="https://img.shields.io/badge/license-SSPL--1.0-blue.svg" alt="License"></a>
  <a href="https://github.com/anybackup-ai/Anybackup/blob/main/VERSION.txt"><img src="https://img.shields.io/badge/version-9.0.0--alpha-orange.svg" alt="Version"></a>
  <img src="https://img.shields.io/badge/status-alpha_preview-yellow.svg" alt="Status">
  <img src="https://img.shields.io/badge/architecture-AI--Native-brightgreen.svg" alt="Architecture">
  <img src="https://img.shields.io/badge/workload-MySQL_first-informational.svg" alt="Workload">
  <img src="https://img.shields.io/badge/cloud--native-Kubernetes-326CE5.svg" alt="Cloud Native">
</p>

<p align="center">
  <strong>AI-Native 数据韧性平台</strong><br>
  用可解释的 Agent 工作流完成备份、恢复与运行保障。
</p>

<p align="center">
  <a href="./README.md">English</a>
</p>

---

## 产品定位

作为更经济、智能的数据韧性平台，Anybackup V9 基于开源商业模式，为客户实现业务所需的数据韧性保障。Anybackup Agent 打造的 AI 备份管理员，实现自主备份、自主恢复、自主优化，总体拥有成本可降低 35%，告别被动响应。

---

## Anybackup 为什么存在

传统备份系统并不缺能力，真正的问题是：你必须先知道点哪里、配哪条策略、选哪个恢复点、承担什么风险，然后才能把能力用起来。这恰恰是 Anybackup V9 想解决的地方。

Anybackup V9 不是给备份软件套一个聊天框。它要重做的是备份与恢复的操作体验，把它变成一条 AI-Native 工作流：

1. 用自然语言描述数据保护需求。
2. 由 Agent 生成包含假设、依据和风险的结构化方案。
3. 高风险动作由人明确确认。
4. 由 Foundation 执行已确认的备份或恢复任务。
5. 保留可审计的决策与执行上下文。

目标很直接：让数据韧性更容易被操作，同时不变得含糊、玄学或失控。

---

## 这个仓库代表什么

这是 **Anybackup V9** 的开源仓库，代表的是完整平台方向：

| 产品部分 | 职责 |
|---|---|
| **Anybackup Agent** | 理解意图、生成备份和恢复方案、解释风险、管理确认流程、保留决策上下文 |
| **Anybackup Foundation** | 执行备份、恢复、保留策略和数据保护操作 |
| **Anybackup Client** | 连接被保护工作负载，提供工作负载侧数据访问能力 |

Anybackup Agent 采用云原生架构，只能部署在 Kubernetes 上。Anybackup Foundation 部署在主机上，运行在 Agent Kubernetes 运行时之外的受管基础设施中。这个 README 会保持部署说明克制，但必须尊重真实产品结构。

---

## 产品能力

### 自然语言备份规划

描述一个工作负载，Anybackup Agent 会把需求转化为可比较的备份候选方案。方案不只是一句建议，而应该说明备份频率、恢复点预期、风险取舍，以及为什么推荐某个选项。

### 恢复方案生成

描述一个 MySQL 故障，Agent 会生成结构化恢复方案。方案会说明恢复范围、目标时间点、执行路径，以及覆盖或回滚数据的风险。

### 人工可控执行

任何可能破坏生产数据的动作，都必须经过明确的人工确认。Anybackup 把 AI 定位为规划与决策辅助层，而不是不受约束的执行者。

### 运行状态查询

管理员可以用自然语言查询备份任务、恢复进度和平台状态，而不是一上来就在原始系统细节中翻找。

### 审计友好闭环

对话、生成方案、人工决策、执行请求和执行结果都应该可追踪。真实备份恢复场景里，"为什么这么做"和"是否执行成功"同样重要。

---

## 当前 Alpha 范围

`9.0.0-alpha` 是早期公开预览版本。它刻意保持聚焦，用来先证明核心闭环，再逐步扩展平台宽度。

**当前范围**

- 单一备份管理员工作流
- MySQL 首批备份与恢复场景
- 从自然语言生成备份推荐
- 从故障描述生成恢复方案
- 高风险执行前人工确认
- 由 Foundation 承接的执行路径
- 基础运行状态查询体验

**当前不承诺**

- 完整多租户 SaaS 运营
- 完整企业级角色与权限模型
- 首批 MySQL 场景之外的广泛工作负载覆盖
- 无需人工审核的全自动多步骤恢复
- 覆盖所有环境的成熟生产安装器

这个边界是有意为之。可靠的 AI-Native 数据韧性平台，应该一条操作闭环一条操作闭环地建立信任。

---

## 部署概览

Anybackup V9 按三层产品结构部署。三层彼此关联，但部署目标并不相同。

### Anybackup Agent

Anybackup Agent 只能运行在 Kubernetes 上。集成部署入口是 [deploy/install.sh](./deploy/install.sh)，它会准备 Kubernetes 基础环境，部署 Agent 运行时和业务服务，导入 Agent 内容，发布网络入口，并执行部署验证。

本地单节点 Agent 体验：

```bash
cd deploy
./install.sh --local --foundation-self-ip <foundation-private-ip>
```

使用 inventory 的 Agent 部署：

```bash
cd deploy
./install.sh --inventory deploy_package/ansible/inventory.ini --foundation-self-ip <foundation-private-ip>
```

Agent 部署 profile：

| Profile | 用途 |
|---|---|
| `full` | 部署 Kubernetes 运行时、Agent 服务、Agent 内容、网络入口和验证流程 |
| `kweaver-core-only` | 只部署 Agent 核心运行时层 |
| `agent-content-only` | 面向已有 Agent 运行时导入或刷新 Agent 内容 |

### Anybackup Foundation

Anybackup Foundation 只能部署在主机上，不运行在 Agent 的 Kubernetes 集群里。安装脚本可以通过 integrated、separated 或 external 模式编排 Foundation：

```bash
cd deploy
./install.sh --foundation-mode integrated --foundation-self-ip <foundation-private-ip>
```

Foundation 相关参数包括 `--skip-foundation`、`--foundation-mode`、`--foundation-package-path` 和 `--foundation-install-root`。源码树中的 `deploy/deploy_package/foundation/` 当前只是 Foundation 安装包占位目录；真实 Foundation 安装需要可用的 Foundation 安装包，或已经部署好的外部 Foundation。

### Anybackup Client

Anybackup Client 是工作负载侧接入和采集层，用于把被保护资产连接到 Foundation 承接的保护与恢复流程。当前 alpha 仓库里，Client 部署没有像 Agent 部署那样暴露为顶层独立安装器。Client 推出应遵循目标环境下的 Foundation 与工作负载接入流程。

用于共享环境或类生产环境前，请先阅读 [deploy/deploy_package/README.md](./deploy/deploy_package/README.md)。

---

## 示例工作流

### 备份推荐

```text
用户：
帮我们的生产 MySQL 数据库推荐一个备份方案。

Anybackup Agent：
我找到三套候选方案：

1. 常规保护
   每周全备 + 每天增量备份。

2. 低 RPO 保护
   每周全备 + 每天增量备份 + 分钟级日志备份。

3. 简单保护
   每天全备。

推荐：低 RPO 保护，因为这是生产数据库，需要更短的恢复点目标。
```

### 恢复方案

```text
用户：
生产 MySQL 实例崩溃了，所有数据库都访问不了。

Anybackup Agent：
这看起来是实例级故障。

建议恢复方案：
- 范围：完整 MySQL 实例
- 目标：最近一次有效备份点
- 执行：通过 Anybackup Foundation 恢复
- 风险：该操作可能覆盖目标主机上的当前数据

请确认后再执行。
```

---

## 架构一眼看懂

```text
自然语言请求
        |
        v
Anybackup Agent
意图、方案、风险、确认、审计上下文
        |
        v
Anybackup Foundation
备份、恢复、保留策略、执行
        |
        v
Anybackup Client
被保护工作负载访问与数据采集
```

平台设计刻意拆开 **决策**、**执行** 和 **工作负载访问**。这很重要：AI 可以帮助判断和解释，Foundation 执行已确认的操作，Client 侧能力负责连接被保护环境。

---

## 仓库结构

```text
Anybackup/
├── Agent/          # AI 交互与决策层
├── CLI/            # 内部命令行工具与控制面辅助能力
├── deploy/         # 云原生部署资产
├── LICENSE         # SSPL-1.0
├── NOTICE          # 版权声明
├── README.md       # 英文 README
├── README_zh.md    # 中文 README
└── VERSION.txt     # 当前版本号
```

CLI 和部署资产存在，是因为真实平台需要工程工具。它们不是这个 README 的主角。这个 README 的主角是产品能力：AI-Native 备份、恢复与数据韧性。

---

## 开源模式

Anybackup 基于 [SSPL-1.0](./LICENSE) 发布。项目采用开源模式，让平台方向可见、可审阅、可扩展，同时为企业级持续研发保留可持续路径。

第三方开源声明按分发单元维护。详情见 [NOTICE](./NOTICE) 以及各组件目录下的 `THIRD_PARTY_NOTICES.md`。

---

## 社区

- 问题反馈：[GitHub Issues](https://github.com/anybackup-ai/Anybackup/issues)
- 讨论交流：[GitHub Discussions](https://github.com/anybackup-ai/Anybackup/discussions)

---

## 参与贡献

欢迎社区贡献。提交 Pull Request 前：

1. 先通过 Issue 讨论你的改动或新功能。
2. 保持变更与当前 alpha 阶段范围一致。
3. 行为或依赖变化时，同步更新相关文档和声明。
4. 运行与你修改组件相关的检查。

详细贡献指南会随着公开开发流程成熟逐步补齐。
