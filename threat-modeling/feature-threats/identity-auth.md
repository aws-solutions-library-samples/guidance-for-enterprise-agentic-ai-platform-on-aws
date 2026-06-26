<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Identity & Authentication (AUTH)

Threats to Cognito User Pool (end-user auth), AgentCore Identity (machine identity + Token Vault), OAuth2 Credential Provider (M2M tokens), and the pipeline-eval user credential path.

Related docs: [docs/agentcore-auth.md](../../docs/agentcore-auth.md), [docs/platform-security.md](../../docs/platform-security.md).

---

## AUTH.T01 — JWT theft and replay

**STRIDE:** Spoofing
**Description:** A valid Cognito JWT is stolen (browser XSS, insecure storage, client-side leak) and replayed.
**Attack path:** Attacker obtains token → calls Runtime impersonating the user.
**Impact:** Full user-level access for the token's lifetime.
**Current controls:** Cognito short-lived access tokens (1h default); HTTPS everywhere.
**Mitigations to consider:** Shorten token TTL; enable Cognito Advanced Security (risk-based auth); audit unusual IP / UA changes; avoid storing tokens in `localStorage`.
**Residual risk:** TBD

---

## AUTH.T02 — OAuth2 client secret exposure

**STRIDE:** Spoofing
**Description:** The Cognito machine-client secret (used for Runtime→Gateway M2M) leaks — e.g. from a secret scanner miss, stored in a build log, or read by an over-permissive IAM principal.
**Attack path:** Attacker with the secret can mint tokens and call Gateway directly, bypassing Runtime.
**Impact:** Gateway tools invokable by attacker with full machine-client scope.
**Current controls:** Secret stored in AgentCore Identity Token Vault; no env vars, no source code.
**Mitigations to consider:** Rotate periodically; alert on unusual token-issuance rate; scope Gateway tools by `client_id` with least privilege; CloudTrail alerting on `DescribeUserPoolClient` calls from unexpected principals.
**Residual risk:** TBD

---

## AUTH.T03 — Privilege escalation via custom Cognito claims

**STRIDE:** Elevation of Privilege
**Description:** Agent code or Gateway authorization reads custom claims from the JWT without verifying integrity, and the attacker modifies the token (offline decoded + re-encoded with attacker claims) if signature verification is skipped.
**Attack path:** Token manipulation + missing signature check.
**Impact:** Impersonation, role claim escalation.
**Current controls:** AgentCore verifies JWT signature and `kid` rotation via Cognito JWKS.
**Mitigations to consider:** If adding custom claim handling, always re-verify signature + issuer + audience before trusting claims.
**Residual risk:** TBD

---

## AUTH.T04 — Pipeline-eval user credential exposure

**STRIDE:** Spoofing
**Description:** The CodePipeline's on-demand eval authenticates as a Cognito user `pipeline-eval@${PROJECT}.internal` whose password is stored in Secrets Manager. Leakage of this secret gives an attacker a foothold with agent-invoke permissions.
**Attack path:** Secret retrieved from Secrets Manager by an over-permissive principal, or exposed via CodeBuild logs.
**Impact:** Ability to invoke the agent and run evals, bypassing end-user auth.
**Current controls:** Secret stored in Secrets Manager; accessed only by the pipeline role.
**Mitigations to consider:** Restrict `secretsmanager:GetSecretValue` to the pipeline-build role only; rotate on a schedule; scrub CodeBuild output.
**Residual risk:** TBD

---

## AUTH.T05 — Cognito self-signup enabled in production

**STRIDE:** Spoofing
**Description:** If self-signup is enabled in the user pool, any internet user can create an account and get a JWT.
**Attack path:** Attacker signs up → gets valid JWT → invokes the agent.
**Impact:** Bypasses intended access control; makes RT.T06 (cost blowout) trivially reachable.
**Current controls:** Self-signup defaults follow the CDK config; check `cognito-stack.ts`.
**Mitigations to consider:** Ensure self-signup disabled in prod; restrict to admin-create-user; enforce domain-based email verification for a known corporate domain.
**Residual risk:** TBD

---

## AUTH.T06 — Token Vault contents leak via IAM

**STRIDE:** Information Disclosure
**Description:** A principal with `bedrock-agentcore:*` or overly broad Identity Token Vault access reads OAuth2 secrets stored in Vault.
**Attack path:** Compromised IAM session with Vault read permission.
**Impact:** See AUTH.T02.
**Current controls:** Vault IAM controls, no default public access.
**Mitigations to consider:** Least-privilege on Vault read; Access Analyzer; alert on unexpected reads.
**Residual risk:** TBD
