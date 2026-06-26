// Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
// SPDX-License-Identifier: MIT-0

import * as cdk from "aws-cdk-lib"
import * as iam from "aws-cdk-lib/aws-iam"
import * as ssm from "aws-cdk-lib/aws-ssm"
import * as s3 from "aws-cdk-lib/aws-s3"
import * as lambda from "aws-cdk-lib/aws-lambda"
import * as cr from "aws-cdk-lib/custom-resources"
import * as ecrAssets from "aws-cdk-lib/aws-ecr-assets"
import * as agentcore from "@aws-cdk/aws-bedrock-agentcore-alpha"
import { Construct } from "constructs"
import { AppConfig, AgentConfig } from "./utils/config-manager"
import { AgentCoreRole } from "./utils/agentcore-role"
import * as path from "path"
import * as fs from "fs"
import * as os from "os"

export interface AgentStackProps extends cdk.StackProps {
  config: AppConfig
  agentName: string
  agentConfig: AgentConfig
  userPoolId: string
  userPoolClientId: string
}

/**
 * Per-agent stack: AgentCore Runtime + Memory + execution role.
 *
 * One top-level stack per agent. Deploy all agents with `cdk deploy --all`
 * (or select one via `--context target_agent=<name>`).
 *
 * Depends on GatewayStack having already published
 *   /<stack>/gateway_url, /<stack>/machine_client_id, /<stack>/cognito_provider
 * to SSM so the runtime container can read them at boot.
 */
export class AgentStack extends cdk.Stack {
  public readonly runtimeArn: string
  public readonly memoryArn: string | undefined

