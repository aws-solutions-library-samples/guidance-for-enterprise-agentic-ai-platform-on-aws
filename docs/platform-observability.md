<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Observability

## Architecture

Observability is centralized in the observability account with cross-account metric sharing from shared-tooling and dev accounts.

## Dashboards

Deployed in the observability account, sourced from every workload (shared-tooling, dev, staging, prod) via OAM:

- Agent invocations (all accounts, 5-min sum)
- Agent latency (p50/p95/p99)
- Tool call success rate
- Token usage (input/output)
- Model invocation cost estimate (hourly)

## Alarms

| Alarm | Condition | Account |
|-------|-----------|---------|
| High Error Rate | > 5 errors in 15 min | Observability |
| High Latency | p99 > 30s for 15 min | Observability |
| Token Budget | > 10M input tokens/day | Observability |

## Cross-Account Metrics

Telemetry flows via CloudWatch Observability Access Manager (OAM). Each workload account (dev, staging, prod, shared-tooling) emits metrics, logs, and X-Ray traces locally. An OAM Sink in the observability account is paired with an OAM Link in every source account — the Link grants the monitoring account read access to that account's telemetry. No cross-account `sts:AssumeRole` or `PutMetricData` is required.

### Sink Policy: Explicit Account List vs. Org-Wide

AWS documents two patterns for the sink's resource policy. We use the explicit account list.

| Approach | Scanner-friendly | Operational |
|---|---|---|
| `Principal: "*"` + `aws:PrincipalOrgID` condition | Passes standard scanners (cfn-nag, Checkov, AWS Config). May flag aggressive custom rulesets that treat any `"*"` principal as a finding. | New accounts joining the org auto-link. Zero template maintenance. |
| Explicit `Principal.AWS` account list (current) | Passes all scanners including strict custom rulesets. | Adding a new member account requires updating `observability.yaml` and redeploying the stack. |

If your org adds accounts infrequently and security review is aggressive, the explicit list is worth the maintenance cost. If you expect frequent account onboarding, switch to `Principal: "*"` + `aws:PrincipalOrgID` and suppress scanner findings with a note that this is an OAM sink resource policy (not an IAM role trust policy).

## Log Groups

AgentCore Runtime writes directly to `/aws/bedrock-agentcore/runtimes/*` in each workload account. The OAM Link exposes these log groups to the observability account for cross-account queries (Logs Insights, Live Tail) without any additional log-group provisioning.

## AgentCore Native Observability

AgentCore Runtime provides built-in observability via:
- CloudWatch Logs at `/aws/bedrock-agentcore/runtimes/*`
- X-Ray tracing (enabled on runtime and gateway)
- CloudWatch metrics under `bedrock-agentcore` namespace