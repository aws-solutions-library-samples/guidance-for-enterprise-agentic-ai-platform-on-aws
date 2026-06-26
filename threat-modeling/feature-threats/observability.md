<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Observability (OBS)

Threats to the CloudWatch Observability Access Manager (OAM) telemetry aggregation, X-Ray traces, and CloudWatch Logs. Primarily an enterprise-tier concern; single-tier collapses into a single-account CloudWatch and carries only the logging-content threats.

Related docs: [docs/platform-observability.md](../../docs/platform-observability.md).

---

## OBS.T01 — OAM sink policy widened

**STRIDE:** Information Disclosure
**Description:** The OAM Sink resource policy currently lists explicit workload-account ARNs. A change to `Principal: "*"` without an `aws:PrincipalOrgID` condition lets external principals create OAM Links into the sink.
**Attack path:** Principal with `oam:UpdateSink` permission in the observability account loosens the policy.
**Impact:** External principals gain read access to aggregated logs, metrics, traces.
**Current controls:** Explicit account list (see `observability.yaml`).
**Mitigations to consider:** AWS Config rule monitoring OAM sink policy; periodic diff check; CloudTrail alarm on `oam:UpdateSink`; document the two valid shapes (explicit list vs. `*` + `aws:PrincipalOrgID`) and forbid a policy with `*` and no org condition.
**Residual risk:** TBD

---

## OBS.T02 — Sensitive content in logs / traces

**STRIDE:** Information Disclosure
**Description:** Agent logs, tool invocation logs, and X-Ray traces can contain user-submitted content (potentially PII or secrets) or internal context. Aggregated to observability account in enterprise, broadening the exposure.
**Attack path:** Passive — content naturally flows to CloudWatch.
**Impact:** Exposure scope = observability-account read principals.
**Current controls:** Agent/Runtime default logging behavior.
**Mitigations to consider:** Log scrubbing in agent code; ban specific fields from going to logs; Macie or similar PII scanner on the observability-account log groups; shorter log retention for high-sensitivity environments.
**Residual risk:** TBD

---

## OBS.T03 — Log tampering / deletion

**STRIDE:** Tampering, Repudiation
**Description:** A compromised principal deletes log groups, streams, or X-Ray trace data in a workload account before it's aggregated to observability.
**Attack path:** `logs:DeleteLogGroup` / `xray:*` in a workload account, if the compromised role has those permissions.
**Impact:** Audit gap; incident-response blind spot.
**Current controls:** Runtime/Lambda roles do not normally have `logs:Delete*` privileges.
**Mitigations to consider:** SCPs denying `logs:Delete*`, `logs:PutRetentionPolicy` below a minimum, and `xray:DeleteResourcePolicy` outside admin roles; shipping critical logs to the security-account CloudTrail bucket for longer retention.
**Residual risk:** TBD

---

## OBS.T04 — OAM link hijack via lifecycle drift

**STRIDE:** Tampering
**Description:** An OAM Link in a workload account is deleted + re-created pointing to a different (attacker-controlled) sink.
**Attack path:** Principal with `oam:DeleteLink` + `oam:CreateLink` in a workload account.
**Impact:** Telemetry redirected; observability account sees no data; attacker sees all of it.
**Current controls:** Link is CFN-managed; drift would surface on next deploy.
**Mitigations to consider:** AWS Config rule on OAM Links; alert on `oam:CreateLink` with a non-canonical sink ARN.
**Residual risk:** TBD

---

## OBS.T05 — Transaction Search misconfiguration / disablement

**STRIDE:** Denial of Service (observability), Repudiation
**Description:** `UpdateTraceSegmentDestination` to CloudWatchLogs is required for AgentCore span ingestion used by the eval framework. If disabled or pointed elsewhere, evals cannot score traces and troubleshooting loses visibility.
**Attack path:** Principal with `xray:UpdateTraceSegmentDestination` disables ingestion.
**Impact:** Evals produce zero-score results (see the "fresh account first run" issue documented earlier); incident analysis blind.
**Current controls:** `deploy.sh` polls `GetTraceSegmentDestination` for `ACTIVE` after deploy.
**Mitigations to consider:** AWS Config rule on the X-Ray destination; alert on `xray:UpdateTraceSegmentDestination`.
**Residual risk:** TBD