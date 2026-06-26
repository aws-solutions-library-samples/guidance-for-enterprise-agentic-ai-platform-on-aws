<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Cost

> These cost estimates are provided for informational purposes only. Actual costs vary based on usage patterns and configuration. You are responsible for monitoring and managing your AWS costs.

## Cost Considerations

When implementing this guidance on AWS, it's important to understand the various factors that contribute to the overall cost. This section outlines the primary cost components and key factors that influence pricing.

## Cost Components

The total cost of running this solution can be broadly categorized into two main components:

1. **LLM Provider Costs**: Charges incurred for using Amazon Bedrock foundation models. Pricing is based on input/output tokens processed, model selection, and usage volume. See [Amazon Bedrock pricing](https://aws.amazon.com/bedrock/pricing/).

2. **AWS Infrastructure Costs**: Costs associated with running the AgentCore platform on AWS infrastructure, including compute, networking, storage, and supporting services.

## Key Factors Influencing AWS Infrastructure Costs

The actual cost of running the platform can vary significantly based on your implementation and usage patterns:

1. **AgentCore Runtime**: Container execution costs depend on vCPU/memory allocation, number of concurrent agents, and invocation duration.

2. **AgentCore Gateway**: Lambda-based tool execution costs scale with the number of tool invocations and execution duration.

3. **AgentCore Memory**: DynamoDB costs for session storage and OpenSearch costs for semantic memory scale with conversation volume and retention policies.

4. **Traffic Patterns**: The shape and distribution of agent requests, including:
   - Requests per minute (RPM)
   - Tokens per minute (TPM)
   - Concurrent sessions
   - Average conversation length
   - Tool invocation frequency

5. **Multi-Account Overhead**: Enterprise deployments incur additional costs for cross-account roles, StackSets, and centralized observability infrastructure.

6. **Networking**: Data transfer charges between accounts and NAT gateway costs for outbound calls to Bedrock APIs.

7. **Observability**: CloudWatch Logs retention, X-Ray traces, and dashboard metrics contribute to monitoring costs.

## Customer Responsibility

Customers are responsible for:

1. Configuring the solution to optimal settings based on their specific use case
2. Monitoring and managing costs incurred from running the platform
3. Managing and optimizing Bedrock model usage and token consumption

We recommend creating a [budget](https://docs.aws.amazon.com/cost-management/latest/userguide/budgets-create.html) through [AWS Cost Explorer](https://aws.amazon.com/aws-cost-management/aws-cost-explorer/) to help manage costs. Prices are subject to change. For full details, refer to the pricing webpage for each AWS service used in this guidance.

## Sample Cost Table — Single Account Deployment

The following table provides a sample cost breakdown for deploying this guidance with default parameters in `us-east-1` (N. Virginia) for one month.

| AWS Service | Dimensions | Cost/month (USD) |
|-------------|-----------|-----------------|
| Amazon Bedrock AgentCore Runtime | 2 vCPU, 4 GB memory, ~10K invocations/month, avg 30s duration | ~$50.00 |
| Amazon Bedrock AgentCore Gateway | Lambda-based tools, ~50K invocations/month, avg 500ms | ~$5.00 |
| Amazon Bedrock AgentCore Memory | DynamoDB on-demand, ~100K read/write units/month | ~$10.00 |
| Amazon Bedrock (Model) | Claude Sonnet, ~5M input + 1M output tokens/month | ~$45.00 |
| Amazon Cognito | 1 user pool, <50K MAU (free tier) | $0.00 |
| Amazon CloudWatch | Logs (10 GB), 20 metrics, X-Ray traces | ~$15.00 |
| AWS Lambda | OAuth2 provider + tool functions, ~100K invocations | ~$2.00 |
| Amazon ECR | 2 GB image storage | ~$0.20 |
| **TOTAL** | | **~$127.20/month** |

> **Note**: These are estimates based on moderate usage. Actual costs will vary based on model selection, invocation volume, and conversation complexity. AgentCore pricing may vary — check [Amazon Bedrock AgentCore pricing](https://aws.amazon.com/bedrock/agentcore/pricing/) for current rates.

## Sample Cost Table — Enterprise (7 Account) Deployment

| AWS Service | Dimensions | Cost/month (USD) |
|-------------|-----------|-----------------|
| Workload costs | AgentCore runtime in dev + staging + prod accounts | ~$381.60 |
| AWS Organizations | Free | $0.00 |
| AWS CloudTrail | 1 trail, organization-wide | ~$2.00 |
| AWS KMS | 1 CMK, ~10K requests/month | ~$4.00 |
| Amazon CloudWatch (Observability account) | Cross-account dashboards, alarms, 30-day log retention | ~$25.00 |
| IAM Cross-Account Roles | Free | $0.00 |
| AWS CloudFormation StackSets | Free (pay for resources deployed) | $0.00 |
| Amazon S3 (Security account) | Audit logs, ~5 GB/month | ~$0.15 |
| CI/CD Pipeline (Shared Tooling) | CodePipeline, CodeBuild, CodeCommit, ECR | ~$10.00 |
| **TOTAL** | | **~$422.75/month** |

> **Note**: Enterprise adds multi-env overhead (dev + staging + prod each run their own AgentCore stack) plus shared-tooling CI/CD and centralized security/observability. Single-account workload cost is replicated per environment; platform/tooling overhead is fixed.

## AWS Services in this Guidance

| AWS Service | Role | Description |
|-------------|------|-------------|
| [Amazon Bedrock](https://aws.amazon.com/bedrock/) | Core | Foundation model access for agent reasoning |
| [Amazon Bedrock AgentCore](https://aws.amazon.com/bedrock/agentcore/) | Core | Runtime, Gateway, Memory, Identity, Code Interpreter |
| [Amazon Cognito](https://aws.amazon.com/cognito/) | Core | User authentication, JWT tokens, M2M OAuth2 |
| [AWS Lambda](https://aws.amazon.com/lambda/) | Core | Gateway tool targets, OAuth2 credential provider |
| [Amazon DynamoDB](https://aws.amazon.com/dynamodb/) | Supporting | Session memory, agent registry |
| [Amazon ECR](https://aws.amazon.com/ecr/) | Supporting | Container image storage for agent runtime |
| [Amazon CloudWatch](https://aws.amazon.com/cloudwatch/) | Monitoring | Logs, metrics, dashboards, alarms |
| [AWS X-Ray](https://aws.amazon.com/xray/) | Monitoring | Distributed tracing for agent invocations |
| [AWS CloudTrail](https://aws.amazon.com/cloudtrail/) | Security | API audit logging (enterprise) |
| [AWS KMS](https://aws.amazon.com/kms/) | Security | Encryption key management (enterprise) |
| [AWS Organizations](https://aws.amazon.com/organizations/) | Management | Multi-account governance (enterprise) |
| [AWS CloudFormation](https://aws.amazon.com/cloudformation/) | Deployment | Infrastructure as code, StackSets |
| [AWS CDK](https://aws.amazon.com/cdk/) | Deployment | AgentCore infrastructure definition |
| [Amazon S3](https://aws.amazon.com/s3/) | Supporting | Audit logs, artifacts storage |
