<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# System Overview

## Scope

This threat model covers the Guidance for Agentic AI Platform on AWS, in both deployment tiers. The platform is built on Amazon Bedrock AgentCore, which provides the following components:

- **Single-account** — all components in one account
- **Enterprise multi-account** — mgmt + security + observability + shared-tooling + dev + staging + prod (7 accounts)

## Components

### Agent plane (runs in workload account: dev/staging/prod in enterprise, or the single account in single-tier)

- **AgentCore Runtime** — containerized Strands agent, invoked via `bedrock-agentcore:InvokeAgentRuntime`. Handles the agent loop, calls Bedrock for model inference, calls Gateway for tools.
- **AgentCore Memory** — conversation history per session. Session-scoped isolation provided by AgentCore.
- **AgentCore Code Interpreter** — Python sandbox invoked by the agent for code execution.

### Shared services (runs in shared-tooling account in enterprise, or the single account in single-tier)

- **Amazon Cognito User Pool** — end-user authentication (JWT). Machine client for OAuth2 M2M.
- **AgentCore Identity** — Token Vault storing OAuth2 client secrets. OAuth2 Credential Provider issues access tokens to Runtime.
- **AgentCore Gateway** — MCP-protocol gateway. Accepts JWT-authenticated requests from Runtime, routes tool calls to Lambda targets.
- **Gateway Tool Lambdas** — individual Lambda functions that implement MCP tools. Invoked by Gateway with JWT context.

### Platform plane

- **CodeCommit** — agent source repo (enterprise). Scaffolded by `deploy.sh enterprise`.
- **CodePipeline** — promotion pipeline: Source → Build → DeployDevAndEval → ApproveStaging → DeployStaging → ApproveProd → DeployProd.
- **CodeBuild** — runs CDK deploy + `pipeline_eval.py` in each stage.
- **ECR** — container images for agent runtimes.
- **SSM Parameter Store** — non-secret config (runtime ARNs, account IDs, gateway URLs).
- **Secrets Manager** — OAuth2 client secrets, pipeline eval credentials.

### Security / observability plane

- **CloudTrail** (security account) — org-wide audit log.
- **KMS** (security account) — customer-managed key for security data.
- **CloudWatch OAM Sink** (observability account) — aggregates metrics, logs, X-Ray from every workload account via OAM Links.
- **StackSet Admin Role** (management account) — used by `deploy.sh enterprise` to deploy platform StackSets into member accounts via `OrganizationAccountAccessRole`.

## Trust Boundaries

```
┌────────────────────────────────────────────────────────────────────────┐
│ AWS Organization                                                       │
│                                                                        │
│  ┌────────────┐     StackSets via                                      │
│  │ Management │────►OrganizationAccountAccessRole───►(all member a/cs) │
│  └────────────┘                                                        │
│                                                                        │
│  ┌────────────┐  ┌──────────────┐  ┌────────────┐                      │
│  │  Security  │  │ Observability│  │Shared Tool │                      │
│  │ CloudTrail │  │  OAM Sink ◄──┼──┤  CICD      │                      │
│  │    KMS     │  │  Dashboards  │  │  Cognito   │                      │
│  └────────────┘  └──────────────┘  │  Identity  │                      │
│                         ▲          │  Gateway   │                      │
│                         │ OAM Link │  ECR, SSM  │                      │
│                         │          │  Secrets   │                      │
│                         │          └─────┬──────┘                      │
│                         │                │ JWT (end users)             │
│                         │                │ OAuth2 M2M (Runtime→GW)     │
│                         │                ▼                             │
│                         │    ┌──────┐ ┌──────┐ ┌──────┐                │
│                         └────┤ Dev  │ │ Stg  │ │ Prod │                │
│                              │Runtime│ │Runtime│ │Runtime│             │
│                              │Memory │ │Memory │ │Memory │             │
│                              └───┬──┘ └───┬──┘ └───┬──┘                │
│                                  │        │        │                   │
│                                  └────────┴────────┘                   │
│                                   invokes Gateway (MCP)                │
│                                   via OAuth2 M2M token                 │
└────────────────────────────────────────────────────────────────────────┘

                  ▲
                  │ (JWT) End users
                  │
              ┌───┴───┐
              │ Client│
              └───────┘
```

Key trust boundaries:

1. **Internet → Cognito/Gateway** — untrusted callers; JWT validation is the gate.
2. **Cognito → AgentCore Runtime** — Runtime trusts only tokens minted by the known Cognito pool.
3. **Runtime → Gateway** — M2M boundary; OAuth2 client credentials via Identity Token Vault.
4. **Gateway → Tool Lambda** — Gateway decides which tool to invoke; Lambda trusts Gateway's JWT context.
5. **Workload account → Observability account** — one-way OAM Link (read-only).
6. **Management account → Member accounts** — `OrganizationAccountAccessRole` (full admin via StackSets). Highest-impact boundary in the enterprise tier.
7. **Workload account → Shared-Tooling account** — Runtime consumes Gateway + Cognito + ECR. No admin path back.

## Actors

| Actor | Where they sit | Trust level |
|-------|---------------|-------------|
| End user | Internet → Cognito JWT | Untrusted; authenticated after JWT |
| Machine client | Workload (Runtime) → Shared-Tooling (Gateway) via OAuth2 | Semi-trusted service-to-service |
| Agent developer | CodeCommit pusher | Trusted; push triggers deploy pipeline |
| Platform operator | `./scripts/deploy.sh` from mgmt (enterprise) or target account (single) | Highly trusted; has admin on target |
| CodeBuild (pipeline) | Executes agent deploys + evals | Trusted within scoped IAM role |
| Attacker (external) | Internet, with or without a Cognito user | Untrusted |
| Attacker (internal) | Compromised dev credentials, stolen JWT, or a compromised workload IAM role | Variable scope of damage |

## Assumptions

- AWS Organizations and Control Tower (or equivalent) are correctly configured for the enterprise tier.
- `OrganizationAccountAccessRole` in each member account trusts only the management account root (this is the default).
- Bedrock model access is already granted in the target regions.
- Cognito end-user sign-up flow is controlled (not self-service in production).
- No secrets are stored in the agent source repo — all secrets come from Secrets Manager / Identity Token Vault.

## Out of Scope

- AWS service implementation vulnerabilities (Bedrock, Cognito, Lambda, CDK, etc.) — these are AWS's responsibility under the shared responsibility model.
- Network-layer DDoS against AWS public endpoints — AWS Shield Standard baseline applies.
- Physical security of AWS data centers.
- Customer Bedrock model behavior (jailbreaking the model itself, as opposed to prompt injection in the app layer) — mitigate with Bedrock Guardrails if needed.
- Threats specific to customer agent code that is added later (outside the reference `strands-single-agent` pattern).
