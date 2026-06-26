<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Executive Summary

**Status:** Skeleton (v0.1). Threats enumerated, risk scoring pending.

## What this threat model covers

The Guidance for Agentic AI Platform on AWS deploys AI agents (built on Amazon Bedrock AgentCore) in either a single AWS account or a 7-account enterprise layout with CI/CD promotion from dev → staging → prod. This threat model enumerates plausible threats against every component of that deployment — the agent runtime, tool gateway, memory, authentication, cross-account deploy mechanism, CI/CD pipeline, and observability layer — using the STRIDE methodology.

## Headline numbers

- **45 threats** identified across 8 feature areas
- **7 accounts** in the enterprise tier, each with its own threat surface
- **Risk scores: not yet assigned.** The per-threat impact/likelihood judgment requires a workshop with humans who own the relevant systems.

## Top surface areas (qualitative, pending scoring)

Based on what has typical highest blast radius in platforms of this shape:

1. **Cross-account deploy (DEPLOY.\*)** — `OrganizationAccountAccessRole` abuse from the management account is the single highest-impact failure mode. Compromising the management account means owning every member account.
2. **CI/CD pipeline (CICD.\*)** — The pipeline is the only intended write path to prod. Artifact tampering, eval gate bypass, or direct pipeline-role assumption all defeat the "code review → eval → approve" model.
3. **Agent runtime (RT.\*)** — Prompt injection is the defining threat of LLM systems; cost blowout via agent-loop amplification is a real and often-underweighted concern.
4. **Identity (AUTH.\*)** — Cognito JWT theft, OAuth2 M2M secret exposure, and pipeline-eval credential handling — all Cognito-mediated, all in shared-tooling in the enterprise tier.
5. **Gateway tools (GW.\*)** — Tool output is treated as trusted context by the agent; any tool that reaches external data is a prompt-injection vector.

## What's missing

- **Risk scoring.** Every row in `risk-assessment/risk-matrix.md` says `TBD`.
- **Mitigation ownership.** Each threat lists controls and "mitigations to consider" but no assigned owner or deadline.
- **Quantitative threat modeling.** No loss-magnitude estimates, no ALE calculations. This model is qualitative.
- **Tool-specific threat analysis.** Only the reference `strands-single-agent` + shipped sample tools are covered. Customer-added tools are out of scope and need their own reviews.
- **Third-party library threats.** Supply-chain threats against Python / Node dependencies are not explicitly modeled — rely on dependency scanning as a compensating control.

## Next steps

1. Schedule a threat-modeling workshop with representatives from platform, security, and agent-development teams.
2. Walk the 45 threats in priority order (start with DEPLOY + CICD + AUTH), assign likelihood/impact, score the risk matrix.
3. For every High or Critical, assign an owner + target date + mitigation plan.
4. Roll mitigations into [`docs/platform-security.md`](../../docs/platform-security.md) and the implementation guide.
5. Re-review on significant architecture changes; at minimum, quarterly.

## Stakeholder questions this model should help answer

- *Is it safe to use the platform for data classified at level X?* → scope X against the Information Disclosure threats (OBS.T02, MEM.T03, CI.T02 in particular) and their mitigation status.
- *What's the worst-case blast radius of a compromised developer credential?* → CICD.T04 + DEPLOY.T03 trace the lateral path.
- *What's the worst-case blast radius of a compromised user JWT?* → RT.T01 + RT.T04 + MEM.T01.
- *Is there a single point of compromise that affects all environments?* → Yes — the shared-tooling account's Gateway + Cognito + pipeline. See GW.T04, AUTH.T02, CICD.T06.