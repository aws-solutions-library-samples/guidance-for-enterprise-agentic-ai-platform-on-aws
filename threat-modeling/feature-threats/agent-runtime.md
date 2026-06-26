<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Agent Runtime (RT)

Threats to the Amazon Bedrock AgentCore Runtime container: the agent loop, model invocation, session handling, and the Runtime IAM role.

Related docs: [docs/agentcore-configuration.md](../../docs/agentcore-configuration.md), [docs/agentcore-streaming.md](../../docs/agentcore-streaming.md).

---

## RT.T01 — Prompt injection via user input

**STRIDE:** Tampering, Elevation of Privilege (via agent actions)
**Description:** User-supplied prompt content includes instructions that cause the model to ignore its system prompt, reveal context, or invoke tools in unintended ways.
**Attack path:** Authenticated user → Runtime → model. Injected content in the prompt steers the agent loop.
**Impact:** Data disclosure (session context, prior turns), unauthorized tool invocation, crafted tool inputs that abuse downstream systems.
**Current controls:**
- Cognito JWT required (limits to authenticated users).
- System prompt in `basic_agent.py` sets role boundaries.
- Gateway independently authorizes tool calls.
**Mitigations to consider:** Bedrock Guardrails, input classification, tool-call allowlists, tool-call rate limits per session.
**Residual risk:** TBD
**References:** OWASP LLM01 Prompt Injection.

---

## RT.T02 — Prompt injection via tool output

**STRIDE:** Tampering
**Description:** A Gateway tool returns content that contains model-directed instructions ("ignore previous instructions…"). The agent treats tool output as trusted context.
**Attack path:** Attacker controls or influences the data source a tool reads from (e.g. a web page fetched by a tool). The tool returns that content verbatim; the agent acts on it.
**Impact:** Downstream tool abuse, data exfiltration, privilege escalation via subsequent tool calls.
**Current controls:**
- Tool responses flow through Gateway unchanged (no sanitization layer by default).
**Mitigations to consider:** Treat tool output as untrusted in the agent's system prompt, delimit tool output in model context, strip/escape control phrases in tool output, Bedrock Guardrails on output path.
**Residual risk:** TBD
**References:** OWASP LLM01.

---

## RT.T03 — Runtime IAM role over-privilege

**STRIDE:** Elevation of Privilege
**Description:** The Runtime role grants broader permissions than the agent needs (e.g. `bedrock:*`, wildcard S3, wildcard Secrets Manager).
**Attack path:** Attacker who achieves code execution inside Runtime (via prompt injection + tool abuse, or container compromise) assumes the Runtime role's full IAM scope.
**Impact:** Lateral movement, data exfiltration, resource tampering limited only by the Runtime role.
**Current controls:**
- Runtime role scoped in `backend-stack.ts` to specific actions (Bedrock invoke, Memory, Gateway, Secrets Manager for OAuth2 secret, Token Vault, CloudWatch Logs).
**Mitigations to consider:** Audit the role periodically with IAM Access Analyzer; remove any `*:*` or cross-resource wildcards; split role by function.
**Residual risk:** TBD

---

## RT.T04 — Session ID spoofing / hijack

**STRIDE:** Spoofing
**Description:** Session ID is client-supplied on invoke. A malicious or buggy client could submit a session ID belonging to another user and, if AgentCore does not tie session to JWT subject, read or overwrite memory.
**Attack path:** Authenticated user A sends request with session ID belonging to user B.
**Impact:** Cross-user memory read or write.
**Current controls:**
- AgentCore Memory is scoped per session. JWT subject is available to the agent.
**Mitigations to consider:** Confirm (via AgentCore docs + integration test) that session-to-subject binding is enforced by the Runtime or by the reference agent code; if not, bind in agent code using JWT `sub` claim as part of session key.
**Residual risk:** TBD — verify behavior.

---

## RT.T05 — Model region/egress misconfiguration

**STRIDE:** Information Disclosure
**Description:** Bedrock model invocations routed to an unintended region, or non-Bedrock outbound traffic from Runtime to an attacker-controlled endpoint.
**Attack path:** Misconfigured `model_id` with cross-region inference profile; or agent code that fetches a URL as part of tool behavior.
**Impact:** Data transfer to unintended region/account; potential compliance violation; exfiltration via HTTP tool abuse.
**Current controls:**
- Bedrock model ID in config; network mode defaults to PUBLIC.
**Mitigations to consider:** VPC network mode with egress only to required endpoints (Bedrock, Gateway); SCP denying Bedrock calls outside allowed regions.
**Residual risk:** TBD

---

## RT.T06 — Denial of wallet via agent loop amplification

**STRIDE:** Denial of Service (economic)
**Description:** A single request triggers a long agent loop with many model invocations and tool calls, running up Bedrock/Gateway costs.
**Attack path:** Authenticated user sends a crafted prompt that induces deep multi-step reasoning or tool-call recursion.
**Impact:** Cost blowout; possible throttling of legitimate traffic.
**Current controls:**
- Strands default max-iterations cap.
**Mitigations to consider:** Hard per-session iteration cap, per-user rate limit at the Runtime or at an API Gateway in front, CloudWatch billing alarms.
**Residual risk:** TBD

---

## RT.T07 — Streaming response tampering

**STRIDE:** Tampering
**Description:** SSE stream modified in-flight.
**Attack path:** Man-in-the-middle — requires TLS compromise or client-side attack.
**Impact:** Altered responses shown to the user.
**Current controls:** HTTPS/TLS end-to-end.
**Mitigations to consider:** None beyond TLS; document to consumers that stream fidelity relies on TLS.
**Residual risk:** TBD
