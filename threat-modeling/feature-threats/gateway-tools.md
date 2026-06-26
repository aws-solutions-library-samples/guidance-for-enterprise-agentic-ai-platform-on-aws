<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Gateway & Tools (GW)

Threats to the AgentCore Gateway, MCP protocol layer, and the Lambda functions registered as Gateway tool targets.

Related docs: [docs/agentcore-gateway.md](../../docs/agentcore-gateway.md), [docs/agentcore-auth.md](../../docs/agentcore-auth.md).

---

## GW.T01 — Tool authorization bypass

**STRIDE:** Elevation of Privilege
**Description:** A caller invokes a tool they should not have access to — either because Gateway's authorization config is permissive, or because the Lambda target does not re-check authorization.
**Attack path:** Authenticated Runtime (or stolen OAuth2 token) calls Gateway for a tool intended for a different scope.
**Impact:** Unauthorized tool execution; potential data exfiltration or side-effect abuse.
**Current controls:**
- Gateway validates JWT/OAuth2 token signature and audience before dispatch.
**Mitigations to consider:** Per-tool scope claims; Lambda-side re-authorization using the JWT `scope` / `client_id`; tool-level resource policies.
**Residual risk:** TBD

---

## GW.T02 — Tool response injection

**STRIDE:** Tampering
**Description:** A tool Lambda returns content that the Runtime/model treats as instructions (see also RT.T02). Especially dangerous for tools that fetch external data.
**Attack path:** External source compromised → tool returns that content → agent acts on instructions.
**Impact:** See RT.T02.
**Current controls:** None beyond agent-level prompt engineering.
**Mitigations to consider:** Sanitize/escape tool output; wrap tool output in a clearly-bounded section in the model context.
**Residual risk:** TBD

---

## GW.T03 — Tool Lambda IAM over-privilege

**STRIDE:** Elevation of Privilege
**Description:** A Gateway tool Lambda has broader IAM permissions than the tool logic requires. An attacker who can coerce the agent to call the tool with specific inputs could abuse the Lambda's IAM for lateral access.
**Attack path:** Prompt injection → crafted tool call → Lambda executes against an unintended resource using its over-broad role.
**Impact:** Data access, resource manipulation proportional to the Lambda's role.
**Current controls:** Sample tool (text analysis) has minimal permissions.
**Mitigations to consider:** Per-tool IAM with resource-level constraints; deny wildcards; periodic Access Analyzer review.
**Residual risk:** TBD

---

## GW.T04 — Lambda target tampering

**STRIDE:** Tampering
**Description:** The Lambda code backing a registered tool is replaced with malicious code (e.g. by someone with Lambda UpdateFunctionCode permission).
**Attack path:** Compromised CI principal, or a stolen IAM session in shared-tooling with Lambda write, updates tool Lambda directly (bypassing the pipeline).
**Impact:** All agent tool calls via that tool are compromised.
**Current controls:** Lambda function deployed via CDK; in principle any drift would be reverted on next deploy.
**Mitigations to consider:** CloudTrail detection on `lambda:UpdateFunctionCode` outside the pipeline role; AWS Config rule for Lambda immutability; signed Lambda functions; treat Lambda code deployments as privileged.
**Residual risk:** TBD

---

## GW.T05 — Gateway endpoint exposure

**STRIDE:** Information Disclosure
**Description:** Gateway URL and machine client ID are not secret, but gateway discovery without M2M token should reject. A misconfigured Gateway that accepts unauthenticated pings or echoes tool metadata publicly is a surface.
**Attack path:** Unauthenticated request to Gateway URL.
**Impact:** Tool enumeration, possibly invocation.
**Current controls:** Gateway requires JWT/OAuth2 token on every request.
**Mitigations to consider:** Periodic unauth probe as part of smoke test to confirm 401s; log and alert on anomalous 401 patterns.
**Residual risk:** TBD

---

## GW.T06 — MCP protocol vulnerability

**STRIDE:** Tampering, Information Disclosure
**Description:** A vulnerability in the MCP library or AgentCore Gateway's MCP handler (injection, deserialization, oversized response DoS).
**Attack path:** Crafted MCP request from a compromised or hostile client.
**Impact:** Depends on vulnerability class.
**Current controls:** AWS-managed Gateway; AgentCore team patches.
**Mitigations to consider:** Keep AgentCore SDK and gateway up to date; subscribe to Bedrock AgentCore security advisories.
**Residual risk:** TBD