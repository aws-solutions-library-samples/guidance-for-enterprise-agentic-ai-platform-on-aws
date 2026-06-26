<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Agentic AI Platform — Threat Model

## Document Information

| Field | Value |
|-------|-------|
| **Version** | 0.1 (skeleton) |
| **Last Updated** | 2026-04-23 |
| **System** | Guidance for Agentic AI Platform on AWS |
| **Architecture** | Single-account + 7-account enterprise (mgmt, security, observability, shared-tooling, dev, staging, prod) |
| **Methodology** | STRIDE |
| **Status** | Skeleton — threats enumerated, risk scores and mitigation owners TBD |

## Status and Scope

This is a **working skeleton**, not a finished threat model. Threats have been enumerated from the platform's actual architecture (AgentCore Runtime, Gateway, Memory, Identity, Cognito, CI/CD pipeline, cross-account observability). Risk scores, mitigation owners, and detailed countermeasures are marked `TBD` and require a structured threat-modeling workshop to complete.

Do not treat this document as "81% mitigated" or otherwise final. Treat it as a pre-populated template ready for review and prioritization.

## Overview

The platform deploys AI agents on [Amazon Bedrock AgentCore](https://aws.amazon.com/bedrock/agentcore/) with Cognito user authentication, OAuth2 M2M auth between Runtime and Gateway, MCP-protocol Gateway with Lambda-backed tools, Code Interpreter for sandboxed Python execution, and conversation memory. Enterprise deployments add a CodeCommit → CodePipeline → CodeBuild promotion pipeline across dev/staging/prod and centralized observability via CloudWatch OAM.

See [architecture/system-overview.md](architecture/system-overview.md) for components, trust boundaries, and data flows.

## Directory Structure

```
threat-modeling/
├── README.md                                    ← You are here
├── threat-id-glossary.md                        ← All threat IDs with cross-references
│
├── architecture/                                ← System architecture & data flows
│   ├── system-overview.md                       ← Components, trust boundaries
│   ├── data-flows.md                            ← Request/response flows with security analysis
│   ├── single-account.md                        ← Single-account-specific threats
│   └── enterprise-multi-account.md              ← Cross-account / StackSet / OU-level threats
│
├── feature-threats/                             ← Per-surface threat analysis
│   ├── agent-runtime.md                         ← AgentCore Runtime threats (RT)
│   ├── gateway-tools.md                         ← Gateway + MCP tool threats (GW)
│   ├── code-interpreter.md                      ← Code Interpreter sandbox threats (CI)
│   ├── memory.md                                ← Conversation memory threats (MEM)
│   ├── identity-auth.md                         ← Cognito, OAuth2 M2M, Token Vault (AUTH)
│   ├── cross-account-deploy.md                  ← StackSets, OrgAccessRole (DEPLOY)
│   ├── cicd-pipeline.md                         ← CodeCommit/Pipeline/Build + eval gates (CICD)
│   └── observability.md                         ← CloudWatch OAM sink/link (OBS)
│
├── threat-analysis/
│   └── stride-analysis.md                       ← Full STRIDE across all components
│
├── risk-assessment/
│   └── risk-matrix.md                           ← Risk register (scores TBD)
│
└── deliverables/
    ├── executive-summary.md                     ← Executive-level summary
    └── implementation-guide.md                  ← Security controls implementation
```

## Quick Navigation

### Start Here

- **[System Overview](architecture/system-overview.md)** — architecture, components, trust boundaries
- **[Data Flows](architecture/data-flows.md)** — request/response paths with security commentary
- **[Risk Matrix](risk-assessment/risk-matrix.md)** — all identified threats, one row each

### Per-Surface Threats

- **[Agent Runtime](feature-threats/agent-runtime.md)** — prompt injection, agent-loop abuse, IAM scope
- **[Gateway & Tools](feature-threats/gateway-tools.md)** — tool response injection, authorization bypass, Lambda target tampering
- **[Code Interpreter](feature-threats/code-interpreter.md)** — sandbox escape attempts, data exfiltration via code, resource abuse
- **[Memory](feature-threats/memory.md)** — session isolation, cross-user leakage, memory poisoning
- **[Identity & Auth](feature-threats/identity-auth.md)** — JWT theft, OAuth2 secret exposure, token replay, privilege escalation
- **[Cross-Account Deploy](feature-threats/cross-account-deploy.md)** — OrganizationAccountAccessRole abuse, StackSet admin-role misuse
- **[CI/CD Pipeline](feature-threats/cicd-pipeline.md)** — artifact tampering, eval bypass, pipeline role abuse
- **[Observability](feature-threats/observability.md)** — OAM sink policy drift, log tampering, PII in traces

### Deployment-Tier-Specific

- **[Single Account](architecture/single-account.md)** — everything-in-one-account risks
- **[Enterprise Multi-Account](architecture/enterprise-multi-account.md)** — cross-account trust, org-level threats

### Cross-Cutting

- **[STRIDE Analysis](threat-analysis/stride-analysis.md)** — Spoofing/Tampering/Repudiation/Info-Disclosure/DoS/Elevation across all components
- **[Threat ID Glossary](threat-id-glossary.md)** — every threat ID with one-line descriptions

### Deliverables

- **[Executive Summary](deliverables/executive-summary.md)** — stakeholder view
- **[Implementation Guide](deliverables/implementation-guide.md)** — security controls mapping

## Threat Categories

| Prefix | Category | File |
|--------|----------|------|
| RT | Agent Runtime | [agent-runtime.md](feature-threats/agent-runtime.md) |
| GW | Gateway & Tools | [gateway-tools.md](feature-threats/gateway-tools.md) |
| CI | Code Interpreter | [code-interpreter.md](feature-threats/code-interpreter.md) |
| MEM | Memory | [memory.md](feature-threats/memory.md) |
| AUTH | Identity & Auth | [identity-auth.md](feature-threats/identity-auth.md) |
| DEPLOY | Cross-Account Deploy | [cross-account-deploy.md](feature-threats/cross-account-deploy.md) |
| CICD | CI/CD Pipeline | [cicd-pipeline.md](feature-threats/cicd-pipeline.md) |
| OBS | Observability | [observability.md](feature-threats/observability.md) |

## Related Documentation

- [docs/platform-security.md](../docs/platform-security.md) — high-level security posture
- [docs/platform-architecture.md](../docs/platform-architecture.md) — architecture the threats reference
- [docs/agentcore-auth.md](../docs/agentcore-auth.md) — M2M auth flow detail
- [docs/platform-observability.md](../docs/platform-observability.md) — OAM configuration

## How to Contribute

When adding a new threat:

1. Pick the right category prefix (see table above)
2. Use the next sequential number (e.g. `RT.T04`)
3. Follow the entry template in any existing feature file
4. Add the threat to [threat-id-glossary.md](threat-id-glossary.md)
5. Add a row to [risk-assessment/risk-matrix.md](risk-assessment/risk-matrix.md)
6. Cross-reference in [threat-analysis/stride-analysis.md](threat-analysis/stride-analysis.md) under the appropriate STRIDE category

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 0.1 | 2026-04-23 | Initial skeleton — threats enumerated, risk scoring and mitigation review pending |
