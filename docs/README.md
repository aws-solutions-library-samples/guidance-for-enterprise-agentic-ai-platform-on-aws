<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Documentation

Documentation for the Agentic AI Platform on AWS.

Files are grouped by audience in this index. The filesystem is flat —
use the `platform-*` prefix for platform/operator concerns and the
`agentcore-*` prefix for agent runtime concerns.

## Platform

- [Architecture](./platform-architecture.md) — component architecture and data flow across deployment tiers
- [Deployment](./platform-deployment.md) — single-account and enterprise (multi-account) deploy instructions
- [Security](./platform-security.md) — shared-responsibility controls and hardening guidance
- [Observability](./platform-observability.md) — CloudWatch, X-Ray, and cross-account telemetry
- [Cost](./platform-cost.md) — cost drivers and estimation guidance

## AgentCore

- [Deployment](./agentcore-deployment.md) — build, deploy, and test the agent stack
- [Configuration](./agentcore-configuration.md) — agent patterns and configuration options
- [Gateway & Tool Integration](./agentcore-gateway.md) — MCP gateway and Lambda-backed tools
- [Memory](./agentcore-memory.md) — conversation history and memory strategies
- [Authentication](./agentcore-auth.md) — M2M auth between Runtime and Gateway
- [Streaming](./agentcore-streaming.md) — SSE streaming event format
- [Evaluation](./agentcore-evaluation.md) — agent evaluation and pipeline gates
- [Code Interpreter Tool](./agentcore-tool-code-interpreter.md) — Code Interpreter integration

## Local Development

- [Local Development](./agentcore-local-development.md) — full local stack with docker-compose and Gateway support
- [Local Docker Testing](./agentcore-local-docker-testing.md) — lightweight container-only testing

## Diagrams

Architecture diagrams live in [`./diagrams/`](./diagrams/).

- `FAST-architecture-180326.png` — current platform architecture
- `FAST-architecture.drawio` — editable source

## Contributing

When adding or updating docs:

1. Place new files directly under `docs/` (flat) using the `platform-*` or `agentcore-*` prefix.
2. Use kebab-case for filenames.
3. Add the new doc to the relevant section of this index.
4. Cross-link related docs instead of duplicating content.
