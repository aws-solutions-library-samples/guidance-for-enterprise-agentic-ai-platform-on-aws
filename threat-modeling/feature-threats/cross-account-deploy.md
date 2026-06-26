<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Cross-Account Deploy (DEPLOY)

Threats specific to the enterprise-tier deploy mechanism: StackSets from the management account, `OrganizationAccountAccessRole` assumption, and per-target platform deploys. Does not apply to single-tier.

Related docs: [docs/platform-deployment.md](../../docs/platform-deployment.md).

---

## DEPLOY.T01 — OrganizationAccountAccessRole abuse

**STRIDE:** Elevation of Privilege
**Description:** `OrganizationAccountAccessRole` in each member account grants `AdministratorAccess`, trusted by the management account root. Anyone in the management account with `sts:AssumeRole` on this role gains admin in every member account.
**Attack path:** Compromised management-account principal → assumes the role into any workload → acts as full admin.
**Impact:** Full control over any member account. This is the single highest-impact boundary in the enterprise tier.
**Current controls:**
- Role exists per account standard; trust policy defaults to management-account root.
- `deploy.sh enterprise` verifies assume-ability at start of run.
**Mitigations to consider:** SCP restricting non-deploy principals from assuming `OrganizationAccountAccessRole`; break-glass procedures for management account access; MFA + short session on management-account roles; CloudTrail alarm on assume-role events to this role outside deploy windows.
**Residual risk:** TBD

---

## DEPLOY.T02 — StackSet admin role abuse

**STRIDE:** Elevation of Privilege
**Description:** `AWSCloudFormationStackSetAdministrationRole` in the management account can call `sts:AssumeRole` on the `OrganizationAccountAccessRole` in any member. A principal that can use this role can deploy arbitrary CFN to every account.
**Attack path:** Compromised principal with pass-role on the StackSet admin role → creates a malicious StackSet.
**Impact:** Lateral deploy of attacker-controlled stacks.
**Current controls:** Role is provisioned during deploy; service principal trust restricts to CloudFormation service.
**Mitigations to consider:** Audit trust policy; restrict `iam:PassRole` on this role to known deploy principals; CloudTrail alarm on `CreateStackSet` / `UpdateStackSet` events.
**Residual risk:** TBD

---

## DEPLOY.T03 — Trust-policy drift in member accounts

**STRIDE:** Elevation of Privilege, Repudiation
**Description:** A new trusted principal is added to `OrganizationAccountAccessRole` trust policy in a member account (manually or via an out-of-band deploy), expanding the set of principals that can take over that account.
**Attack path:** Someone with IAM admin in a member account adds their own external account as a trusted principal.
**Impact:** Persistent, hard-to-detect lateral access path.
**Current controls:** None by default.
**Mitigations to consider:** AWS Config rule `IAM_ROLE_TRUST_POLICY` monitoring for unexpected principals; periodic assertion script (the deploy script already verifies the role is assumable — extend to verify trust policy shape).
**Residual risk:** TBD

---

## DEPLOY.T04 — CFN template tampering

**STRIDE:** Tampering
**Description:** Someone modifies the CFN template uploaded during deploy (local disk, S3 bootstrap bucket) between the operator's view and CloudFormation's parse.
**Attack path:** Malicious code on operator's machine; compromised CDK/CLI install.
**Impact:** Arbitrary resources deployed with admin-scope across the org.
**Current controls:** None beyond operator-device integrity.
**Mitigations to consider:** Run deploys from a clean CloudShell/CodeBuild environment; sign CFN artifacts; review ChangeSets before execute-changeset (currently auto-executed).
**Residual risk:** TBD

---

## DEPLOY.T05 — SCP bypass via deploy scope

**STRIDE:** Elevation of Privilege
**Description:** The deploy role is admin-scoped (necessary for StackSets). If SCPs attempt to restrict certain actions org-wide, the deploy runs as a principal that could plausibly be whitelisted, and becomes a way to bypass SCPs.
**Attack path:** Attacker with deploy-role access uses a crafted template to touch resources that are otherwise SCP-denied.
**Impact:** Policy-in-theory vs. effective-policy mismatch.
**Current controls:** SCPs not configured out of the box.
**Mitigations to consider:** Explicit SCPs with `aws:PrincipalArn != management-account:*` conditions where feasible; limit what the deploy role can touch beyond CFN/StackSets.
**Residual risk:** TBD