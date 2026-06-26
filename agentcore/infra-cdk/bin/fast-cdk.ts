#!/usr/bin/env node
import * as cdk from "aws-cdk-lib"
import { GatewayStack } from "../lib/gateway-stack"
import { AgentStack } from "../lib/agent-stack"
import { ConfigManager } from "../lib/utils/config-manager"

/**
 * AgentCore CDK entry point.
 *
 * Deploys only AgentCore data-plane components:
 *   - GatewayStack:  AgentCore Gateway + tool Lambdas + OAuth2 credential provider
 *   - AgentStack:    per-agent Runtime + Memory + execution role
 *
 * Cognito (user pool, hosted UI, resource server, machine clients) is
 * deployed as CloudFormation in infra/cloudformation/ and consumed here
 * via CDK context.
 *
 * NOTE on bootstrap: `cdk bootstrap` is always invoked with `--app ''`
 * (see scripts/deploy.sh) so it skips evaluating this file entirely. This
 * entry point is therefore only ever called in deploy mode, which means
 * we can fail fast when required context is missing.
 *
 * Required context (deploy):
 *   cognito_user_pool_id          Cognito user pool id
 *   cognito_user_pool_client_id   Cognito user-facing client id
 *   cognito_user_pool_domain      Full <prefix>.auth.<region>.amazoncognito.com URL
 *   machine_client_id             Cognito machine client id (client_credentials)
 *
 * The machine client secret is NOT passed in. The oauth2 provider custom
 * resource reads it directly from Cognito via DescribeUserPoolClient.
 *
 * Optional context:
 *   stack_name                          Override config.yaml stack_name_base
 *   project_name                        Project tag used for the runtime PROJECT_NAME env var
 *   target_agent                        Deploy only this agent (skip others)
 *   agents_dir                          Override the auto-discovered agents directory
 *   skip_gateway                        "true" to skip deploying GatewayStack
 *   machine_client_describe_role_arn    Enterprise only: ARN of a role in the
 *                                       Security account that this (workload)
 *                                       account assumes for DescribeUserPoolClient.
 */
const app = new cdk.App()

const configFile = app.node.tryGetContext("config_file") || "config.yaml"
const configManager = new ConfigManager(configFile)
const baseConfig = configManager.getProps()

const stackName = app.node.tryGetContext("stack_name") || baseConfig.stack_name_base
const config = { ...baseConfig, stack_name_base: stackName }

const env = {
  account: process.env.CDK_DEFAULT_ACCOUNT,
  region: process.env.CDK_DEFAULT_REGION,
}

function required(key: string): string {
  const v = app.node.tryGetContext(key)
  if (!v) {
    throw new Error(
      `Missing required CDK context '${key}'. Pass it via --context ${key}=<value>.\n` +
        "All Cognito identity resources (user pool, machine client) are owned by\n" +
        "CloudFormation; the CDK app imports them by id at deploy time."
    )
  }
  return v
}

// ---------------------------------------------------------------------
// GatewayStack (one per account/region)
// ---------------------------------------------------------------------
const skipGateway = app.node.tryGetContext("skip_gateway") === "true"
if (!skipGateway) {
  new GatewayStack(app, `${stackName}-gateway`, {
    config,
    userPoolId: required("cognito_user_pool_id"),
    userPoolDomain: required("cognito_user_pool_domain"),
    machineClientId: required("machine_client_id"),
    machineClientDescribeRoleArn: app.node.tryGetContext("machine_client_describe_role_arn") as
      | string
      | undefined,
    env,
    description: "AgentCore Gateway + tool Lambdas + OAuth2 credential provider.",
  })
}

// ---------------------------------------------------------------------
// AgentStack (one per agent)
// ---------------------------------------------------------------------
const agents = configManager.discoverAgents(app.node.tryGetContext("agents_dir"))
const targetAgent = app.node.tryGetContext("target_agent") as string | undefined

for (const [agentName, agentConfig] of Object.entries(agents)) {
  if (targetAgent && agentName !== targetAgent) continue
  new AgentStack(app, `${stackName}-agent-${agentName}`, {
    config,
    agentName,
    agentConfig,
    userPoolId: required("cognito_user_pool_id"),
    userPoolClientId: required("cognito_user_pool_client_id"),
    env,
    description: `AgentCore Runtime + Memory for agent "${agentName}".`,
  })
}

app.synth()
