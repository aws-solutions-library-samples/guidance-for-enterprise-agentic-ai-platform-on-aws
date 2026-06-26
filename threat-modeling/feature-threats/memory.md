<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Memory (MEM)

Threats to Amazon Bedrock AgentCore Memory — conversation history storage, session isolation, and memory-driven agent behavior.

Related docs: [docs/agentcore-memory.md](../../docs/agentcore-memory.md).

---

## MEM.T01 — Cross-session / cross-user memory leakage

**STRIDE:** Information Disclosure
**Description:** Session keyspace is not bound to user subject; a crafted or stolen session ID reads another user's conversation.
**Attack path:** See RT.T04.
**Impact:** Disclosure of prior turns, including any sensitive context.
**Current controls:** AgentCore Memory is session-scoped; Memory ARN is per-agent.
**Mitigations to consider:** Bind session ID to JWT `sub` in agent code; audit for session-ID-as-URL-parameter patterns in clients.
**Residual risk:** TBD — verify binding behavior.

---

## MEM.T02 — Memory poisoning

**STRIDE:** Tampering
**Description:** An earlier turn (or an attacker with write access) seeds memory with content that influences future agent behavior (persistent prompt injection across turns).
**Attack path:** Prompt injection in turn N becomes part of conversation history → re-fed to the model in turn N+1.
**Impact:** Persistent manipulation, possibly survives across sessions if using long-term memory strategies.
**Current controls:** Default memory configuration is per-session only (no long-term).
**Mitigations to consider:** If enabling long-term memory strategies (summaries, preferences, semantic), review what gets persisted; sanitize or truncate risky content before write.
**Residual risk:** TBD

---

## MEM.T03 — Memory retention beyond compliance window

**STRIDE:** Information Disclosure (regulatory)
**Description:** Conversation memory retained longer than the data's intended lifecycle.
**Attack path:** Passive — misconfigured retention policy.
**Impact:** Regulatory or policy violation; larger attack surface if storage is compromised.
**Current controls:** AgentCore Memory TTL applies per memory strategy.
**Mitigations to consider:** Document retention; set explicit TTLs; schedule periodic purge; verify that delete-user workflows cover memory.
**Residual risk:** TBD

---

## MEM.T04 — Memory ARN exposure / confusion

**STRIDE:** Information Disclosure, Tampering
**Description:** The Memory ARN is stored in SSM (non-secret) and used by Runtime. A misconfiguration that points a Runtime at a different agent's Memory would cross-pollute data.
**Attack path:** Incorrect CDK config or drift between deployments in the same account.
**Impact:** Data mixing between agents.
**Current controls:** Memory is created per agent stack in CDK; SSM key includes agent name.
**Mitigations to consider:** Unit/integration tests verifying SSM key → Memory ARN matches the agent stack name.
**Residual risk:** TBD
