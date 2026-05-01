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
  <strong>AI-Native Data Resilience Platform</strong><br>
  Backup, recovery, and operational assurance through explainable agent workflows.
</p>

<p align="center">
  <a href="./README_zh.md">中文</a>
</p>

---

## Product Positioning

Anybackup V9 is a more economical and intelligent data resilience platform. Built on an open-source business model, it helps customers achieve the data resilience their business requires. Powered by Anybackup Agent as an AI backup administrator, the platform enables autonomous backup, autonomous recovery, and autonomous optimization, reducing total cost of ownership by up to 35% and moving teams beyond reactive response.

---

## Why Anybackup Exists

Traditional backup systems are usually powerful after you already know what to click, which policy to configure, which recovery point to choose, and which risk you are about to create. That is exactly the problem.

Anybackup V9 is not trying to put a chatbot on top of backup software. It is rebuilding the backup and recovery experience around an AI-native workflow:

1. Describe the data protection need in natural language.
2. Let the Agent generate a structured plan with assumptions and risks.
3. Keep the human in control for dangerous actions.
4. Let Foundation execute the confirmed backup or recovery task.
5. Keep the decision and execution trail auditable.

The goal is simple: make data resilience easier to operate without making it vague, magical, or unsafe.

---

## What This Repository Represents

This is the open-source repository for **Anybackup V9**, the full platform direction:

| Product part | What it does |
|---|---|
| **Anybackup Agent** | Understands intent, generates backup and recovery plans, explains risk, manages confirmation, and keeps decision context |
| **Anybackup Foundation** | Executes backup, recovery, retention, and data protection operations |
| **Anybackup Client** | Connects protected workloads and provides workload-side data access |

Anybackup Agent is cloud-native and must be deployed on Kubernetes. Anybackup Foundation is host-deployed and runs on managed infrastructure outside the Agent Kubernetes runtime. This README keeps deployment details compact, but it should still respect the real product structure.

---

## Product Capabilities

### Natural-Language Backup Planning

Describe a workload and Anybackup Agent turns the request into comparable backup plan candidates. The plan is not just a sentence: it should explain frequency, recovery point expectations, risk trade-offs, and why one option is recommended.

### Recovery Plan Generation

Describe a MySQL failure and the Agent turns it into a structured recovery plan. The plan identifies recovery scope, target point, execution path, and the risk of overwriting or rolling back data.

### Human-Controlled Execution

Any action that can damage production data must go through explicit human confirmation. Anybackup treats AI as a planning and decision-support layer, not as an unchecked operator.

### Operational Query

Administrators can ask about backup jobs, recovery progress, and platform state in natural language instead of hunting through raw system details first.

### Audit-Friendly Workflow

The conversation, generated plan, human decision, execution request, and result should remain traceable. This is essential for real backup and recovery operations, where "why did this happen" matters as much as "did it run."

---

## Current Alpha Scope

`9.0.0-alpha` is an early public preview. It is focused, deliberately narrow, and meant to prove the core loop before the platform grows wider.

**In scope now**

- Single backup administrator workflow
- MySQL-first backup and recovery scenarios
- Backup recommendation from natural language
- Recovery plan generation from failure descriptions
- Human confirmation before risky execution
- Foundation-backed execution path
- Basic operational query experience

**Not promised by this alpha**

- Complete multi-tenant SaaS operations
- Full enterprise role and permission model
- Broad workload coverage beyond the first MySQL scenarios
- Fully automated multi-step recovery without operator review
- A polished production installer for every environment

This boundary is intentional. A reliable AI-native data resilience platform should earn trust one operational loop at a time.

---

## Deployment Overview

Anybackup V9 is deployed as three product layers. They are related, but they are not the same deployment target.

### Anybackup Agent

Anybackup Agent must run on Kubernetes. The integrated deployment entrypoint is [deploy/install.sh](./deploy/install.sh), which prepares the Kubernetes base environment, deploys the Agent runtime and services, imports Agent content, publishes the network entrypoint, and runs deployment verification.

For a local single-node Agent evaluation:

```bash
cd deploy
./install.sh --local --foundation-self-ip <foundation-private-ip>
```

For an inventory-driven Agent deployment:

