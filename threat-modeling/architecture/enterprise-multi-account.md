<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Enterprise Multi-Account Tier — Threat Notes

The enterprise tier spreads the platform across 7 accounts under an AWS Organization: management, security, observability, shared-tooling, dev, staging, and prod. This amplifies some threats and introduces new ones that do not exist in single-tier.

## Account-specific threat surfaces

### Management account
- Holds StackSet admin role + uses `OrganizationAccountAccessRole` to push CFN into every member.
- Compromise here = full platform compromise.
- Recommended controls: MFA on all principals, SCPs denying anything outside deploy roles, CloudTrail alerting on unusual `AssumeRole` / `CreateStackSet` events.
- See **[DEPLOY.*](../feature-threats/cross-account-deploy.md)**.

### Security account
- CloudTrail trail destination + KMS CMK.
- Compromise = ability to delete/tamper audit trail.
- Recommended controls: S3 object lock on audit bucket, KMS key policy restricting delete, separate Break-Glass role.

### Observability account
- OAM Sink + dashboards + cross-account log read.
- Read-only from workload accounts (by design). Compromise = ability to see all telemetry but not write to workloads.
- Risk: OAM sink resource policy drift — if someone widens the `Principal` to `"*"` without `aws:PrincipalOrgID`, external principals could link in.
- See **[OBS.*](../feature-threats/observability.md)**.

### Shared-tooling account
- Cognito + AgentCore Identity + Gateway + Tool Lambdas + CodeCommit + CodePipeline + ECR + Secrets Manager (OAuth2, pipeline eval).
- This is the "shared services" account. Compromise = ability to mint arbitrary JWTs (Cognito), steal OAuth2 secrets (Token Vault), tamper with pipeline, or replace images in ECR.
- Recommended controls: scoped IAM per function, no human-admin access in steady state, S3 versioning on pipeline artifact bucket, ECR image signing.
- See **[AUTH.*](../feature-threats/identity-auth.md)**, **[GW.*](../feature-threats/gateway-tools.md)**, **[CICD.*](../feature-threats/cicd-pipeline.md)**.

### Dev / Staging / Prod accounts
- Each runs its own AgentCore Runtime + Memory + Code Interpreter.
- Compromise of one does not compromise another (AWS account boundary), but compromise of shared-tooling would compromise all three.
- See all feature files.

## Cross-account-specific threats to verify

- **DEPLOY.T01** — OrganizationAccountAccessRole abused from management account (or stolen session token used laterally).
- **DEPLOY.T02** — StackSet admin role assumed by a principal that should not have org-wide write capability.
- **DEPLOY.T03** — A trust-policy change in a member account's OrganizationAccountAccessRole (e.g. adding another trusted principal) goes undetected.
- **OBS.T01** — OAM sink policy widened to org-wide `*` without `aws:PrincipalOrgID` condition.
- **OBS.T02** — Log data containing secrets/PII aggregated to observability account, broadening exposure.
- **CICD.T03** — Pipeline role in shared-tooling account assumed by a human user, bypassing the pipeline's eval gates.

## Enterprise amplifications of feature-level threats

- **GW.* (Gateway tool threats)** — Gateway in shared-tooling is a shared dependency for dev/staging/prod. A Gateway-level vulnerability affects all environments simultaneously; there is no per-env Gateway isolation.
- **AUTH.* (Identity)** — Cognito user pool is in shared-tooling. A pool compromise affects all environments.
- **CICD.*** — one pipeline deploys to all environments. Pipeline compromise = ability to promote arbitrary code to prod.

## Defense-in-depth opportunities unique to enterprise

- SCPs at the Organization level to deny high-risk actions even if IAM were misconfigured.
- Guard Duty + Security Hub aggregated in security account.
- Centralized IAM Access Analyzer findings in security account.
- Strict Break-Glass procedures for management account access.

See the individual feature files for threat detail. Cross-reference enterprise-specific mitigations in `docs/platform-security.md`.
