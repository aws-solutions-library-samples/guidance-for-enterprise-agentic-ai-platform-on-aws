<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Implementation Guide

> This implementation guide addresses customer responsibilities within the [AWS shared responsibility model](https://aws.amazon.com/compliance/shared-responsibility-model/). AWS is responsible for securing the underlying infrastructure, Amazon Bedrock AgentCore service, and managed service components. Customers are responsible for implementing the controls documented in this guide.

**Status:** Placeholder. Fill in per-threat mitigations after the workshop populates `risk-assessment/risk-matrix.md`.

This document maps agreed-upon mitigations (not "mitigations to consider" — actual committed mitigations) to concrete implementation locations in the platform.

## Where mitigations live

| Layer | Location | Examples |
|-------|----------|----------|
| IAM scoping | `agentcore/infra-cdk/lib/*.ts`, `infra/cloudformation/**/*.yaml` | Runtime role, Gateway role, Lambda target roles, pipeline roles |
| Cognito policy | `agentcore/infra-cdk/lib/cognito-stack.ts` | Self-signup, password policy, advanced security, MFA |
| System prompts | `agentcore/patterns/*/basic_agent.py` | Tool-output sanitization guidance, refusal scopes |
| Gateway config | `agentcore/infra-cdk/lib/backend-stack.ts` | Tool registration, authorization scopes |
| SCPs | *(not in repo — customer org)* | Deny-lists at org level |
| CloudWatch alarms | `infra/cloudformation/enterprise/platform/observability.yaml` | OAM sink policy drift, unusual role assumptions |
| AWS Config rules | *(to be added)* | IAM role trust policy drift, OAM sink policy shape |
| Pipeline gates | `infra/cloudformation/enterprise/platform/shared-tooling.yaml`, `scripts/pipeline_eval.py` | Eval thresholds, retry policy, approval stages |

## Template — how to document a mitigation

For each threat marked High or Critical in the risk matrix, add a section below following this shape:

```
### <THREAT.ID> — <Title>

**Decision:** <Accepted / Mitigated / Partially mitigated / Transferred>

**Chosen control(s):**
- <Specific, testable control>
- <Specific, testable control>

**Implementation location:**
- File: <path>
- Resource: <CFN/CDK logical ID>

**Verification:**
- <How to check the control is in place — AWS Config rule, integration test, periodic audit script>

**Owner:** <Team or role>
**Target date:** <YYYY-MM-DD>
**Residual risk:** <Low / Med / High / Critical>
**Last reviewed:** <YYYY-MM-DD>
```

## Cross-cutting controls to put in place first

Regardless of per-threat workshop outcomes, these are defensible defaults worth implementing early:

### Detective controls

- CloudTrail organization trail (already enabled by `deploy.sh enterprise`)
- GuardDuty in each account, findings aggregated in security account
- Security Hub enabled, CIS + Foundational Security Best Practices standards
- Access Analyzer in each account, findings aggregated in security account
- CloudWatch alarms on:
  - `sts:AssumeRole` into `OrganizationAccountAccessRole` outside deploy windows
  - `oam:UpdateSink` (any call)
  - `lambda:UpdateFunctionCode` by non-pipeline principals
  - `ecr:PutImage` with mutable tags
  - `xray:UpdateTraceSegmentDestination` (any call)

### Preventive controls

- SCPs denying:
  - `iam:DeleteRole` on `OrganizationAccountAccessRole` in member accounts
  - `logs:DeleteLogGroup` / `logs:PutRetentionPolicy` below org minimum
  - Cross-region actions in regions not on the allowlist
- ECR tag immutability on all image repositories
- S3 versioning + MFA delete on pipeline artifact bucket
- S3 object lock on CloudTrail bucket in security account

### Process controls

- MFA required on all management-account principals
- MFA required on all manual-approval approvers in CodePipeline
- Different approvers for ApproveStaging vs. ApproveProd
- Code review required on the agent repo `main` branch
- Quarterly threat-model review

## Per-threat implementations

*(Empty — populate from the risk matrix after the workshop.)*

---

## Appendix: Testing mitigations

Whenever a new mitigation lands, add a corresponding test:

- **IAM scoping** — integration test invoking the role against a denied action; expect `AccessDenied`
- **Cognito policy** — integration test attempting self-signup (if disabled) or weak password (if policy applies)
- **Pipeline gates** — introduce a deliberately failing eval case; verify the pipeline stops
- **OAM sink policy** — AWS Config custom rule checks policy shape; add CI test on the CFN template
- **CloudTrail alarms** — trigger the action under test; expect alarm to fire within N minutes