```bash
cd deploy
./install.sh --inventory deploy_package/ansible/inventory.ini --foundation-self-ip <foundation-private-ip>
```

Agent deployment profiles:

| Profile | Purpose |
|---|---|
| `full` | Deploy the Kubernetes runtime, Agent services, Agent content, network entrypoint, and verification flow |
| `kweaver-core-only` | Deploy only the core Agent runtime layer |
| `agent-content-only` | Import or refresh Agent content against an existing Agent runtime |

### Anybackup Foundation

Anybackup Foundation is deployed on hosts, not inside the Agent Kubernetes cluster. The installer can coordinate Foundation through integrated, separated, or external modes:

```bash
cd deploy
./install.sh --foundation-mode integrated --foundation-self-ip <foundation-private-ip>
```

Foundation-related options include `--skip-foundation`, `--foundation-mode`, `--foundation-package-path`, and `--foundation-install-root`. The source tree keeps a placeholder under `deploy/deploy_package/foundation/`; a real Foundation installation requires an available Foundation package or an already deployed external Foundation.

### Anybackup Client

Anybackup Client is the workload-side access and collection layer. It connects protected assets to Foundation-backed protection and recovery workflows. In the current alpha repository, Client deployment is not exposed as a top-level standalone installer in the same way as Agent deployment. Client rollout should follow the Foundation and workload access flow for the target environment.

Review [deploy/deploy_package/README.md](./deploy/deploy_package/README.md) before using the deployment scripts in a shared or production-like environment.

---

## Example Workflows

### Backup Recommendation

```text
User:
Recommend a backup plan for our production MySQL database.

Anybackup Agent:
I found three candidate plans:

1. Standard protection
   Weekly full backup + daily incremental backup.

2. Low-RPO protection
   Weekly full backup + daily incremental backup + minute-level log backup.

3. Simple protection
   Daily full backup.

Recommended: Low-RPO protection, because this database is production-facing
and needs a shorter recovery point objective.
```

### Recovery Plan

```text
User:
The production MySQL instance crashed and all databases are unavailable.

Anybackup Agent:
This looks like an instance-level failure.

Recommended recovery:
- Scope: full MySQL instance
- Target: latest valid backup point
- Execution: restore through Anybackup Foundation
- Risk: this may overwrite current data on the target host

Please confirm before execution.
```

---

## Architecture at a Glance

```text
Natural language request
        |
        v
Anybackup Agent
Intent, plan, risk, confirmation, audit context
        |
        v
Anybackup Foundation
Backup, recovery, retention, execution
        |
        v
Anybackup Client
Protected workload access and data collection
```

The platform design separates **decision**, **execution**, and **workload access**. That separation matters: AI can help decide and explain, Foundation executes confirmed operations, and Client-side capabilities connect the protected environment.

---

## Repository Map

```text
Anybackup/
├── Agent/          # AI interaction and decision layer
├── CLI/            # Internal command-line tooling and control utilities
├── deploy/         # Cloud-native deployment assets
├── LICENSE         # SSPL-1.0
├── NOTICE          # Copyright notice
├── README.md       # English README
├── README_zh.md    # Chinese README
└── VERSION.txt     # Current version
```

CLI and deployment assets exist because real platforms need engineering tools. They are not the main story of this README. The main story is the product capability: AI-native backup, recovery, and data resilience.

---

## Open Source Model

Anybackup is released under [SSPL-1.0](./LICENSE). The project uses an open-source model to make the platform direction visible, inspectable, and extensible while preserving a sustainable path for enterprise-grade development.

Third-party notices are maintained alongside distribution units where applicable. See [NOTICE](./NOTICE) and component-level `THIRD_PARTY_NOTICES.md` files for details.

---

## Community

- Issues: [GitHub Issues](https://github.com/anybackup-ai/Anybackup/issues)
- Discussions: [GitHub Discussions](https://github.com/anybackup-ai/Anybackup/discussions)

---

## Contributing

Contributions are welcome as the project evolves. Before submitting a pull request:

1. Open an issue to discuss the change or feature.
2. Keep changes aligned with the current alpha scope.
3. Update relevant documentation and notices when behavior or dependencies change.
4. Run checks for the component you modified.

Detailed contribution guidelines will be expanded as the public development workflow matures.
