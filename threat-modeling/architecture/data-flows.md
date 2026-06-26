<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Data Flows

This document enumerates the main data flows in the platform and highlights the security-relevant boundaries each crosses. See [system-overview.md](system-overview.md) for the component layout.

## Flow 1: End-user invokes agent

```
User Browser/Client
    │  1. Sign in to Cognito User Pool (username/password → JWT)
    ▼
Cognito User Pool ──────────► JWT (access_token, id_token)
    │
    │  2. Invoke Runtime
    ▼
AgentCore Runtime (workload account: dev/stg/prod, or single)
    │  Authorizes request against Cognito public keys
    │  Loads session (sessionId) from AgentCore Memory
    │  Starts agent loop
    │
    │  3. Agent calls model
    ▼
Amazon Bedrock (same region)
    │  Returns model tokens
    │
    │  4. Agent calls a tool (optional, repeats)
    ▼
AgentCore Gateway (shared-tooling account in enterprise)
    │  Validates Runtime's OAuth2 access token
    │  Dispatches to registered Lambda target
    ▼
Tool Lambda (shared-tooling account)
    │  Returns tool result
    │
    │  5. Agent writes session state back
    ▼
AgentCore Memory (workload account)
    │
    │  6. Response streamed back
    ▼
User
```

### Security commentary

- **Step 1** — JWT is minted by Cognito; user-pool client ID + audience enforced on verification.
- **Step 2** — Runtime validates JWT before processing. Session ID is user-provided but scoped to the authenticated subject.
- **Step 3** — Bedrock inference happens in-region; no cross-region model calls in this flow.
- **Step 4** — Cross-account hop (in enterprise). Runtime uses a Bearer OAuth2 token obtained from AgentCore Identity. Gateway trusts tokens minted by the known OAuth2 Credential Provider.
- **Step 5** — Memory is strictly per-session. AgentCore enforces isolation by session ID; no cross-session reads.
- **Step 6** — Streaming is SSE over HTTPS; see `docs/agentcore-streaming.md`.

## Flow 2: Runtime → Gateway M2M auth

```
Runtime (cold start or token expiry)
    │
    │  1. Describe credential provider
    ▼
AgentCore Identity (shared-tooling)
    │
    │  2. Request OAuth2 token with client_credentials grant
    ▼
OAuth2 Token Endpoint (Cognito, with machine client ID + secret)
    │  client secret is stored in Identity Token Vault
    │
    │  3. Access token (opaque, short-lived)
    ▼
Runtime caches token in memory
    │
    │  4. Calls Gateway with Authorization: Bearer <token>
    ▼
Gateway
```

### Security commentary

- **Client secret does not touch the Runtime** — it lives in the Token Vault; the Credential Provider issues access tokens on the Runtime's behalf.
- **Token TTL** — short (default Cognito machine-client TTL). No refresh tokens for client_credentials.
- **Scope** — Gateway validates that the token's `client_id` matches the expected machine client.

See `docs/agentcore-auth.md` for the full flow.

## Flow 3: Pipeline agent deploy (enterprise)

```
Agent developer
    │  git push to codecommit::/.../<project>-agents main
    ▼
CodeCommit (shared-tooling)
    │  EventBridge rule → CodePipeline
    ▼
CodePipeline (shared-tooling)
    │
    ├─► Source stage: pulls code into S3 artifact
    │
    ├─► Build stage (CodeBuild): determines changed agents
    │
    ├─► DeployDevAndEval stage (CodeBuild):
    │       assumes cross-account role into dev
    │       cdk deploy <project>-agent-<name> + <project>-gateway
    │       waits for runtime READY
    │       python3 scripts/pipeline_eval.py (authenticates as pipeline-eval user)
    │       if eval fails → stage fails (auto-retry once via OnFailure: RETRY)
    │
    ├─► Manual approval → DeployStaging (CodeBuild, same pattern into staging)
    │
    └─► Manual approval → DeployProd  (CodeBuild, same pattern into prod)
```

### Security commentary

- **Trigger** — push to `main` in CodeCommit. Who can push controls who can trigger a deploy.
- **Cross-account deploy** — CodeBuild assumes a per-target role published by each workload account's platform StackSet.
- **Eval gates** — `pipeline_eval.py` authenticates as a dedicated Cognito user (`pipeline-eval@${PROJECT}.internal`) with its password in Secrets Manager. Failures block promotion.
- **Manual gates** — ApproveStaging and ApproveProd require a human. Audit these via CloudTrail.

See `docs/platform-deployment.md` and `docs/agentcore-evaluation.md`.

## Flow 4: Cross-account observability (enterprise)

```
Runtime / Gateway / Tool Lambda (workload account)
    │  emits metrics, logs, X-Ray traces locally
    ▼
CloudWatch Logs + Metrics + X-Ray (workload account)
    │
    │  OAM Link (one-way)
    ▼
CloudWatch OAM Sink (observability account)
    │
    └─► Dashboards, alarms, Logs Insights, cross-account queries
```

### Security commentary

- **Direction** — read-only from observability into workload. No write-back path; observability cannot inject into workload telemetry.
- **Sink resource policy** — explicit account list (current) or `aws:PrincipalOrgID` (alternative); see `docs/platform-observability.md`.
- **Sensitive content in logs** — depends on agent/user behavior. PII/secrets scrubbing is the agent developer's responsibility.

## Flow 5: Platform deploy

```
Operator shell (mgmt account creds for enterprise, target account creds for single)
    │
    ▼
./scripts/deploy.sh <single|enterprise>
    │
    ├─ single:
    │     aws cloudformation deploy ... (single-account.yaml)
    │     cdk deploy --all (agentcore/infra-cdk)
    │     Scaffold CodeCommit repo, push initial agent
    │     Poll X-Ray: GetTraceSegmentDestination → ACTIVE
    │
    └─ enterprise:
          Assume OrganizationAccountAccessRole into each target
          Deploy StackSets: security, observability, shared-tooling, dev, stg, prod
          Scaffold CodeCommit repo in shared-tooling
          Push initial agent
          Per-workload: poll X-Ray for Transaction Search readiness
```

### Security commentary

- **Single** — runs as the caller's credentials. Scope of impact = caller's IAM.
- **Enterprise** — requires mgmt account credentials. Uses `OrganizationAccountAccessRole` (admin) per target. Highest-privilege operation in the system.
- **Deploy artifacts** — CFN templates and CDK output go through the caller's local filesystem, the CDK bootstrap buckets, and the CodePipeline artifact bucket. Integrity depends on transport (HTTPS) and bucket policies.

## Flow 6: Code Interpreter tool call

```
Agent (Runtime)
    │  "use Code Interpreter to run this Python"
    ▼
AgentCore Code Interpreter (managed sandbox)
    │  Python code runs in isolated environment
    │  no access to host runtime filesystem or network beyond what AgentCore exposes
    ▼
Result returned to agent
```

### Security commentary

- **Sandbox** — AgentCore-managed. Trust boundary is between the agent's Python code and the host runtime.
- **Input source** — code string typically comes from the model's tool call. Model output is user-influenced (prompt injection surface).
- **Output exfiltration** — code can emit anything, including content from prior agent context. Audit logs are in CloudWatch.
