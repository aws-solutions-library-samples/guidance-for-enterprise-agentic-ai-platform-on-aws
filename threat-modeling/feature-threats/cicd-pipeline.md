<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# CI/CD Pipeline (CICD)

Threats to the CodeCommit → CodePipeline → CodeBuild promotion pipeline that deploys agents across dev, staging, and prod (enterprise) or a single account (single-tier). Includes evaluation gates and manual approvals.

Related docs: [docs/platform-deployment.md](../../docs/platform-deployment.md), [docs/agentcore-evaluation.md](../../docs/agentcore-evaluation.md).

---

## CICD.T01 — Artifact tampering in pipeline bucket

**STRIDE:** Tampering
**Description:** The S3 pipeline artifact bucket holds source snapshots, build outputs, and eval results. An attacker who can write to this bucket can replace artifacts mid-pipeline.
**Attack path:** Compromised principal with `s3:PutObject` on the artifact bucket → overwrites `BuildOutput` between stages.
**Impact:** Arbitrary code promoted through staging → prod.
**Current controls:** Pipeline artifact bucket in shared-tooling; default IAM scopes.
**Mitigations to consider:** S3 versioning + MFA delete; bucket policy denying `PutObject` by non-pipeline principals; Object Lock with governance mode for compliance workloads.
**Residual risk:** TBD

---

## CICD.T02 — Evaluation gate bypass

**STRIDE:** Tampering
**Description:** `pipeline_eval.py` evaluates an agent after deploy; failures block promotion. An attacker who can tamper with the eval (modify `pipeline_eval.py`, modify eval cases, or skip the stage) pushes unreviewed code forward.
**Attack path:** Developer with push access to the agent repo edits `scripts/pipeline_eval.py` or empties `agents/<name>/eval/` directory → eval produces a PASS on any input.
**Impact:** Broken / malicious agents reach staging/prod.
**Current controls:**
- `pipeline_eval.py` is in the scaffolded agent repo (under developer control).
- Manual approval gates before staging and prod deploy.
**Mitigations to consider:** Treat the eval harness as pipeline-owned, not agent-owned — source it from a separate protected location or a shared-tooling-controlled layer; require code review on the agent repo; validate that eval case counts > 0 before running; audit changes to `pipeline_eval.py`.
**Residual risk:** TBD

---

## CICD.T03 — Pipeline role assumption by human

**STRIDE:** Elevation of Privilege
**Description:** The pipeline's CodeBuild role has cross-account deploy + Cognito + Gateway access. A human user assumes this role directly and bypasses pipeline gates entirely (no eval, no approval).
**Attack path:** IAM principal with `sts:AssumeRole` on the pipeline role deploys straight to prod.
**Impact:** Bypass of every pipeline gate; ability to deploy arbitrary code and evade approvals.
**Current controls:** Role trust policy includes CodeBuild service principal; if `Service: codebuild.amazonaws.com` is the only trusted principal, humans cannot assume directly.
**Mitigations to consider:** Verify trust policy is CodeBuild-service-only (no `arn:aws:iam::*:user/*` or `root`); CloudTrail alarm on `AssumeRole` for this role from non-CodeBuild sources.
**Residual risk:** TBD

---

## CICD.T04 — Source-stage poisoning

**STRIDE:** Tampering, Spoofing
**Description:** A compromised developer credential pushes to `main` in CodeCommit, triggering a deploy with attacker code.
**Attack path:** Stolen IAM credential or SSH key with `codecommit:GitPush` → push malicious commit to `main`.
**Impact:** Pipeline runs attacker code; eval gates may still catch basic functional failures but not security-relevant changes.
**Current controls:** CodeCommit IAM-based auth; all pushes logged.
**Mitigations to consider:** Require MFA on CodeCommit-push principals; enforce pull-request workflow via a protected-branch equivalent (CodeCommit approval rules); git commit signing + enforcement.
**Residual risk:** TBD

---

## CICD.T05 — Manual approval misuse

**STRIDE:** Repudiation, Elevation of Privilege
**Description:** `ApproveStaging` and `ApproveProd` are human gates. An approver who approves without review, or whose credentials are compromised, lets malicious code through.
**Attack path:** Social engineering, stolen console credential, or approver fatigue.
**Impact:** Same as CICD.T04.
**Current controls:** Manual approvals are logged in CloudTrail.
**Mitigations to consider:** Require different approvers for staging vs. prod; MFA on approver principals; out-of-band approval notifications with the changeset summary.
**Residual risk:** TBD

---

## CICD.T06 — ECR image tampering

**STRIDE:** Tampering
**Description:** An attacker replaces a container image in the shared ECR after build. The Runtime pulls the tampered image on next deploy or cold start.
**Attack path:** Principal with `ecr:PutImage` on the agent repo pushes a tag over an existing one.
**Impact:** Malicious code running inside AgentCore Runtime.
**Current controls:** ECR access is IAM-controlled; build pushes images tagged with commit SHA.
**Mitigations to consider:** ECR tag immutability enabled; image signing (Notary / Signer); scan-on-push + policy block on critical CVEs; `ecr:BatchDeleteImage` and `ecr:PutImage` restricted to pipeline role.
**Residual risk:** TBD

---

## CICD.T07 — Eval flakiness masking real failures

**STRIDE:** Tampering (indirect)
**Description:** The `OnFailure: RETRY` on the deploy+eval stage auto-retries once to mop up cold-start span-ingestion flakiness. A retry also masks a real regression if the second attempt passes by chance.
**Attack path:** Passive — a flaky eval + real regression look identical to the pipeline.
**Impact:** Lowered eval signal strength.
**Current controls:** Retry is exactly once, then failure is surfaced.
**Mitigations to consider:** Flag "first-attempt failed, second-attempt passed" cases for human review; track eval scores over time to catch regressions the pass/fail threshold misses.
**Residual risk:** TBD