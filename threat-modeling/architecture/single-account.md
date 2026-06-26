<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Single-Account Tier — Threat Notes

The single-account tier collapses all trust boundaries into one AWS account. Most threats documented in the feature files still apply, but the blast radius is different.

## Amplified risks in single-tier

- **No cross-account isolation** — a compromise of the Runtime role, the Gateway role, or the pipeline role gives the attacker IAM context in the same account as the platform stack itself (Cognito, Secrets Manager, ECR, CodeCommit).
- **No staged promotion** — there is no staging/prod gate; the single pipeline deploys straight into the only environment. The `OnFailure: RETRY` on the deploy+eval stage is the only automated safety net.
- **Shared observability context** — no separate observability account. Logs, metrics, and traces share the same account IAM with the workload.

## Diminished risks in single-tier

- **No OrganizationAccountAccessRole** — the highest-privilege boundary in enterprise does not exist here. Platform deploys run as the caller's credentials; scope equals caller's IAM.
- **No OAM sink policy** — no cross-account log aggregation attack surface.
- **No StackSet admin role** — no lateral-deploy surface across accounts.

## Scenario coverage

Single-tier still needs threat review for:

- All agent-plane threats (RT.*, GW.*, CI.*, MEM.*)
- Identity & auth threats (AUTH.*)
- CI/CD pipeline threats (CICD.*)

And can largely skip:

- DEPLOY.* cross-account deploy threats
- OBS.* cross-account observability threats (CloudWatch local, not OAM)

See the individual feature files for the full threat list. Flag any mitigation that depends on "separate AWS account" — those don't apply to single-tier and need alternative controls (IAM-level scoping, resource-level policies, tighter SCPs where possible).
