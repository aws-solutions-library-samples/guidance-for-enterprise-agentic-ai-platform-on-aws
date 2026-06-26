import * as fs from "fs"
import * as path from "path"
import * as yaml from "yaml"

const MAX_STACK_NAME_BASE_LENGTH = 35

export type DeploymentType = "docker" | "zip"

/**
 * Network mode for the AgentCore Runtime.
 * - PUBLIC: Runtime is accessible over the public internet (default).
 * - VPC: Runtime is deployed into a user-provided VPC for private network isolation.
 */
export type NetworkMode = "PUBLIC" | "VPC"

/**
 * VPC configuration for deploying the AgentCore Runtime into an existing VPC.
 * Required when network_mode is "VPC".
 */
export interface VpcConfig {
  /** The ID of the existing VPC to deploy into (e.g. "vpc-0abc1234def56789a"). */
  vpc_id: string
  /** List of subnet IDs within the VPC where the runtime will be placed. */
  subnet_ids: string[]
  /** Optional list of security group IDs. If omitted, a default security group is created. */
  security_group_ids?: string[]
}

/** Configuration for a single agent from agent.yaml inside each agent directory */
export interface AgentConfig {
  team: string
  pattern: string
  model_id: string
  deployment_type: DeploymentType
  memory: boolean
  gateway: boolean
  description?: string
}

export interface AppConfig {
  stack_name_base: string
  admin_user_email?: string | null
  backend: {
    pattern: string
    deployment_type: DeploymentType
    /** Network mode for the AgentCore Runtime. Defaults to "PUBLIC". */
    network_mode: NetworkMode
    /** VPC configuration. Required when network_mode is "VPC". */
    vpc?: VpcConfig
  }
  /** Agents discovered from agents/ directory. Key is agent name. */
  agents?: Record<string, AgentConfig>
}

export class ConfigManager {
  private config: AppConfig

  constructor(configFile: string) {
    this.config = this._loadConfig(configFile)
  }

  private _loadConfig(configFile: string): AppConfig {
    const configPath = path.join(__dirname, "..", "..", configFile)

    if (!fs.existsSync(configPath)) {
      throw new Error(`Configuration file ${configPath} does not exist. Please create config.yaml file.`)
    }

    try {
      const fileContent = fs.readFileSync(configPath, "utf8")
      const parsedConfig = yaml.parse(fileContent) as AppConfig

      const deploymentType = parsedConfig.backend?.deployment_type || "zip"
      if (deploymentType !== "docker" && deploymentType !== "zip") {
        throw new Error(`Invalid deployment_type '${deploymentType}'. Must be 'docker' or 'zip'.`)
      }

      const stackNameBase = parsedConfig.stack_name_base
      if (!stackNameBase) {
        throw new Error("stack_name_base is required in config.yaml")
      }
      if (stackNameBase.length > MAX_STACK_NAME_BASE_LENGTH) {
        throw new Error(
          `stack_name_base '${stackNameBase}' is too long (${stackNameBase.length} chars). ` +
            `Maximum length is ${MAX_STACK_NAME_BASE_LENGTH} characters due to AWS AgentCore runtime naming constraints.`
        )
      }

      // Validate network_mode if provided
      const networkMode = parsedConfig.backend?.network_mode || "PUBLIC"
      if (networkMode !== "PUBLIC" && networkMode !== "VPC") {
        throw new Error(`Invalid network_mode '${networkMode}'. Must be 'PUBLIC' or 'VPC'.`)
      }

      // Validate VPC configuration when network_mode is VPC
      const vpcConfig = parsedConfig.backend?.vpc
      if (networkMode === "VPC") {
        if (!vpcConfig) {
          throw new Error("backend.vpc configuration is required when network_mode is 'VPC'.")
        }
        if (!vpcConfig.vpc_id) {
          throw new Error("backend.vpc.vpc_id is required when network_mode is 'VPC'.")
        }
        if (!vpcConfig.subnet_ids || vpcConfig.subnet_ids.length === 0) {
          throw new Error("backend.vpc.subnet_ids must contain at least one subnet ID when network_mode is 'VPC'.")
        }
      }

      return {
        stack_name_base: stackNameBase,
        admin_user_email: parsedConfig.admin_user_email || null,
        backend: {
          pattern: parsedConfig.backend?.pattern || "strands-single-agent",
          deployment_type: deploymentType,
          network_mode: networkMode,
          vpc: vpcConfig,
        },
      }
    } catch (error) {
      throw new Error(`Failed to parse configuration file ${configPath}: ${error}`)
    }
  }

  public getProps(): AppConfig {
    return this.config
  }

  public get(key: string, defaultValue?: any): any {
    const keys = key.split(".")
    let value: any = this.config

    for (const k of keys) {
      if (typeof value === "object" && value !== null && k in value) {
        value = value[k]
      } else {
        return defaultValue
      }
    }

    return value
  }

  /**
   * Discover agents by scanning agents/{name}/agent.yaml directories.
   *
   * The directory structure IS the registry. Each agent is a subdirectory
   * under agents/ with an agent.yaml config file. No central registry needed.
   *
   * Search order for the agents/ directory:
   *   - Explicit path from CDK context (agents_dir)
   *   - {repo_root}/agents/       (team repo — standard location)
   *   - {cdk_parent}/agents/      (fallback if CDK is nested)
   *
   * If no agents/ directory is found, falls back to a single agent from config.yaml.
   */
  public discoverAgents(agentsDirOverride?: string): Record<string, AgentConfig> {
    const searchPaths = agentsDirOverride
      ? [agentsDirOverride]
      : [
          path.join(__dirname, "..", "..", "..", "agents"),
          path.join(__dirname, "..", "..", "..", "..", "agents"),
          path.join(__dirname, "..", "..", "agents"),
        ]

    let agentsDir: string | undefined
    for (const p of searchPaths) {
      if (fs.existsSync(p) && fs.statSync(p).isDirectory()) {
        agentsDir = p
        break
      }
    }

    if (!agentsDir) {
      return {
        "strands-single-agent": {
          team: "platform",
          pattern: this.config.backend.pattern,
          model_id: "",
          deployment_type: this.config.backend.deployment_type,
          memory: true,
          gateway: true,
          description: "Default agent from config.yaml",
        },
      }
    }

    const agents: Record<string, AgentConfig> = {}

    for (const entry of fs.readdirSync(agentsDir, { withFileTypes: true })) {
      if (!entry.isDirectory()) continue

      const agentYaml = path.join(agentsDir, entry.name, "agent.yaml")
      if (!fs.existsSync(agentYaml)) {
        console.log(`[CONFIG] Skipping agents/${entry.name}/ — no agent.yaml`)
        continue
      }

      try {
        const content = fs.readFileSync(agentYaml, "utf8")
        const parsed = yaml.parse(content) as AgentConfig
        agents[entry.name] = {
          team: parsed.team || "default",
          pattern: parsed.pattern || this.config.backend.pattern,
          model_id: parsed.model_id || "",
          deployment_type: parsed.deployment_type || this.config.backend.deployment_type,
          memory: parsed.memory !== false,
          gateway: parsed.gateway !== false,
          description: parsed.description || "",
        }
      } catch (error) {
        console.error(`[CONFIG] Failed to parse agents/${entry.name}/agent.yaml: ${error}`)
      }
    }

    if (Object.keys(agents).length === 0) {
      throw new Error("No valid agents found in agents/ directory. Each agent needs an agent.yaml file.")
    }

    console.log(`[CONFIG] Discovered ${Object.keys(agents).length} agent(s) from ${agentsDir}`)
    this.config.agents = agents
    return agents
  }
}
