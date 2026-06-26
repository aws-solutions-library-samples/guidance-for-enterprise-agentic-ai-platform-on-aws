<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Architecture

## Enterprise — 7 Account Setup

Management + Security + Observability + Shared-Tooling + Dev + Staging + Prod.

```mermaid
flowchart TB
    subgraph org["AWS Organization"]
        subgraph mgmt["Management Account"]
            orgs[AWS Organizations]
            scps[SCPs]
            budget[Budget Alarms]
            stacksets[StackSet Admin Role]
        end

        subgraph sec["Security Account"]
            trail[CloudTrail]
            kms[AWS KMS Key]
            findings[Security Findings Bucket]
            audit_s3[Audit Trail Bucket]
        end

        subgraph obs["Observability Account"]
            cw_dash[CloudWatch Dashboards]
            cw_alarms[CloudWatch Alarms]
            cw_logs[Centralized Log Groups]
            oam_sink[OAM Sink]
        end

        subgraph st["Shared Tooling Account"]
            direction TB
            cognito[Cognito User Pool]
            identity[AgentCore Identity]
            gw[AgentCore Gateway - MCP]
            oauth[OAuth2 Credential Provider]
            registry[Agent Registry - DynamoDB]
            ecr[Shared ECR Repository]
            cicd_pipeline[CodePipeline - dev→staging→prod]
            codecommit[CodeCommit - agents repo]
            ssm_st[SSM Parameters]
        end

        subgraph dev["Dev Account"]
            runtime_d[AgentCore Runtime]
            memory_d[AgentCore Memory]
        end

        subgraph stg["Staging Account"]
            runtime_s[AgentCore Runtime]
            memory_s[AgentCore Memory]
        end

        subgraph prod["Prod Account"]
            runtime_p[AgentCore Runtime]
            memory_p[AgentCore Memory]
        end
    end

    mgmt -->|creates accounts| sec & obs & st & dev & stg & prod
    stacksets -->|deploys stacks| sec & obs & st & dev & stg & prod

    cognito -->|JWT auth| gw
    oauth -->|M2M tokens| gw
    identity -->|workload identity| runtime_d & runtime_s & runtime_p

    cicd_pipeline -->|deploy| runtime_d
    cicd_pipeline -.->|promote| runtime_s
    cicd_pipeline -.->|promote| runtime_p

    runtime_d & runtime_s & runtime_p -->|invoke tools via| gw
    runtime_d -->|read/write| memory_d
    runtime_s -->|read/write| memory_s
    runtime_p -->|read/write| memory_p

    runtime_d & runtime_s & runtime_p -.->|metrics, logs, traces| oam_sink

    trail -->|logs| audit_s3

    style mgmt fill:#fff3e0,color:#000
    style sec fill:#fce4ec,color:#000
    style obs fill:#f3e5f5,color:#000
    style st fill:#e3f2fd,color:#000
    style dev fill:#e8f5e9,color:#000
    style stg fill:#e8f5e9,color:#000
    style prod fill:#e8f5e9,color:#000
```

## AgentCore Component Placement

```mermaid
flowchart LR
    subgraph st2["Shared Tooling Account"]
        direction TB
        C[Cognito]
        I[AgentCore Identity]
        G[AgentCore Gateway]
        O[OAuth2 Provider]
        T[Tool Targets - Lambda]

        C --> I
        I --> O
        O --> G
        G --> T
    end

    subgraph dev2["Dev Account"]
        direction TB
        R[AgentCore Runtime]
        M[AgentCore Memory]
        A[Agent Code]

        A --> R
        R --> M
    end

    G <-->|MCP protocol| R
    C -.->|JWT validation| R

    style st2 fill:#e3f2fd,color:#000
    style dev2 fill:#e8f5e9,color:#000
```

## Component Placement Summary

| Component | Account | Purpose |
|-----------|---------|---------|
| Cognito | Shared Tooling | User pools, M2M auth, OAuth2 flows |
| AgentCore Identity | Shared Tooling | Workload identity, token vault |
| AgentCore Gateway | Shared Tooling | MCP protocol, tool discovery, JWT auth |
| OAuth2 Credential Provider | Shared Tooling | Runtime-to-Gateway authentication |
| AgentCore Runtime | Dev / Staging / Prod | Agent execution (container or zip) |
| AgentCore Memory | Dev / Staging / Prod | Session history, summarization strategies |
| Agent Registry | Shared Tooling | DynamoDB registry of deployed agents |
| Agent Images (ECR) | Shared Tooling | Shared container repository |
| CI/CD Pipeline | Shared Tooling | CodeCommit → CodePipeline → CodeBuild, promotes dev → staging → prod |

## Platform Component Placement

| Component | Account | Purpose |
|-----------|---------|---------|
| AWS Organizations | Management | OUs, SCPs, billing |
| CloudTrail | Security | Audit trail, log validation |
| AWS KMS | Security | Encryption for security data |
| CloudWatch Dashboards | Observability | Agent metrics, latency, token usage |
| CloudWatch Alarms | Observability | Error rate, latency, token budget |
| OAM Sink | Observability | Aggregates metrics, logs, and X-Ray traces from all workload accounts |
| Cross-Account Roles | All | StackSet deployment, telemetry sharing |

## Deployment Flow

Enterprise deploys in a single pass from the management account via `./scripts/deploy.sh enterprise`.

```mermaid
flowchart TD
    A[./scripts/deploy.sh enterprise] -->|runs in management account| B[Management Account]
    B -->|StackSets| C[Security]
    B -->|StackSets| D[Observability]
    B -->|StackSets| E[Shared Tooling]
    B -->|StackSets| F[Dev]
    B -->|StackSets| G[Staging]
    B -->|StackSets| H[Prod]

    A -->|assumes into shared-tooling| I[Auth Layer<br/>Cognito · Identity · Gateway]
    I --> E
    A -->|assumes into dev/staging/prod| J[Workload Layer<br/>Runtime · Memory]
    J --> F
    J --> G
    J --> H

    style A fill:#fff3e0,color:#000
    style B fill:#fff3e0,color:#000
```

1. Platform stacks are deployed per account via CloudFormation StackSets from the management account.
2. AgentCore auth layer (Cognito, Identity, Gateway) is deployed into shared-tooling.
3. AgentCore workload layer (Runtime, Memory) is deployed into dev, staging, and prod.
4. Agents are deployed as container images or zip packages to AgentCore Runtime via the CI/CD pipeline (CodeCommit → CodePipeline → CodeBuild) owned by shared-tooling.

For single-account, the equivalent entry point is `./scripts/deploy.sh single`, which deploys both the platform CFN stack and the AgentCore CDK stacks into the current account.