  constructor(scope: Construct, id: string, props: AgentStackProps) {
    super(scope, id, props)

    const { config, agentName, agentConfig, userPoolId, userPoolClientId } = props
    const stack = cdk.Stack.of(this)
    const sanitizedName = agentName.replace(/[^a-zA-Z0-9_]/g, "_")

    // -----------------------------------------------------------------
    // Agent Execution Role
    // -----------------------------------------------------------------
    const agentRole = new AgentCoreRole(this, "AgentCoreRole")

    // -----------------------------------------------------------------
    // Memory
    // -----------------------------------------------------------------
    let memoryId = ""
    if (agentConfig.memory) {
      const memory = new cdk.CfnResource(this, "AgentMemory", {
        type: "AWS::BedrockAgentCore::Memory",
        properties: {
          Name: cdk.Names.uniqueResourceName(this, { maxLength: 48 }),
          EventExpiryDuration: 30,
          Description: `Memory for ${agentName} agent`,
          MemoryStrategies: [
            {
              SummaryMemoryStrategy: {
                Name: "SessionSummarizer",
                Namespaces: ["/summaries/{actorId}/{sessionId}"],
              },
            },
          ],
          MemoryExecutionRoleArn: agentRole.roleArn,
          Tags: { Name: `${config.stack_name_base}_${sanitizedName}_Memory`, ManagedBy: "CDK" },
        },
      })
      memoryId = memory.getAtt("MemoryId").toString()
      this.memoryArn = memory.getAtt("MemoryArn").toString()

      agentRole.addToPolicy(
        new iam.PolicyStatement({
          sid: "MemoryResourceAccess",
          effect: iam.Effect.ALLOW,
          actions: [
            "bedrock-agentcore:CreateEvent",
            "bedrock-agentcore:GetEvent",
            "bedrock-agentcore:ListEvents",
            "bedrock-agentcore:RetrieveMemoryRecords",
          ],
          resources: [this.memoryArn],
        })
      )
    }

    // -----------------------------------------------------------------
    // SSM + Secrets + OAuth2 permissions
    // -----------------------------------------------------------------
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "SSMParameterAccess",
        effect: iam.Effect.ALLOW,
        actions: ["ssm:GetParameter", "ssm:GetParameters"],
        resources: [
          `arn:aws:ssm:${this.region}:${this.account}:parameter/${config.stack_name_base}/*`,
        ],
      })
    )
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "CodeInterpreterAccess",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:StartCodeInterpreterSession",
          "bedrock-agentcore:StopCodeInterpreterSession",
          "bedrock-agentcore:InvokeCodeInterpreter",
        ],
        resources: [`arn:aws:bedrock-agentcore:${this.region}:aws:code-interpreter/*`],
      })
    )
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "OAuth2CredentialProviderAccess",
        effect: iam.Effect.ALLOW,
        actions: [
          "bedrock-agentcore:GetOauth2CredentialProvider",
          "bedrock-agentcore:GetResourceOauth2Token",
        ],
        resources: [
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:oauth2-credential-provider/*`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:token-vault/*`,
          `arn:aws:bedrock-agentcore:${this.region}:${this.account}:workload-identity-directory/*`,
        ],
      })
    )
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "SecretsManagerOAuth2Access",
        effect: iam.Effect.ALLOW,
        actions: ["secretsmanager:GetSecretValue"],
        resources: [
          // Secret 2: AgentCore Identity-managed secret read via IAM delegation
          // when the Token Vault fetches a new M2M token from Cognito.
          `arn:aws:secretsmanager:${this.region}:${this.account}:secret:bedrock-agentcore-identity!default/oauth2/${config.stack_name_base}-runtime-gateway-auth*`,
        ],
      })
    )
    // ECR pull for Docker-mode runtimes. fromImageUri() does not auto-grant
    // anything, so we scope to CDK's asset repo + any repo in this account.
    const projectName = this.node.tryGetContext("project_name") || config.stack_name_base
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "EcrImagePull",
        effect: iam.Effect.ALLOW,
        actions: [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ],
        resources: [`arn:aws:ecr:${this.region}:${this.account}:repository/${projectName}/*`],
      })
    )
    agentRole.addToPolicy(
      new iam.PolicyStatement({
        sid: "EcrAuthToken",
        effect: iam.Effect.ALLOW,
        // ecr:GetAuthorizationToken does not support resource-level permissions
        actions: ["ecr:GetAuthorizationToken"],
        resources: ["*"],
      })
    )

    // -----------------------------------------------------------------
    // Runtime artifact — ZIP or Docker based on deployment_type
    // -----------------------------------------------------------------
    const pattern = agentConfig.pattern || "strands-single-agent"
    const deploymentType = agentConfig.deployment_type || "zip"
    const repoRoot = path.resolve(__dirname, "..", "..")

    // Code dir resolution. Works for both layouts:
    //   Local monorepo:  agentcore/patterns/<pattern>  (pattern code)
    //                    agentcore/agents/<name>       (if overridden per agent)
    //   CodeCommit repo: agents/<name>                 (flat, one up)
    const codecommitPath = path.join(repoRoot, "..", "agents", agentName)
    const codecommitPath2 = path.join(repoRoot, "agents", agentName)
    const platformPath = path.join(repoRoot, "patterns", pattern)
    const codeDir = fs.existsSync(codecommitPath)
      ? codecommitPath
      : fs.existsSync(codecommitPath2)
      ? codecommitPath2
      : platformPath

    let agentRuntimeArtifact: agentcore.AgentRuntimeArtifact
    let zipPackager: cdk.CustomResource | undefined

    if (deploymentType === "docker") {
      agentRuntimeArtifact = this.buildDockerArtifact({
        agentName,
        pattern,
        codeDir,
        repoRoot,
      })
    } else {
      const zip = this.buildZipArtifact({ agentName, codeDir, repoRoot })
      agentRuntimeArtifact = zip.artifact
      zipPackager = zip.packager
    }

    // -----------------------------------------------------------------
    // AgentCore Runtime
    // -----------------------------------------------------------------
    const modelId = agentConfig.model_id || this.node.tryGetContext("model_id") || ""

    const envVars: Record<string, string> = {
      AWS_REGION: stack.region,
      AWS_DEFAULT_REGION: stack.region,
      STACK_NAME: config.stack_name_base,
      PROJECT_NAME: projectName,
      AGENT_NAME: agentName,
      GATEWAY_CREDENTIAL_PROVIDER_NAME: `${config.stack_name_base}-runtime-gateway-auth`,
      DEPLOY_VERSION: new Date().toISOString(),
      ...(memoryId ? { MEMORY_ID: memoryId } : {}),
      ...(modelId ? { MODEL_ID: modelId } : {}),
    }

    const authorizerConfiguration = agentcore.RuntimeAuthorizerConfiguration.usingJWT(
      `https://cognito-idp.${stack.region}.amazonaws.com/${userPoolId}/.well-known/openid-configuration`,
      [userPoolClientId]
    )

    const runtimeName = `${config.stack_name_base.replace(/-/g, "_")}_${sanitizedName}`
    const runtime = new agentcore.Runtime(this, "Runtime", {
      runtimeName,
      agentRuntimeArtifact,
      executionRole: agentRole,
      protocolConfiguration: agentcore.ProtocolType.HTTP,
      environmentVariables: envVars,
      authorizerConfiguration,
      requestHeaderConfiguration: { allowlistedHeaders: ["Authorization"] },
      description: `${agentName} agent runtime (${agentConfig.team})`,
    })
    if (zipPackager) {
      runtime.node.addDependency(zipPackager)
    }

    this.runtimeArn = runtime.agentRuntimeArn

    // -----------------------------------------------------------------
    // SSM registration — used by other services to discover this agent
    // -----------------------------------------------------------------
    new ssm.StringParameter(this, "RuntimeArnParam", {
      parameterName: `/${config.stack_name_base}/agents/${agentName}/runtime-arn`,
      stringValue: this.runtimeArn,
    })

    new ssm.StringParameter(this, "AgentConfigParam", {
      parameterName: `/${config.stack_name_base}/agents/${agentName}/config`,
      stringValue: JSON.stringify({
        agent_name: agentName,
        team: agentConfig.team,
        model_id: modelId,
        memory: agentConfig.memory,
        gateway: agentConfig.gateway,
        pattern: pattern,
        description: agentConfig.description || "",
        deployed_at: new Date().toISOString(),
      }),
      description: `Agent metadata for ${agentName} — used for discovery`,
    })

    if (this.memoryArn) {
      new ssm.StringParameter(this, "MemoryArnParam", {
        parameterName: `/${config.stack_name_base}/agents/${agentName}/memory-arn`,
        stringValue: this.memoryArn,
      })
    }

    // -----------------------------------------------------------------
    // Outputs
    // -----------------------------------------------------------------
    new cdk.CfnOutput(this, "RuntimeArn", {
      value: this.runtimeArn,
      description: `Runtime ARN for ${agentName}`,
    })
    if (this.memoryArn) {
      new cdk.CfnOutput(this, "MemoryArn", {
        value: this.memoryArn,
        description: `Memory ARN for ${agentName}`,
      })
    }
  }

  /** Recursively read directory contents as base64 for ZIP packaging */
  private readDirRecursive(
    dir: string,
    prefix: string,
    output: Record<string, string>
  ): void {
    for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
      const fullPath = path.join(dir, entry.name)
      const relativePath = `${prefix}/${entry.name}`
      if (entry.isDirectory()) {
        if (entry.name === "__pycache__" || entry.name === ".git") continue
        this.readDirRecursive(fullPath, relativePath, output)
      } else if (
        entry.name.endsWith(".py") ||
        entry.name.endsWith(".txt") ||
        entry.name.endsWith(".json")
      ) {
        output[relativePath] = fs.readFileSync(fullPath).toString("base64")
      }
    }
  }

  /** Create a hash of content for change detection */
  private hashContent(content: string): string {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const crypto = require("crypto")
    return crypto.createHash("sha256").update(content).digest("hex").substring(0, 16)
  }

  /**
   * ZIP path — previous behavior. Packages agent + shared code into an S3
   * object via a custom-resource Lambda, returns an AgentRuntimeArtifact.
   */
  private buildZipArtifact(args: {
    agentName: string
    codeDir: string
    repoRoot: string
  }): { artifact: agentcore.AgentRuntimeArtifact; packager: cdk.CustomResource } {
    const { codeDir, repoRoot } = args

    const agentCodeBucket = new s3.Bucket(this, "AgentCodeBucket", {
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      versioned: true,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      encryption: s3.BucketEncryption.S3_MANAGED,
      enforceSSL: true,
    })

    const packagerLambda = new lambda.Function(this, "ZipPackagerLambda", {
      runtime: lambda.Runtime.PYTHON_3_12,
      handler: "index.handler",
      code: lambda.Code.fromAsset(path.join(__dirname, "..", "lambdas", "zip-packager")),
      timeout: cdk.Duration.minutes(10),
      memorySize: 1024,
      ephemeralStorageSize: cdk.Size.gibibytes(2),
    })
    agentCodeBucket.grantReadWrite(packagerLambda)

    const agentCode: Record<string, string> = {}
    if (fs.existsSync(codeDir)) {
      for (const file of fs.readdirSync(codeDir)) {
        if (file.endsWith(".py")) {
          agentCode[file] = fs.readFileSync(path.join(codeDir, file)).toString("base64")
        }
      }
    }
    const sharedRoot = path.join(repoRoot, "..")
    for (const [dir, prefix] of [
      [path.join(sharedRoot, "shared", "gateway"), "gateway"],
      [path.join(sharedRoot, "shared", "utils"), "utils"],
      [path.join(sharedRoot, "shared", "tools"), "tools"],
      [path.join(repoRoot, "shared", "gateway"), "gateway"],
      [path.join(repoRoot, "shared", "utils"), "utils"],
      [path.join(repoRoot, "shared", "tools"), "tools"],
      [path.join(repoRoot, "gateway"), "gateway"],
      [path.join(repoRoot, "tools"), "tools"],
      [path.join(repoRoot, "patterns", "utils"), "utils"],
    ] as [string, string][]) {
      if (fs.existsSync(dir) && !agentCode[`${prefix}/__init__.py`]) {
        this.readDirRecursive(dir, prefix, agentCode)
      }
    }

    const requirementsPath = path.join(codeDir, "requirements.txt")
    const requirements = fs.existsSync(requirementsPath)
      ? fs
          .readFileSync(requirementsPath, "utf-8")
          .split("\n")
          .map((l) => l.trim())
          .filter((l) => l && !l.startsWith("#"))
      : []

    const contentHash = this.hashContent(JSON.stringify({ requirements, agentCode }))

    const provider = new cr.Provider(this, "ZipPackagerProvider", {
      onEventHandler: packagerLambda,
    })
    const packager = new cdk.CustomResource(this, "ZipPackager", {
      serviceToken: provider.serviceToken,
      properties: {
        BucketName: agentCodeBucket.bucketName,
        ObjectKey: "deployment_package.zip",
        Requirements: requirements,
        AgentCode: agentCode,
        ContentHash: contentHash,
      },
    })

    const artifact = agentcore.AgentRuntimeArtifact.fromS3(
      { bucketName: agentCodeBucket.bucketName, objectKey: "deployment_package.zip" },
      agentcore.AgentCoreRuntime.PYTHON_3_12,
      ["opentelemetry-instrument", "basic_agent.py"]
    )

    return { artifact, packager }
  }

  /**
   * Docker path — stages agent + shared code + a generated Dockerfile into a
   * temp dir, hands it to CDK's DockerImageAsset, and references the pushed
   * ECR image from the runtime. Requires Docker running on the machine that
   * runs `cdk deploy`.
   */
  private buildDockerArtifact(args: {
    agentName: string
    pattern: string
    codeDir: string
    repoRoot: string
  }): agentcore.AgentRuntimeArtifact {
    const { agentName, codeDir, repoRoot } = args

    // Stage a clean build context CDK can ship to the docker daemon.
    const stageDir = fs.mkdtempSync(path.join(os.tmpdir(), `agentstage-${agentName}-`))

    // 1. Agent code files (flat at the context root).
    this.copyFilesFlat(codeDir, stageDir)

    // 2. Shared libs (same candidates the ZIP path scans).
    const sharedRoot = path.join(repoRoot, "..")
    const shareCandidates: [string, string][] = [
      [path.join(sharedRoot, "shared", "gateway"), "gateway"],
      [path.join(sharedRoot, "shared", "utils"), "utils"],
      [path.join(sharedRoot, "shared", "tools"), "tools"],
      [path.join(repoRoot, "shared", "gateway"), "gateway"],
      [path.join(repoRoot, "shared", "utils"), "utils"],
      [path.join(repoRoot, "shared", "tools"), "tools"],
      [path.join(repoRoot, "gateway"), "gateway"],
      [path.join(repoRoot, "tools"), "tools"],
      [path.join(repoRoot, "patterns", "utils"), "utils"],
    ]
    for (const [src, dst] of shareCandidates) {
      const target = path.join(stageDir, dst)
      if (fs.existsSync(src) && !fs.existsSync(target)) {
        this.copyDirRecursive(src, target)
      }
    }

    // 3. requirements.txt (agent-local).
    const reqSrc = path.join(codeDir, "requirements.txt")
    if (fs.existsSync(reqSrc)) {
      fs.copyFileSync(reqSrc, path.join(stageDir, "requirements.txt"))
    } else {
      fs.writeFileSync(path.join(stageDir, "requirements.txt"), "")
    }

    // 4. Generated Dockerfile tailored to this flat staging layout.
    fs.writeFileSync(
      path.join(stageDir, "Dockerfile"),
      [
        "FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim",
        "WORKDIR /app",
        "ENV UV_SYSTEM_PYTHON=1 \\",
        "    UV_COMPILE_BYTECODE=1 \\",
        "    DOCKER_CONTAINER=1 \\",
        "    OTEL_PYTHON_LOG_CORRELATION=true \\",
        "    PYTHONUNBUFFERED=1",
        "COPY requirements.txt .",
        "RUN uv pip install --no-cache -r requirements.txt && \\",
        "    uv pip install --no-cache aws-opentelemetry-distro==0.12.2 requests>=2.31.0",
        "COPY gateway/ gateway/",
        "COPY utils/ utils/",
        "COPY *.py ./",
        "RUN useradd -m -u 1000 bedrock_agentcore",
        "USER bedrock_agentcore",
        "EXPOSE 8080",
        'HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \\',
        "  CMD python -c \"import urllib.request; urllib.request.urlopen('http://localhost:8080/ping', timeout=2)\" || exit 1",
        'CMD ["opentelemetry-instrument", "python", "-m", "basic_agent"]',
        "",
      ].join("\n")
    )

    const image = new ecrAssets.DockerImageAsset(this, "AgentImage", {
      directory: stageDir,
      platform: ecrAssets.Platform.LINUX_ARM64,
    })

    return agentcore.AgentRuntimeArtifact.fromImageUri(image.imageUri)
  }

  /** Copy a directory tree, pruning noise. */
  private copyDirRecursive(src: string, dst: string): void {
    fs.mkdirSync(dst, { recursive: true })
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
      if (entry.name === "__pycache__" || entry.name === ".git") continue
      const s = path.join(src, entry.name)
      const d = path.join(dst, entry.name)
      if (entry.isDirectory()) {
        this.copyDirRecursive(s, d)
      } else {
        fs.copyFileSync(s, d)
      }
    }
  }

  /** Copy .py / .txt / .json files from src into dst (non-recursive). */
  private copyFilesFlat(src: string, dst: string): void {
    if (!fs.existsSync(src)) return
    fs.mkdirSync(dst, { recursive: true })
    for (const entry of fs.readdirSync(src, { withFileTypes: true })) {
      if (!entry.isFile()) continue
      if (
        entry.name.endsWith(".py") ||
        entry.name.endsWith(".txt") ||
        entry.name.endsWith(".json")
      ) {
        fs.copyFileSync(path.join(src, entry.name), path.join(dst, entry.name))
      }
    }
  }
}
