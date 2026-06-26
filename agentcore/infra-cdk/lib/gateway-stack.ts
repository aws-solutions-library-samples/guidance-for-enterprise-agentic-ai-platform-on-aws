// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

import * as cdk from "aws-cdk-lib"
import * as iam from "aws-cdk-lib/aws-iam"
import * as ssm from "aws-cdk-lib/aws-ssm"
import * as logs from "aws-cdk-lib/aws-logs"
import * as bedrockagentcore from "aws-cdk-lib/aws-bedrockagentcore"
import * as lambda from "aws-cdk-lib/aws-lambda"
import * as cr from "aws-cdk-lib/custom-resources"
import { Construct } from "constructs"
import { AppConfig } from "./utils/config-manager"
import * as path from "path"
import * as fs from "fs"

/**
 * Resolve a path that lives under the gateway tools tree in both repo
 * layouts:
 *   - Local monorepo:   <repo>/agentcore/gateway/tools/<rel>
 *       (__dirname = <repo>/agentcore/infra-cdk/lib → ../../gateway/tools/...)
 *   - CodeCommit repo:  <root>/shared/gateway/tools/<rel>
 *       (__dirname = <root>/infra-cdk/lib → ../../shared/gateway/tools/...)
 *
 * deploy.sh copies agentcore/gateway → shared/gateway when scaffolding the
 * CodeCommit repo, so we check both layouts and pick the first that exists.
 *
 * Validates by looking for a known marker file (sample_tool_lambda.py) so
 * empty / stale directories don't get picked by mistake.
 */
function resolveGatewayPath(rel: string): string {
  const MARKER = "sample_tool/sample_tool_lambda.py"
  const candidates = [
    path.join(__dirname, "..", "..", "gateway", "tools"),
    path.join(__dirname, "..", "..", "shared", "gateway", "tools"),
  ]
  for (const base of candidates) {
    if (fs.existsSync(path.join(base, MARKER))) {
      return path.join(base, rel)
    }
  }
  throw new Error(
    `Cannot locate gateway tools tree (missing ${MARKER}). Searched:\n  ` +
      candidates.join("\n  ")
  )
}

export interface GatewayStackProps extends cdk.StackProps {
  config: AppConfig

  /**
   * Cognito user pool id — imported. In single-account mode this comes from
   * the `agentic-ai-platform-single-platform` CFN stack; in enterprise mode from the
   * Security account's `security.yaml` StackSet output.
   */
  userPoolId: string

  /**
   * Full Cognito domain URL for the OAuth2 token endpoint, e.g.
   * `my-prefix-123456789012-eu-west-1.auth.eu-west-1.amazoncognito.com`.
   */
  userPoolDomain: string

  /** Cognito machine client id (client credentials grant). */
  machineClientId: string

  /**
   * Optional cross-account role ARN to assume for `DescribeUserPoolClient`.
   * Set in enterprise mode where the Cognito pool lives in the Security
   * account and this stack runs in a workload account. Omit in single-account
   * mode — the Lambda will use its own credentials.
   */
  machineClientDescribeRoleArn?: string
}

/**
 * AgentCore Gateway stack.
 *
 * Scope: this stack owns only AgentCore data-plane components that depend on
 * an already-existing Cognito pool + machine client. It does NOT own Cognito,
 * the machine client, or its secret — those are CFN-managed (single-account
 * platform stack or enterprise identity StackSet).
 *
 * Resources:
 *   - Sample tool Lambda(s) exposed through the Gateway
 *   - Gateway IAM role
 *   - AgentCore Gateway + GatewayTarget (L1 CfnGateway / CfnGatewayTarget)
 *   - AgentCore Identity OAuth2 Credential Provider (via custom resource)
 *   - SSM params the agent runtime reads at boot:
 *       /<stack>/gateway_url
 *       /<stack>/machine_client_id
 *       /<stack>/cognito_provider
 */
export class GatewayStack extends cdk.Stack {
  public readonly gatewayArn: string
  public readonly gatewayUrl: string

