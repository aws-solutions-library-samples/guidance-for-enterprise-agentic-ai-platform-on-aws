<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# STRIDE Analysis

Cross-cutting view of all identified threats, grouped by STRIDE category. Each threat is listed in the per-feature file (linked) with full detail. This document is for navigation and coverage checking only.

## Spoofing (impersonation)

| ID | Threat | File |
|----|--------|------|
| RT.T04 | Session ID spoofing / hijack | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| AUTH.T01 | JWT theft and replay | [identity-auth.md](../feature-threats/identity-auth.md) |
| AUTH.T02 | OAuth2 client secret exposure | [identity-auth.md](../feature-threats/identity-auth.md) |
| AUTH.T04 | Pipeline-eval user credential exposure | [identity-auth.md](../feature-threats/identity-auth.md) |
| AUTH.T05 | Cognito self-signup enabled in production | [identity-auth.md](../feature-threats/identity-auth.md) |
| CICD.T04 | Source-stage poisoning (stolen CodeCommit credential) | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |

## Tampering

| ID | Threat | File |
|----|--------|------|
| RT.T01 | Prompt injection via user input | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| RT.T02 | Prompt injection via tool output | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| RT.T07 | Streaming response tampering | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| GW.T02 | Tool response injection | [gateway-tools.md](../feature-threats/gateway-tools.md) |
| GW.T04 | Lambda target tampering | [gateway-tools.md](../feature-threats/gateway-tools.md) |
| GW.T06 | MCP protocol vulnerability | [gateway-tools.md](../feature-threats/gateway-tools.md) |
| MEM.T02 | Memory poisoning | [memory.md](../feature-threats/memory.md) |
| MEM.T04 | Memory ARN exposure / confusion | [memory.md](../feature-threats/memory.md) |
| DEPLOY.T04 | CFN template tampering | [cross-account-deploy.md](../feature-threats/cross-account-deploy.md) |
| CICD.T01 | Artifact tampering in pipeline bucket | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |
| CICD.T02 | Evaluation gate bypass | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |
| CICD.T06 | ECR image tampering | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |
| CICD.T07 | Eval flakiness masking real failures | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |
| OBS.T03 | Log tampering / deletion | [observability.md](../feature-threats/observability.md) |
| OBS.T04 | OAM link hijack via lifecycle drift | [observability.md](../feature-threats/observability.md) |

## Repudiation

| ID | Threat | File |
|----|--------|------|
| DEPLOY.T03 | Trust-policy drift in member accounts | [cross-account-deploy.md](../feature-threats/cross-account-deploy.md) |
| CICD.T05 | Manual approval misuse | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |
| OBS.T03 | Log tampering / deletion (also under Tampering) | [observability.md](../feature-threats/observability.md) |
| OBS.T05 | Transaction Search disablement | [observability.md](../feature-threats/observability.md) |

## Information Disclosure

| ID | Threat | File |
|----|--------|------|
| RT.T05 | Model region/egress misconfiguration | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| GW.T05 | Gateway endpoint exposure | [gateway-tools.md](../feature-threats/gateway-tools.md) |
| CI.T02 | Data exfiltration via code output | [code-interpreter.md](../feature-threats/code-interpreter.md) |
| MEM.T01 | Cross-session / cross-user memory leakage | [memory.md](../feature-threats/memory.md) |
| MEM.T03 | Memory retention beyond compliance window | [memory.md](../feature-threats/memory.md) |
| AUTH.T06 | Token Vault contents leak via IAM | [identity-auth.md](../feature-threats/identity-auth.md) |
| OBS.T01 | OAM sink policy widened | [observability.md](../feature-threats/observability.md) |
| OBS.T02 | Sensitive content in logs / traces | [observability.md](../feature-threats/observability.md) |

## Denial of Service (including economic)

| ID | Threat | File |
|----|--------|------|
| RT.T06 | Denial of wallet via agent loop amplification | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| CI.T04 | Cost amplification (Code Interpreter) | [code-interpreter.md](../feature-threats/code-interpreter.md) |
| OBS.T05 | Transaction Search disablement | [observability.md](../feature-threats/observability.md) |

## Elevation of Privilege

| ID | Threat | File |
|----|--------|------|
| RT.T01 | Prompt injection (also under Tampering) | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| RT.T03 | Runtime IAM role over-privilege | [agent-runtime.md](../feature-threats/agent-runtime.md) |
| GW.T01 | Tool authorization bypass | [gateway-tools.md](../feature-threats/gateway-tools.md) |
| GW.T03 | Tool Lambda IAM over-privilege | [gateway-tools.md](../feature-threats/gateway-tools.md) |
| CI.T01 | Arbitrary code execution (within sandbox) | [code-interpreter.md](../feature-threats/code-interpreter.md) |
| CI.T03 | Sandbox escape (AWS-service-level) | [code-interpreter.md](../feature-threats/code-interpreter.md) |
| AUTH.T03 | Privilege escalation via custom Cognito claims | [identity-auth.md](../feature-threats/identity-auth.md) |
| DEPLOY.T01 | OrganizationAccountAccessRole abuse | [cross-account-deploy.md](../feature-threats/cross-account-deploy.md) |
| DEPLOY.T02 | StackSet admin role abuse | [cross-account-deploy.md](../feature-threats/cross-account-deploy.md) |
| DEPLOY.T05 | SCP bypass via deploy scope | [cross-account-deploy.md](../feature-threats/cross-account-deploy.md) |
| CICD.T03 | Pipeline role assumption by human | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |
| CICD.T05 | Manual approval misuse | [cicd-pipeline.md](../feature-threats/cicd-pipeline.md) |

## Coverage commentary

- Tampering has the largest footprint — unsurprising for a CI/CD-driven agent platform where artifacts, prompts, tools, and memory can all be manipulated.
- Elevation-of-Privilege concentrates in the cross-account deploy surface (DEPLOY.*) and the agent-to-tool authorization boundary (GW.*).
- Denial of Service is almost entirely economic (cost) rather than availability — a distinctive property of LLM-backed systems.
- Repudiation coverage is currently thin; CloudTrail + OAM aggregation cover most of this but specific audit-gap scenarios are worth expanding during the workshop.