<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Security

When you build systems on AWS infrastructure, you are responsible for security in the cloud, while AWS is responsible for security of the cloud. This [shared responsibility model](https://aws.amazon.com/compliance/shared-responsibility-model/) means AWS secures the underlying infrastructure, while you maintain control and responsibility for securing your content, applications, identity and access management, and network configurations. For more information about AWS security, visit [AWS Cloud Security](https://aws.amazon.com/security/).

## Identity and Access Management

- **Amazon Cognito User Pool**: JWT-based authentication for end users. OAuth2 Client Credentials flow for machine-to-machine auth between AgentCore Runtime and Gateway.
- **AgentCore Identity**: Workload identity and Token Vault for secure credential management. OAuth2 Credential Provider handles Runtime-to-Gateway authentication.
- **IAM Roles**: Least-privilege roles for each component — Runtime, Gateway tool Lambda functions, OAuth2 provider, and cross-account access (enterprise).
- **Cross-Account Roles (Enterprise)**: StackSet admin roles in the management account. Scoped assume-role policies for observability metric sharing and deployment.

## Network Security

### Single Account

- AgentCore Runtime supports `PUBLIC` (default) and `VPC` network modes
- VPC mode deploys the runtime in private subnets with controlled egress
- Gateway tool Lambda functions execute within the AWS Lambda managed network

### Enterprise (Multi-Account)

- Each account operates within its own VPC boundary
- Cross-account communication uses IAM role assumption, not network peering
- NAT gateways provide controlled outbound access to Amazon Bedrock APIs
- No inbound internet access to workload accounts

## Authentication and Authorization

| Flow | Mechanism | Description |
|------|-----------|-------------|
| User → Agent | Amazon Cognito JWT | End users authenticate via Cognito User Pool |
| Runtime → Gateway | OAuth2 Client Credentials | M2M auth via AgentCore Identity Token Vault |
| Gateway → Tools | IAM + JWT | Lambda invocations authorized by Gateway JWT validation |
| Cross-Account | IAM AssumeRole | Enterprise deployments use scoped cross-account roles |

## Data Protection

**AWS Responsibility:**
- Encrypts data at rest in Amazon DynamoDB, Amazon S3, and Amazon CloudWatch Logs using AWS-managed keys by default
- Manages TLS certificates for service endpoints
- Secures the Amazon Bedrock model infrastructure and API endpoints

**Customer Responsibility:**
- Choose between AWS-managed and customer-managed KMS keys based on compliance requirements
- Configure encryption settings in CloudFormation/CDK templates
- Validate that secrets are stored in AWS Secrets Manager or AgentCore Identity Token Vault, not in code or environment variables
- Configure CloudWatch Logs retention periods according to compliance requirements

## Data Classification

| Data Type | Classification | Encryption | Retention | Access |
|-----------|---------------|------------|-----------|--------|
| User credentials | Restricted | KMS + TLS | 90 days | Amazon Cognito service only |
| OAuth2 tokens | Restricted | KMS + TLS | Token TTL | Identity service + Runtime |
| Conversation history | Confidential | KMS + TLS | User-defined | Runtime + Memory service |
| Pipeline artifacts | Internal | KMS + TLS | 30 days | CodeBuild roles only |
| CloudWatch metrics | Internal | AWS-managed | 15 months | Observability account |
| Container images | Internal | KMS | 10 versions | ECR + Runtime |

## Key Management

- **Rotation**: Customer-managed KMS keys have automatic annual rotation enabled (security account)
- **Access**: Keys are scoped per account; only authorized roles have decrypt permissions
- **Lifecycle**: Keys are created during stack deployment and retained on stack deletion for data recovery
- **Separation**: Security data uses a dedicated CMK (`${ProjectName}-security`); pipeline artifacts use the default `aws/s3` key

## Monitoring and Audit

- **AWS CloudTrail**: Organization-wide API audit logging (enterprise). Logs stored in the security account with integrity validation.
- **Amazon CloudWatch Logs**: Agent execution logs, tool invocation logs, and model interaction logs with configurable retention
- **AWS X-Ray Tracing**: Distributed tracing across Runtime, Gateway, and tool invocations
- **Security Findings**: Centralized in the security account (enterprise) with cross-account log aggregation

## AgentCore-Specific Security

- **Runtime Isolation**: Each agent runs in its own containerized environment with no shared state between invocations
- **Gateway Authorization**: MCP-protocol gateway validates JWT tokens on every tool invocation
- **Memory Access Control**: Conversation memory is scoped per session. No cross-session data leakage.
- **Tool Sandboxing**: Gateway tools execute as independent Lambda functions with their own IAM roles and resource policies

## Enterprise Security Controls

| Control | Account | Description |
|---------|---------|-------------|
| SCPs | Management | Preventive guardrails across all member accounts |
| CloudTrail | Security | Organization-wide API audit trail |
| KMS CMK | Security | Customer-managed encryption for security data |
| Centralized Logging | Observability | Cross-account log aggregation and alerting |
| Budget Alarms | Management | Cost anomaly detection and spend limits |

## Customer Security Responsibilities

The following security controls are the customer's responsibility to implement and maintain:

- Regularly rotate Amazon Cognito client secrets and OAuth2 credentials (recommended: 90-day rotation)
- Review and update IAM policies as new tools or agents are added
- Consider enabling Amazon Bedrock Guardrails to help enforce content filtering and topic restrictions based on your security requirements
- Evaluate Amazon Cognito Advanced Security features to help detect compromised credentials based on your threat model
- Use VPC network mode for production deployments to minimize attack surface
- Review agent system prompts for prompt injection vulnerabilities
- Implement input validation and sanitization in custom Gateway tools
- Configure Amazon CloudWatch alarms for security events (failed authentication, unusual API call patterns)
- Regularly review AWS CloudTrail logs for unauthorized access attempts

## Supported AWS Regions

Amazon Bedrock AgentCore availability determines regional support. Check [Amazon Bedrock AgentCore availability](https://aws.amazon.com/bedrock/agentcore/) for the latest supported regions.

| Region Name | Region Code |
|-------------|-------------|
| US East (N. Virginia) | us-east-1 |
| US West (Oregon) | us-west-2 |
| Europe (Frankfurt) | eu-central-1 |
| Europe (Ireland) | eu-west-1 |
| Asia Pacific (Tokyo) | ap-northeast-1 |
| Asia Pacific (Sydney) | ap-southeast-2 |

> **Note**: Region availability is subject to change. Verify current availability before deployment.