  constructor(scope: Construct, id: string, props: GatewayStackProps) {
    super(scope, id, props)

    const { config, userPoolId, userPoolDomain, machineClientId, machineClientDescribeRoleArn } =
      props
    const stackBase = config.stack_name_base

    const userPoolArn = `arn:aws:cognito-idp:${this.region}:${this.account}:userpool/${userPoolId}`

    // ---------------------------------------------------------------------
    // Sample tool Lambda
    // ---------------------------------------------------------------------
    const toolLambda = new lambda.Function(this, "SampleToolLambda", {
      runtime: lambda.Runtime.PYTHON_3_13,
      handler: "sample_tool_lambda.handler",
      code: lambda.Code.fromAsset(resolveGatewayPath("sample_tool")),
      timeout: cdk.Duration.seconds(30),
      tracing: lambda.Tracing.ACTIVE,
      logGroup: new logs.LogGroup(this, "SampleToolLambdaLogGroup", {
        logGroupName: `/aws/lambda/${stackBase}-sample-tool`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    })

    // ---------------------------------------------------------------------
    // Gateway IAM role
    // ---------------------------------------------------------------------
    const gatewayRole = new iam.Role(this, "GatewayRole", {
      assumedBy: new iam.ServicePrincipal("bedrock-agentcore.amazonaws.com"),
      description: "Role assumed by AgentCore Gateway to invoke tool Lambdas and read config",
    })

    toolLambda.grantInvoke(gatewayRole)

    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"],
        resources: [
          "arn:aws:bedrock:*::foundation-model/*",
          `arn:aws:bedrock:*:${this.account}:inference-profile/*`,
        ],
      })
    )
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["ssm:GetParameter", "ssm:GetParameters"],
        resources: [`arn:aws:ssm:${this.region}:${this.account}:parameter/${stackBase}/*`],
      })
    )
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["cognito-idp:DescribeUserPoolClient", "cognito-idp:InitiateAuth"],
        resources: [userPoolArn],
      })
    )
    gatewayRole.addToPolicy(
      new iam.PolicyStatement({
        effect: iam.Effect.ALLOW,
        actions: ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"],
        resources: [
          `arn:aws:logs:${this.region}:${this.account}:log-group:/aws/bedrock-agentcore/*`,
        ],
      })
    )

    // ---------------------------------------------------------------------
    // OAuth2 Credential Provider (AgentCore Identity) via custom resource.
    // Registers the machine client in the local Token Vault so the Runtime
    // can call @requires_access_token and get a fresh token cached in the vault.
    //
    // The Lambda fetches the Cognito client secret directly via
    // DescribeUserPoolClient — no Secrets Manager copy of it exists.
    // ---------------------------------------------------------------------
    const cognitoDiscoveryUrl = `https://cognito-idp.${this.region}.amazonaws.com/${userPoolId}/.well-known/openid-configuration`
    const providerName = `${stackBase}-runtime-gateway-auth`

    const oauth2ProviderLambda = new lambda.Function(this, "OAuth2ProviderLambda", {
      runtime: lambda.Runtime.PYTHON_3_13,
      handler: "index.handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "..", "lambdas", "oauth2-provider")),
      timeout: cdk.Duration.minutes(5),
      tracing: lambda.Tracing.ACTIVE,
      logGroup: new logs.LogGroup(this, "OAuth2ProviderLambdaLogGroup", {
        logGroupName: `/aws/lambda/${stackBase}-oauth2-provider`,
        retention: logs.RetentionDays.ONE_WEEK,
        removalPolicy: cdk.RemovalPolicy.DESTROY,
      }),
    })

    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: ["cognito-idp:DescribeUserPoolClient"],
        resources: [userPoolArn],
      })
    )
    if (machineClientDescribeRoleArn) {
      oauth2ProviderLambda.addToRolePolicy(
        new iam.PolicyStatement({
          actions: ["sts:AssumeRole"],
          resources: [machineClientDescribeRoleArn],
        })
      )
    }

    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateOauth2CredentialProvider",
          "bedrock-agentcore:UpdateOauth2CredentialProvider",
          "bedrock-agentcore:DeleteOauth2CredentialProvider",
          "bedrock-agentcore:GetOauth2CredentialProvider",
        ],
        resources: [
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/default`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/default/oauth2credentialprovider/*`,
        ],
      })
    )
    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "bedrock-agentcore:CreateTokenVault",
          "bedrock-agentcore:GetTokenVault",
          "bedrock-agentcore:DeleteTokenVault",
        ],
        resources: [
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/default`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/default/*`,
        ],
      })
    )
    oauth2ProviderLambda.addToRolePolicy(
      new iam.PolicyStatement({
        actions: [
          "secretsmanager:CreateSecret",
          "secretsmanager:DeleteSecret",
          "secretsmanager:DescribeSecret",
          "secretsmanager:PutSecretValue",
        ],
        resources: [
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:bedrock-agentcore-identity!default/oauth2/*`,
        ],
      })
    )

    const oauth2Provider = new cr.Provider(this, "OAuth2ProviderProvider", {
      onEventHandler: oauth2ProviderLambda,
    })

    new cdk.CustomResource(this, "RuntimeCredentialProvider", {
      serviceToken: oauth2Provider.serviceToken,
      properties: {
        ProviderName: providerName,
        UserPoolId: userPoolId,
        ClientId: machineClientId,
        DiscoveryUrl: cognitoDiscoveryUrl,
        ...(machineClientDescribeRoleArn
          ? { AssumeRoleArn: machineClientDescribeRoleArn }
          : {}),
      },
    })

    // ---------------------------------------------------------------------
    // Gateway + Gateway Target
    // ---------------------------------------------------------------------
    const toolSpecPath = resolveGatewayPath("sample_tool/tool_spec.json")
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const apiSpec = JSON.parse(require("fs").readFileSync(toolSpecPath, "utf8"))

    const gateway = new bedrockagentcore.CfnGateway(this, "AgentCoreGateway", {
      name: `${stackBase}-gateway`,
      roleArn: gatewayRole.roleArn,
      protocolType: "MCP",
      protocolConfiguration: {
        mcp: {
          supportedVersions: ["2025-03-26"],
        },
      },
      authorizerType: "CUSTOM_JWT",
      authorizerConfiguration: {
        customJwtAuthorizer: {
          allowedClients: [machineClientId],
          discoveryUrl: cognitoDiscoveryUrl,
        },
      },
      description: "AgentCore Gateway with MCP protocol and JWT authentication",
    })

    const gatewayTarget = new bedrockagentcore.CfnGatewayTarget(this, "GatewayTarget", {
      gatewayIdentifier: gateway.attrGatewayIdentifier,
      name: "sample-tool-target",
      description: "Sample tool Lambda target",
      targetConfiguration: {
        mcp: {
          lambda: {
            lambdaArn: toolLambda.functionArn,
            toolSchema: { inlinePayload: apiSpec },
          },
        },
      },
      credentialProviderConfigurations: [{ credentialProviderType: "GATEWAY_IAM_ROLE" }],
    })
    gatewayTarget.addDependency(gateway)
    gateway.node.addDependency(toolLambda)
    gateway.node.addDependency(gatewayRole)

    this.gatewayArn = gateway.attrGatewayArn
    this.gatewayUrl = gateway.attrGatewayUrl

    // ---------------------------------------------------------------------
    // SSM params consumed by the agent runtime at boot
    // ---------------------------------------------------------------------
    new ssm.StringParameter(this, "GatewayUrlParam", {
      parameterName: `/${stackBase}/gateway_url`,
      stringValue: gateway.attrGatewayUrl,
      description: "AgentCore Gateway URL",
    })
    new ssm.StringParameter(this, "MachineClientIdParam", {
      parameterName: `/${stackBase}/machine_client_id`,
      stringValue: machineClientId,
      description: "Cognito machine client id (M2M)",
    })
    new ssm.StringParameter(this, "CognitoProviderParam", {
      parameterName: `/${stackBase}/cognito_provider`,
      stringValue: userPoolDomain,
      description: "Cognito domain URL for OAuth2 token endpoint",
    })

    // ---------------------------------------------------------------------
    // Outputs
    // ---------------------------------------------------------------------
    new cdk.CfnOutput(this, "GatewayId", {
      value: gateway.attrGatewayIdentifier,
      description: "AgentCore Gateway ID",
    })
    new cdk.CfnOutput(this, "GatewayUrl", {
      value: gateway.attrGatewayUrl,
      description: "AgentCore Gateway URL",
    })
    new cdk.CfnOutput(this, "GatewayArn", {
      value: gateway.attrGatewayArn,
      description: "AgentCore Gateway ARN",
    })
    new cdk.CfnOutput(this, "ToolLambdaArn", {
      value: toolLambda.functionArn,
      description: "Sample tool Lambda ARN",
    })
  }
}
