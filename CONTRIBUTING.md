# Contributing to Anybackup

Thank you for your interest in contributing to Anybackup. This guide explains how to set up a development environment, understand the project scope, and follow the contribution workflow.

## Project Overview

Anybackup is an AI-Native Data Resilience Platform in active alpha development. The current version is **9.0.0-alpha**, focused on single backup administrator workflows and MySQL-first backup and recovery scenarios.

This is a safe contribution scope: we welcome improvements to documentation, CI/CD, test coverage, and configuration validation. Core deletion, restore, and encryption logic requires deeper alignment with the product roadmap and is best discussed before opening PRs.

## Development Setup

```bash
# Clone the repository
git clone https://github.com/anybackup-ai/Anybackup.git
cd Anybackup

# Install test dependencies
pip install pytest

# Run tests for the deploy package
pytest deploy/deploy_package/tests/
```

## Contribution Workflow

### Issue-First Approach

Before submitting a pull request:

1. **Open an issue** to describe the problem or proposed change
2. **Discuss the approach** — this ensures the change aligns with project direction
3. **Wait for feedback** before writing code
4. **Then submit the PR** referencing the issue

This prevents duplicate work and ensures contributions fit the project's evolving architecture.

## What's In Scope

Contributions in these areas are welcome:

- **Documentation** improvements and corrections
- **CI/CD** pipeline fixes and enhancements
- **Test coverage** additions and bug fixes
- **Configuration validation** logic
- **README** updates when behavior or dependencies change

## What's Out of Scope

Unless previously discussed and approved:

- **Deletion logic** changes
- **Restore execution** code modifications
- **Encryption** implementation changes

These areas involve careful safety considerations and product alignment. Please open an issue first to discuss any changes in these domains.

## Documentation Updates

When your contribution changes behavior or introduces new dependencies:

- Update the relevant README files (`README.md` / `README_zh.md`)
- Update or add `THIRD_PARTY_NOTICES.md` if introducing new components
- Keep the [Architecture at a Glance](#architecture-at-a-glance) section consistent with your changes

## Testing

Run the test suite before submitting:

```bash
pytest deploy/deploy_package/tests/
```

Ensure all existing tests pass. New features should include corresponding tests.

## Code Style

- Follow existing patterns in the codebase
- Keep changes focused and minimal
- Write clear commit messages describing what and why

## License

By contributing to Anybackup, you agree that your contributions will be licensed under the [SSPL-1.0 License](./LICENSE).