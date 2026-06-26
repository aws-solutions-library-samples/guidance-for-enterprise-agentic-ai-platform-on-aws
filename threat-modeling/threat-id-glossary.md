<!-- Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved. -->
<!-- SPDX-License-Identifier: MIT-0 -->

# Threat ID Glossary

Every threat ID in the model, one line each, with a link to its detail. Use this as the entry point when a threat ID is referenced elsewhere (commit messages, reviews, runbooks).

## Agent Runtime (RT)

- **RT.T01** — Prompt injection via user input → [agent-runtime.md](feature-threats/agent-runtime.md#rtt01--prompt-injection-via-user-input)
- **RT.T02** — Prompt injection via tool output → [agent-runtime.md](feature-threats/agent-runtime.md#rtt02--prompt-injection-via-tool-output)
- **RT.T03** — Runtime IAM role over-privilege → [agent-runtime.md](feature-threats/agent-runtime.md#rtt03--runtime-iam-role-over-privilege)
- **RT.T04** — Session ID spoofing / hijack → [agent-runtime.md](feature-threats/agent-runtime.md#rtt04--session-id-spoofing--hijack)
- **RT.T05** — Model region/egress misconfiguration → [agent-runtime.md](feature-threats/agent-runtime.md#rtt05--model-regionegress-misconfiguration)
- **RT.T06** — Denial of wallet via agent loop amplification → [agent-runtime.md](feature-threats/agent-runtime.md#rtt06--denial-of-wallet-via-agent-loop-amplification)
- **RT.T07** — Streaming response tampering → [agent-runtime.md](feature-threats/agent-runtime.md#rtt07--streaming-response-tampering)

## Gateway & Tools (GW)

- **GW.T01** — Tool authorization bypass → [gateway-tools.md](feature-threats/gateway-tools.md#gwt01--tool-authorization-bypass)
- **GW.T02** — Tool response injection → [gateway-tools.md](feature-threats/gateway-tools.md#gwt02--tool-response-injection)
- **GW.T03** — Tool Lambda IAM over-privilege → [gateway-tools.md](feature-threats/gateway-tools.md#gwt03--tool-lambda-iam-over-privilege)
- **GW.T04** — Lambda target tampering → [gateway-tools.md](feature-threats/gateway-tools.md#gwt04--lambda-target-tampering)
- **GW.T05** — Gateway endpoint exposure → [gateway-tools.md](feature-threats/gateway-tools.md#gwt05--gateway-endpoint-exposure)
- **GW.T06** — MCP protocol vulnerability → [gateway-tools.md](feature-threats/gateway-tools.md#gwt06--mcp-protocol-vulnerability)

## Code Interpreter (CI)

- **CI.T01** — Arbitrary code execution via prompt injection → [code-interpreter.md](feature-threats/code-interpreter.md#cit01--arbitrary-code-execution-via-prompt-injection)
- **CI.T02** — Data exfiltration via code output → [code-interpreter.md](feature-threats/code-interpreter.md#cit02--data-exfiltration-via-code-output)
- **CI.T03** — Sandbox escape (AWS-service-level) → [code-interpreter.md](feature-threats/code-interpreter.md#cit03--sandbox-escape-aws-service-level)
- **CI.T04** — Cost amplification → [code-interpreter.md](feature-threats/code-interpreter.md#cit04--cost-amplification)

## Memory (MEM)

- **MEM.T01** — Cross-session / cross-user memory leakage → [memory.md](feature-threats/memory.md#memt01--cross-session--cross-user-memory-leakage)
- **MEM.T02** — Memory poisoning → [memory.md](feature-threats/memory.md#memt02--memory-poisoning)
- **MEM.T03** — Memory retention beyond compliance window → [memory.md](feature-threats/memory.md#memt03--memory-retention-beyond-compliance-window)
- **MEM.T04** — Memory ARN exposure / confusion → [memory.md](feature-threats/memory.md#memt04--memory-arn-exposure--confusion)

## Identity & Auth (AUTH)

- **AUTH.T01** — JWT theft and replay → [identity-auth.md](feature-threats/identity-auth.md#autht01--jwt-theft-and-replay)
- **AUTH.T02** — OAuth2 client secret exposure → [identity-auth.md](feature-threats/identity-auth.md#autht02--oauth2-client-secret-exposure)
- **AUTH.T03** — Privilege escalation via custom Cognito claims → [identity-auth.md](feature-threats/identity-auth.md#autht03--privilege-escalation-via-custom-cognito-claims)
- **AUTH.T04** — Pipeline-eval user credential exposure → [identity-auth.md](feature-threats/identity-auth.md#autht04--pipeline-eval-user-credential-exposure)
- **AUTH.T05** — Cognito self-signup enabled in production → [identity-auth.md](feature-threats/identity-auth.md#autht05--cognito-self-signup-enabled-in-production)
- **AUTH.T06** — Token Vault contents leak via IAM → [identity-auth.md](feature-threats/identity-auth.md#autht06--token-vault-contents-leak-via-iam)

## Cross-Account Deploy (DEPLOY)

- **DEPLOY.T01** — OrganizationAccountAccessRole abuse → [cross-account-deploy.md](feature-threats/cross-account-deploy.md#deployt01--organizationaccountaccessrole-abuse)
- **DEPLOY.T02** — StackSet admin role abuse → [cross-account-deploy.md](feature-threats/cross-account-deploy.md#deployt02--stackset-admin-role-abuse)
- **DEPLOY.T03** — Trust-policy drift in member accounts → [cross-account-deploy.md](feature-threats/cross-account-deploy.md#deployt03--trust-policy-drift-in-member-accounts)
- **DEPLOY.T04** — CFN template tampering → [cross-account-deploy.md](feature-threats/cross-account-deploy.md#deployt04--cfn-template-tampering)
- **DEPLOY.T05** — SCP bypass via deploy scope → [cross-account-deploy.md](feature-threats/cross-account-deploy.md#deployt05--scp-bypass-via-deploy-scope)

## CI/CD Pipeline (CICD)

- **CICD.T01** — Artifact tampering in pipeline bucket → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt01--artifact-tampering-in-pipeline-bucket)
- **CICD.T02** — Evaluation gate bypass → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt02--evaluation-gate-bypass)
- **CICD.T03** — Pipeline role assumption by human → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt03--pipeline-role-assumption-by-human)
- **CICD.T04** — Source-stage poisoning → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt04--source-stage-poisoning)
- **CICD.T05** — Manual approval misuse → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt05--manual-approval-misuse)
- **CICD.T06** — ECR image tampering → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt06--ecr-image-tampering)
- **CICD.T07** — Eval flakiness masking real failures → [cicd-pipeline.md](feature-threats/cicd-pipeline.md#cicdt07--eval-flakiness-masking-real-failures)

## Observability (OBS)

- **OBS.T01** — OAM sink policy widened → [observability.md](feature-threats/observability.md#obst01--oam-sink-policy-widened)
- **OBS.T02** — Sensitive content in logs / traces → [observability.md](feature-threats/observability.md#obst02--sensitive-content-in-logs--traces)
- **OBS.T03** — Log tampering / deletion → [observability.md](feature-threats/observability.md#obst03--log-tampering--deletion)
- **OBS.T04** — OAM link hijack via lifecycle drift → [observability.md](feature-threats/observability.md#obst04--oam-link-hijack-via-lifecycle-drift)
- **OBS.T05** — Transaction Search misconfiguration / disablement → [observability.md](feature-threats/observability.md#obst05--transaction-search-misconfiguration--disablement)