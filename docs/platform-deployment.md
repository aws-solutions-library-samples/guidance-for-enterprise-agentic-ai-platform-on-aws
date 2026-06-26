<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Deployment Guide

## Quick Start

```bash
# Edit account config
vi infra/config.yaml

# Deploy both tiers
./scripts/deploy.sh all
```

## Modes

### Single Account

Deploys everything into the current account. Console testing works.

```bash
./scripts/deploy.sh single
```

Platform resources prefixed with `agentic-ai-platform-single-*` (CFN-owned: pipeline, ECR, CodeCommit, Cognito, IAM, SSM, Secrets). AgentCore resources prefixed with `fastagent-single-*` (CDK-owned: Gateway + per-agent stacks). Includes:
- Platform infra (CodeCommit, CodePipeline, CodeBuild, ECR, Cognito)
- AgentCore (Gateway, Runtime, Memory, Identity) — all co-located

### Enterprise (7 accounts)

Deploys across management, security, observability, shared-tooling, dev, staging, and prod accounts. Run from the management account.

```bash
./scripts/deploy.sh enterprise
```

Resources prefixed with `fastagent-enterprise-*`. Splits:
- Platform stacks (StackSets) → security, observability, shared-tooling, dev, staging, prod
- Auth layer (Cognito, Gateway, Identity) → shared-tooling
- Workload layer (Runtime, Memory) → dev, staging, prod
- CI/CD pipeline (CodeCommit, CodePipeline, CodeBuild) → shared-tooling, promoting dev → staging → prod

### Both

```bash
./scripts/deploy.sh all
```

Deploys enterprise first, then single. Both coexist in the dev account with distinct prefixes.

## Testing

```bash
# Single-account test
python3 agentcore/test-scripts/test-agent.py

# Enterprise — cross-account CLI test
python3 scripts/enterprise_agent_test.py --username you@example.com
```

## Teardown

```bash
./scripts/destroy.sh single
./scripts/destroy.sh enterprise
```

## Outputs

Deploy scripts write to `scripts/out/`:
- `single-outputs.json`
- `enterprise-outputs.json`

## Account Architecture

| Account | Purpose |
|---------|---------|
| Management | Organizations, SCPs, billing, StackSet admin |
| Security | CloudTrail, KMS, findings |
| Observability | Dashboards, alarms, traces (OAM sink) |
| Shared Tooling | Cognito, Gateway, agent registry, ECR, CI/CD pipeline |
| Dev | Runtime, Memory, first-stage deploys |
| Staging | Runtime, Memory, pre-prod promotion target |
| Prod | Runtime, Memory, production deploys |