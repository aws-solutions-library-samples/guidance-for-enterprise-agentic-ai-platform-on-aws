# AI Security and Compliance

This document describes the GenAI security controls, governance practices, and compliance considerations for the Agentic AI Platform.

## GenAI Use Case Classification

This platform provides a general-purpose agent framework for building conversational AI assistants. It is designed for enterprise internal use cases such as:

- Information retrieval and summarization
- Code analysis and generation assistance
- Document processing and data extraction
- Task automation via tool integrations

This platform is NOT intended for:

- Autonomous decision-making in safety-critical domains (healthcare, legal, financial)
- Direct consumer-facing applications without additional guardrails
- Use cases involving minors or vulnerable populations
- Generating content that could cause physical harm

Deployers are responsible for classifying their specific use cases against their organization's AI governance policies before production deployment.

## Third-Party Dependencies and Legal Compliance

### Amazon Bedrock Foundation Models

This platform uses Amazon Bedrock to access foundation models (default: Anthropic Claude Sonnet). Amazon Bedrock models are accessed through the AWS service API under the [AWS Customer Agreement](https://aws.amazon.com/agreement/) and the [AWS Service Terms](https://aws.amazon.com/service-terms/). No separate license agreement with model providers is required when accessing models through Amazon Bedrock.

Deployers should verify that their selected model is available in their AWS Region and complies with their organization's approved model list.

### Strands Agents Framework

[Strands Agents](https://github.com/strands-agents/sdk-python) is an open-source agent framework published under the Apache-2.0 license. It is maintained by AWS and available on PyPI. No additional legal approval is required for Apache-2.0 licensed dependencies.

### Model Context Protocol (MCP)

The [MCP SDK](https://github.com/modelcontextprotocol/python-sdk) is an open-source protocol library published under the MIT license. It is used for tool integration via the AgentCore Gateway. No additional legal approval is required for MIT licensed dependencies.

### Amazon Bedrock AgentCore SDK

The `bedrock-agentcore` SDK is an AWS-published package for integrating with Amazon Bedrock AgentCore services. It is distributed under the Apache-2.0 license.

## AI Security Controls

### Input Validation and Prompt Injection Mitigation

The platform implements multiple layers of input security:

1. **System prompt hardening**: The agent's system prompt includes explicit instructions to reject prompt injection attempts, refuse to reveal system instructions, and validate user requests before tool invocation.

2. **Authentication-bound identity**: User identity is extracted from pre-validated JWT tokens (validated by AgentCore Runtime) rather than from user-supplied input, preventing identity spoofing via prompt injection. See `patterns/utils/auth.py`.

3. **Tool authorization**: All tool calls route through the AgentCore Gateway, which enforces OAuth2 M2M authentication. Tools cannot be invoked without a valid gateway token.

4. **Code Interpreter sandboxing**: The Code Interpreter tool executes user-requested code in a restricted environment with no network access and limited filesystem scope. See `tools/code_interpreter/code_interpreter_tools.py`.

### Output Filtering

- Agent responses are streamed through the AgentCore Runtime, which provides built-in content filtering capabilities.
- Deployers are encouraged to enable [Amazon Bedrock Guardrails](https://docs.aws.amazon.com/bedrock/latest/userguide/guardrails.html) for content filtering, PII redaction, and topic denial. Guardrails can be attached to the model invocation without code changes by configuring a Guardrail ID in the Bedrock model configuration.

### Model Access Controls

- Model access is controlled via IAM policies scoped to specific Bedrock model ARNs.
- The agent execution role (`AgentExecutionRole`) has `bedrock:InvokeModel` permissions limited to the configured model ID.
- Cross-model invocation is prevented by IAM policy — agents cannot switch to unauthorized models at runtime.

### Monitoring and Observability

- All agent invocations are traced via AWS X-Ray with Transaction Search enabled for full span indexing.
- CloudWatch metrics track invocation count, latency (p50/p99), and evaluation scores.
- CloudWatch alarms alert on latency anomalies.
- Agent evaluation scores are published to CloudWatch after each pipeline deployment.

## Bias and Fairness Considerations

This platform delegates language generation to Amazon Bedrock foundation models. Bias characteristics are determined by the selected model:

- **Model selection**: Deployers should review the model card for their chosen foundation model (available in the Amazon Bedrock console) for documented bias evaluations and limitations.
- **Evaluation**: The platform includes an evaluation framework (`scripts/pipeline_eval.py`) that runs automated assessments on each deployment. Deployers should extend the eval cases in `agents/<agent>/eval/` to include fairness-specific test scenarios relevant to their use case.
- **Human review**: For high-stakes use cases, deployers should implement human-in-the-loop review processes. The platform's memory and session tracking features support audit trails for this purpose.

## Dataset Compliance

### Conversation Memory

The platform stores conversation history in Amazon Bedrock AgentCore Memory (short-term and long-term). This data:

- Is encrypted at rest using AWS KMS
- Is scoped per-user via JWT-bound session IDs
- Is subject to the deployer's data retention policies (configurable via AgentCore Memory settings)
- Does NOT leave the deployer's AWS account

### Evaluation Datasets

Evaluation test cases (stored in `agents/<agent>/eval/`) are deployer-authored YAML/JSON files containing test prompts and expected assertions. These are not training data — they are used solely for automated quality gates in the CI/CD pipeline.

Deployers are responsible for ensuring evaluation datasets do not contain PII or sensitive data.

## Threat Model Status

The platform includes a threat modeling framework under `threat-modeling/` covering:

- Agent runtime threats (prompt injection, tool abuse, model manipulation)
- Identity and authentication threats (token theft, session hijacking)
- Memory threats (cross-session leakage, memory poisoning)
- Code Interpreter threats (sandbox escape, data exfiltration)
- Gateway and tool integration threats

The risk matrix (`threat-modeling/risk-assessment/risk-matrix.md`) catalogs identified threats. Deployers should complete the risk assessment (likelihood, impact, status) for their specific deployment context, as risk levels vary by use case, data sensitivity, and user population.

## Recommendations for Production Deployment

1. **Enable Amazon Bedrock Guardrails** for content filtering and PII redaction
2. **Complete the risk matrix** with deployment-specific risk assessments
3. **Extend evaluation cases** with domain-specific and fairness test scenarios
4. **Configure data retention** policies for conversation memory
5. **Review model cards** for the selected foundation model
6. **Implement human review** workflows for high-stakes use cases
7. **Enable VPC deployment** mode for network isolation (see `docs/agentcore-deployment.md`)
