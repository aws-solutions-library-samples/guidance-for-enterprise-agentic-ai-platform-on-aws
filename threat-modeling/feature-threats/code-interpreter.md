<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Code Interpreter (CI)

Threats to the Amazon Bedrock AgentCore Code Interpreter integration. Code Interpreter is AWS-managed; these threats focus on what the platform hands to it and what it returns.

Related docs: [docs/agentcore-tool-code-interpreter.md](../../docs/agentcore-tool-code-interpreter.md).

---

## CI.T01 — Arbitrary code execution via prompt injection

**STRIDE:** Elevation of Privilege (within sandbox)
**Description:** Prompt injection causes the agent to send attacker-crafted Python to Code Interpreter. Code runs in the AWS-managed sandbox, not on Runtime, so scope is sandboxed — but the sandbox is real execution and can emit arbitrary content back to the agent.
**Attack path:** Prompt-injected user input → agent calls Code Interpreter with attacker code → code executes → result returned to agent → agent returns to user (or uses for further tool calls).
**Impact:** Data exfiltration via code output (including context the agent has seen), abuse of any resources Code Interpreter can reach, cost blowout.
**Current controls:**
- AWS-managed sandbox isolates from Runtime host.
- Code Interpreter's network/IO surface is managed by AWS.
**Mitigations to consider:** Agent-level guardrails on *whether* to invoke Code Interpreter for a given input; log and alert on Code Interpreter calls with content patterns matching exfiltration (e.g. prints of environment variables or session metadata); rate-limit Code Interpreter calls per session.
**Residual risk:** TBD

---

## CI.T02 — Data exfiltration via code output

**STRIDE:** Information Disclosure
**Description:** Code executed in the sandbox can print or return any content the agent has provided to it. The agent may be tricked into passing sensitive context (prior turns, retrieved data) to Code Interpreter.
**Attack path:** Prompt injection → agent decides to "compute" on sensitive data → passes data to Code Interpreter → output returned verbatim.
**Impact:** Disclosure of data the agent had legitimate access to, via a channel that looks like a compute result.
**Current controls:** None agent-side by default.
**Mitigations to consider:** System-prompt guidance to not pass raw sensitive context to Code Interpreter; output filtering; audit log reviews for unusual Code Interpreter outputs.
**Residual risk:** TBD

---

## CI.T03 — Sandbox escape (AWS-service-level)

**STRIDE:** Elevation of Privilege
**Description:** A vulnerability in AgentCore Code Interpreter allows code to break out of the sandbox.
**Attack path:** Crafted code designed to exploit the sandbox.
**Impact:** Catastrophic — depends on the escape.
**Current controls:** AWS is responsible for sandbox integrity under the shared responsibility model.
**Mitigations to consider:** Subscribe to Bedrock AgentCore security advisories; SCP-level controls on whether Code Interpreter can be enabled at all for sensitive workloads.
**Residual risk:** TBD — inherently residual to AWS.

---

## CI.T04 — Cost amplification

**STRIDE:** Denial of Service (economic)
**Description:** Agent invokes Code Interpreter with computationally expensive code (cryptomining, infinite recursion, large memory allocation).
**Attack path:** Prompt injection → expensive code → sandbox runs to its limit.
**Impact:** Cost, possibly latency for legitimate users if concurrency-limited.
**Current controls:** Code Interpreter enforces per-invocation resource limits.
**Mitigations to consider:** Per-session/per-user rate limits on Code Interpreter invocations; CloudWatch billing alarms.
**Residual risk:** TBD
