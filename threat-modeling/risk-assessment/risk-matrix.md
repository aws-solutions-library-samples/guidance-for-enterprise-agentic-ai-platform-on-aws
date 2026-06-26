<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Risk Matrix

All identified threats, one row each. Risk scoring is **not yet complete** — the `Likelihood`, `Impact`, `Risk`, and `Status` columns are `TBD` pending a threat-modeling workshop.

## How to use this file

1. Workshop the threats in small batches (one feature file at a time is a reasonable cadence).
2. For each row, assign `Likelihood` (Low / Med / High) and `Impact` (Low / Med / High / Critical).
3. Compute `Risk` as the intersection (use the heat map below) and record a mitigation owner + status.
4. Re-sort by `Risk` descending to identify the top-N priorities.

## Heat map (reference)

|               | Impact: Low | Impact: Med | Impact: High | Impact: Critical |
|---------------|:-----------:|:-----------:|:------------:|:----------------:|
| **Likelihood: High** | Medium | High | Critical | Critical |
| **Likelihood: Med** | Low | Medium | High | Critical |
| **Likelihood: Low** | Low | Low | Medium | High |

Treat anything `High` or `Critical` as a must-fix for the target deployment tier.

## Threats

| ID | Threat | STRIDE | Likelihood | Impact | Risk | Status | Owner |
|----|--------|--------|:----------:|:------:|:----:|:------:|:-----:|
| RT.T01 | Prompt injection via user input | T, E | TBD | TBD | TBD | TBD | TBD |
| RT.T02 | Prompt injection via tool output | T | TBD | TBD | TBD | TBD | TBD |
| RT.T03 | Runtime IAM role over-privilege | E | TBD | TBD | TBD | TBD | TBD |
| RT.T04 | Session ID spoofing / hijack | S | TBD | TBD | TBD | TBD | TBD |
| RT.T05 | Model region/egress misconfiguration | I | TBD | TBD | TBD | TBD | TBD |
| RT.T06 | Denial of wallet via agent loop amplification | D | TBD | TBD | TBD | TBD | TBD |
| RT.T07 | Streaming response tampering | T | TBD | TBD | TBD | TBD | TBD |
| GW.T01 | Tool authorization bypass | E | TBD | TBD | TBD | TBD | TBD |
| GW.T02 | Tool response injection | T | TBD | TBD | TBD | TBD | TBD |
| GW.T03 | Tool Lambda IAM over-privilege | E | TBD | TBD | TBD | TBD | TBD |
| GW.T04 | Lambda target tampering | T | TBD | TBD | TBD | TBD | TBD |
| GW.T05 | Gateway endpoint exposure | I | TBD | TBD | TBD | TBD | TBD |
| GW.T06 | MCP protocol vulnerability | T, I | TBD | TBD | TBD | TBD | TBD |
| CI.T01 | Arbitrary code execution (within sandbox) | E | TBD | TBD | TBD | TBD | TBD |
| CI.T02 | Data exfiltration via code output | I | TBD | TBD | TBD | TBD | TBD |
| CI.T03 | Sandbox escape (AWS-service-level) | E | TBD | TBD | TBD | TBD | TBD |
| CI.T04 | Cost amplification (Code Interpreter) | D | TBD | TBD | TBD | TBD | TBD |
| MEM.T01 | Cross-session / cross-user memory leakage | I | TBD | TBD | TBD | TBD | TBD |
| MEM.T02 | Memory poisoning | T | TBD | TBD | TBD | TBD | TBD |
| MEM.T03 | Memory retention beyond compliance window | I | TBD | TBD | TBD | TBD | TBD |
| MEM.T04 | Memory ARN exposure / confusion | I, T | TBD | TBD | TBD | TBD | TBD |
| AUTH.T01 | JWT theft and replay | S | TBD | TBD | TBD | TBD | TBD |
| AUTH.T02 | OAuth2 client secret exposure | S | TBD | TBD | TBD | TBD | TBD |
| AUTH.T03 | Privilege escalation via custom Cognito claims | E | TBD | TBD | TBD | TBD | TBD |
| AUTH.T04 | Pipeline-eval user credential exposure | S | TBD | TBD | TBD | TBD | TBD |
| AUTH.T05 | Cognito self-signup enabled in production | S | TBD | TBD | TBD | TBD | TBD |
| AUTH.T06 | Token Vault contents leak via IAM | I | TBD | TBD | TBD | TBD | TBD |
| DEPLOY.T01 | OrganizationAccountAccessRole abuse | E | TBD | TBD | TBD | TBD | TBD |
| DEPLOY.T02 | StackSet admin role abuse | E | TBD | TBD | TBD | TBD | TBD |
| DEPLOY.T03 | Trust-policy drift in member accounts | E, R | TBD | TBD | TBD | TBD | TBD |
| DEPLOY.T04 | CFN template tampering | T | TBD | TBD | TBD | TBD | TBD |
| DEPLOY.T05 | SCP bypass via deploy scope | E | TBD | TBD | TBD | TBD | TBD |
| CICD.T01 | Artifact tampering in pipeline bucket | T | TBD | TBD | TBD | TBD | TBD |
| CICD.T02 | Evaluation gate bypass | T | TBD | TBD | TBD | TBD | TBD |
| CICD.T03 | Pipeline role assumption by human | E | TBD | TBD | TBD | TBD | TBD |
| CICD.T04 | Source-stage poisoning | T, S | TBD | TBD | TBD | TBD | TBD |
| CICD.T05 | Manual approval misuse | R, E | TBD | TBD | TBD | TBD | TBD |
| CICD.T06 | ECR image tampering | T | TBD | TBD | TBD | TBD | TBD |
| CICD.T07 | Eval flakiness masking real failures | T | TBD | TBD | TBD | TBD | TBD |
| OBS.T01 | OAM sink policy widened | I | TBD | TBD | TBD | TBD | TBD |
| OBS.T02 | Sensitive content in logs / traces | I | TBD | TBD | TBD | TBD | TBD |
| OBS.T03 | Log tampering / deletion | T, R | TBD | TBD | TBD | TBD | TBD |
| OBS.T04 | OAM link hijack via lifecycle drift | T | TBD | TBD | TBD | TBD | TBD |
| OBS.T05 | Transaction Search disablement | R, D | TBD | TBD | TBD | TBD | TBD |

## After the workshop

- Sort this table by `Risk` descending
- Create a top-N priority list in `deliverables/executive-summary.md`
- For each non-Low risk, document the chosen mitigation in `deliverables/implementation-guide.md`
- Re-review on each significant architecture change or quarterly, whichever comes first
