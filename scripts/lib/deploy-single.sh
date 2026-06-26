#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# =============================================================================
# Agentic AI Platform - Single-account deploy
# Sourced by scripts/deploy.sh. Expects lib/common.sh to already be loaded.
# =============================================================================

deploy_single() {
    # Platform prefix — drives CFN stack name AND its ProjectName parameter
    # (pipeline, ECR, CodeCommit, Cognito, IAM, SSM, Secrets).
    local PLATFORM_STACK="agentic-ai-platform-single"
    local PLATFORM_PREFIX="agentic-ai-platform-single"
    # CDK prefix — AgentCore Gateway + per-agent stacks, runtime SSM keys.
    local CDK_PREFIX="fastagent-single"

    # Single account: deploy into the current account
    local TARGET_ACCT
    TARGET_ACCT=$(aws sts get-caller-identity --query Account --output text)

    echo "============================================================"
    echo "  Agentic AI Platform - Deploy Single"
    echo "  Region: ${REGION}"
    echo "  Account: ${TARGET_ACCT}"
    echo "============================================================"
    echo ""

    # Phase 1: Platform infra
    echo "Phase 1: Platform infrastructure"
    aws cloudformation deploy \
        --template-file "${TEMPLATE_DIR}/single-account.yaml" \
        --stack-name "${PLATFORM_STACK}" \
        --region "$REGION" \
        --capabilities CAPABILITY_NAMED_IAM \
        --no-fail-on-empty-changeset \
        --parameter-overrides "ProjectName=${PLATFORM_PREFIX}" "CdkStackName=${CDK_PREFIX}"
    echo ""

    # Phase 2: AgentCore
    echo "Phase 2: AgentCore (all-in-one)"
    npm install -g aws-cdk 2>/dev/null

    # Read Cognito + machine client outputs from CFN platform stack.
    # Cognito + machine client are entirely CFN-owned; CDK only consumes them
    # by id and reads the machine client secret directly from Cognito via
    # DescribeUserPoolClient at deploy time.
    local COGNITO_POOL COGNITO_CLIENT_ID COGNITO_DOMAIN MACHINE_CLIENT_ID
    COGNITO_POOL=$(aws cloudformation describe-stacks --stack-name "${PLATFORM_STACK}" --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue' --output text 2>/dev/null || echo "")
    COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name "${PLATFORM_STACK}" --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CognitoClientId`].OutputValue' --output text 2>/dev/null || echo "")
    COGNITO_DOMAIN=$(aws cloudformation describe-stacks --stack-name "${PLATFORM_STACK}" --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`CognitoDomain`].OutputValue' --output text 2>/dev/null || echo "")
    MACHINE_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name "${PLATFORM_STACK}" --region "$REGION" \
        --query 'Stacks[0].Outputs[?OutputKey==`MachineClientId`].OutputValue' --output text 2>/dev/null || echo "")

    if [[ -z "$COGNITO_POOL" || -z "$COGNITO_CLIENT_ID" || -z "$COGNITO_DOMAIN" \
        || -z "$MACHINE_CLIENT_ID" ]]; then
        echo "ERROR: Missing required outputs from ${PLATFORM_STACK} stack."
        echo "  CognitoUserPoolId:        ${COGNITO_POOL:-<empty>}"
        echo "  CognitoClientId:          ${COGNITO_CLIENT_ID:-<empty>}"
        echo "  CognitoDomain:            ${COGNITO_DOMAIN:-<empty>}"
        echo "  MachineClientId:          ${MACHINE_CLIENT_ID:-<empty>}"
        echo "  Check that the platform stack is in CREATE_COMPLETE / UPDATE_COMPLETE."
        exit 1
    fi
    echo "  Cognito User Pool:        ${COGNITO_POOL}"
    echo "  Cognito Client:           ${COGNITO_CLIENT_ID}"
    echo "  Cognito Domain:           ${COGNITO_DOMAIN}"
    echo "  Machine Client:           ${MACHINE_CLIENT_ID}"

    cd "$CDK_DIR"
    npm install --silent 2>/dev/null
    # Bootstrap with --app '' so CDK doesn't try to evaluate our TypeScript
    # entry (which needs Cognito context we can't provide here). Bootstrap
    # is idempotent — no-op if the CDKToolkit stack is already up to date.
    local FRESH_BOOTSTRAP=false
    if ! aws cloudformation describe-stacks --stack-name CDKToolkit --region "$REGION" &>/dev/null; then
        FRESH_BOOTSTRAP=true
    fi

    if ! cdk bootstrap --app '' "aws://${TARGET_ACCT}/${REGION}"; then
        echo "ERROR: cdk bootstrap failed for aws://${TARGET_ACCT}/${REGION}."
        echo "  Your AWS principal needs permissions to create the CDKToolkit stack"
        echo "  (IAM roles + ECR repo + S3 bucket). Run"
        echo "    cdk bootstrap --app '' aws://${TARGET_ACCT}/${REGION}"
        echo "  manually to see the underlying error."
        exit 1
    fi

    if [[ "$FRESH_BOOTSTRAP" == "true" ]]; then
        # On a brand-new account the CDKToolkit stack was just created and its
        # bucket policy may not be visible to CloudFormation yet, which can cause
        # the first cdk deploy changeset to hang in REVIEW_IN_PROGRESS.
        echo "  Fresh bootstrap detected — waiting 10s for IAM/S3 propagation..."
        sleep 10
    fi

    # Deploy both the Gateway stack and every per-agent stack in one pass.
    # Stack names are derived from stack_name_base:
    #   <CDK_PREFIX>-gateway         (AgentCore Gateway + tool Lambdas + OAuth2 provider)
    #   <CDK_PREFIX>-agent-<name>    (one per agent discovered in agents/)
    cdk deploy --all \
        --context stack_name="${CDK_PREFIX}" \
        --context project_name="${PROJECT}" \
        --context cognito_user_pool_id="${COGNITO_POOL}" \
        --context cognito_user_pool_client_id="${COGNITO_CLIENT_ID}" \
        --context cognito_user_pool_domain="${COGNITO_DOMAIN}" \
        --context machine_client_id="${MACHINE_CLIENT_ID}" \
        --require-approval never \
        --outputs-file /tmp/ac-single.json \
        2>&1

    clear_role

    # Collect runtime ARN for the first discovered agent (for legacy output file)
    local RUNTIME_ARN MEMORY_ARN
    RUNTIME_ARN=$(python3 -c "
import json
data = json.load(open('/tmp/ac-single.json'))
for name, outputs in data.items():
    if name.startswith('${CDK_PREFIX}-agent-') and outputs.get('RuntimeArn'):
        print(outputs['RuntimeArn']); break
" 2>/dev/null || echo "")
    MEMORY_ARN=$(python3 -c "
import json
data = json.load(open('/tmp/ac-single.json'))
for name, outputs in data.items():
    if name.startswith('${CDK_PREFIX}-agent-') and outputs.get('MemoryArn'):
        print(outputs['MemoryArn']); break
" 2>/dev/null || echo "")

    # Sync Cognito values to SSM (pipeline reads these under the platform prefix)
    if [[ -n "$COGNITO_POOL" ]]; then
        aws ssm put-parameter --name "/${PLATFORM_PREFIX}/cognito-user-pool-id" --value "$COGNITO_POOL" --type String --overwrite --region "$REGION" 2>/dev/null || true
        aws ssm put-parameter --name "/${PLATFORM_PREFIX}/cognito-user-pool-client-id" --value "$COGNITO_CLIENT_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true
        echo "  Cognito SSM params synced."
    fi

    # Create pipeline eval user (needed for on-demand evaluation in the pipeline)
    if [[ -n "$COGNITO_POOL" ]]; then
        echo "  Creating pipeline eval user..."
        local PIPELINE_USER="pipeline-eval@${PROJECT}.internal"
        local PIPELINE_PASS
        PIPELINE_PASS=$(python3 -c "import secrets,string; print(secrets.token_urlsafe(16) + '!A1a')" 2>/dev/null)
        if ! aws cognito-idp admin-get-user --user-pool-id "$COGNITO_POOL" --username "$PIPELINE_USER" --region "$REGION" &>/dev/null; then
            aws cognito-idp admin-create-user --user-pool-id "$COGNITO_POOL" --username "$PIPELINE_USER" \
                --user-attributes Name=email,Value="$PIPELINE_USER" Name=email_verified,Value=true \
                --message-action SUPPRESS --region "$REGION" > /dev/null
        fi
        aws cognito-idp admin-set-user-password --user-pool-id "$COGNITO_POOL" --username "$PIPELINE_USER" \
            --password "$PIPELINE_PASS" --permanent --region "$REGION"
        aws secretsmanager create-secret --name "/${PLATFORM_PREFIX}/pipeline_eval_credentials" \
            --secret-string "{\"username\":\"${PIPELINE_USER}\",\"password\":\"${PIPELINE_PASS}\"}" \
            --region "$REGION" 2>/dev/null \
        || aws secretsmanager put-secret-value --secret-id "/${PLATFORM_PREFIX}/pipeline_eval_credentials" \
            --secret-string "{\"username\":\"${PIPELINE_USER}\",\"password\":\"${PIPELINE_PASS}\"}" \
            --region "$REGION" 2>/dev/null || true
        echo "  Pipeline eval user ready."
    fi

    # Phase 3: Scaffold agent repo
    echo "Phase 3: Scaffold agent repo"
    if ! pip show git-remote-codecommit &>/dev/null; then
        echo "  Installing git-remote-codecommit..."
        pip install git-remote-codecommit --quiet
    fi

    local CC_TMP
    CC_TMP=$(mktemp -d)

    local EXAMPLE_AGENT="strands-single-agent"
    local CC_REPO="${PLATFORM_PREFIX}-agents"
    local CC_URL="codecommit::${REGION}://${CC_REPO}"
    local TEAM_DIR="$CC_TMP/agents"

    echo "  Repo: ${CC_REPO}"

    if git ls-remote "$CC_URL" &>/dev/null; then
        git clone "$CC_URL" "$TEAM_DIR" --quiet 2>/dev/null || git init "$TEAM_DIR" --quiet
    else
        git init "$TEAM_DIR" --quiet
    fi

    local PATTERN_DIR="${REPO_ROOT}/agentcore/patterns/strands-single-agent"
    mkdir -p "$TEAM_DIR/agents/${EXAMPLE_AGENT}/prompts"
    mkdir -p "$TEAM_DIR/agents/${EXAMPLE_AGENT}/eval"
    cp "${PATTERN_DIR}/"*.py "$TEAM_DIR/agents/${EXAMPLE_AGENT}/" 2>/dev/null || true
    cp "${PATTERN_DIR}/requirements.txt" "$TEAM_DIR/agents/${EXAMPLE_AGENT}/" 2>/dev/null || true
    cp "${PATTERN_DIR}/README.md" "$TEAM_DIR/agents/${EXAMPLE_AGENT}/" 2>/dev/null || true
    [[ -d "${PATTERN_DIR}/tools" ]] && cp -r "${PATTERN_DIR}/tools" "$TEAM_DIR/agents/${EXAMPLE_AGENT}/"

    cat > "$TEAM_DIR/agents/${EXAMPLE_AGENT}/Dockerfile" <<'DOCKERFILE'
FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim
WORKDIR /app
ENV UV_SYSTEM_PYTHON=1 UV_COMPILE_BYTECODE=1 DOCKER_CONTAINER=1 OTEL_PYTHON_LOG_CORRELATION=true PYTHONUNBUFFERED=1
COPY shared/gateway/ gateway/
COPY agents/strands-single-agent/requirements.txt requirements.txt
RUN uv pip install --no-cache -r requirements.txt && \
    uv pip install --no-cache aws-opentelemetry-distro==0.12.2 requests>=2.31.0
RUN useradd -m -u 1000 bedrock_agentcore
USER bedrock_agentcore
EXPOSE 8080
COPY agents/strands-single-agent/*.py .
COPY shared/utils/ utils/
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/ping', timeout=2)" || exit 1
CMD ["opentelemetry-instrument", "python", "-m", "basic_agent"]
DOCKERFILE

    cat > "$TEAM_DIR/agents/${EXAMPLE_AGENT}/agent.yaml" <<'AGENTYAML'
team: default
pattern: strands-single-agent
model_id: global.anthropic.claude-haiku-4-5-20251001-v1:0
deployment_type: zip
memory: true
gateway: true
description: Reference agent with Gateway tools and Code Interpreter
AGENTYAML

    echo "You are a helpful AI assistant." > "$TEAM_DIR/agents/${EXAMPLE_AGENT}/prompts/system_prompt.txt"

    # Seed eval cases from the pattern's evals/ dir. Fall back to a minimal
    # default if the pattern didn't ship any.
    local PATTERN_EVAL_FILES=()
    if [[ -d "${PATTERN_DIR}/evals" ]]; then
        shopt -s nullglob
        PATTERN_EVAL_FILES=("${PATTERN_DIR}/evals"/*.yaml "${PATTERN_DIR}/evals"/*.yml "${PATTERN_DIR}/evals"/*.json)
        shopt -u nullglob
    fi
    if (( ${#PATTERN_EVAL_FILES[@]} > 0 )); then
        cp "${PATTERN_EVAL_FILES[@]}" "$TEAM_DIR/agents/${EXAMPLE_AGENT}/eval/"
        echo "  Seeded ${#PATTERN_EVAL_FILES[@]} eval case file(s) from pattern."
    else
        cat > "$TEAM_DIR/agents/${EXAMPLE_AGENT}/eval/eval_cases.yaml" <<'EVALEOF'
cases:
  - name: "Basic greeting"
    prompt: "Hello, how are you? What can you help me with?"
    assertions:
      - "Agent responded politely"
      - "Agent described its capabilities or available tools"
    trajectory: []
EVALEOF
    fi

    # Shared libs + infra. Wipe first so repeated runs don't nest
    # `shared/gateway/gateway/...` because `cp -r src dst` copies INTO dst
    # when dst already exists.
    rm -rf "$TEAM_DIR/shared" "$TEAM_DIR/infra-cdk"
    mkdir -p "$TEAM_DIR/shared"
    cp -r "${REPO_ROOT}/agentcore/patterns/utils" "$TEAM_DIR/shared/utils"
    [[ -d "${REPO_ROOT}/agentcore/gateway" ]] && cp -r "${REPO_ROOT}/agentcore/gateway" "$TEAM_DIR/shared/gateway"
    [[ -d "${REPO_ROOT}/agentcore/tools" ]] && cp -r "${REPO_ROOT}/agentcore/tools" "$TEAM_DIR/shared/tools"
    cp -r "${REPO_ROOT}/agentcore/infra-cdk" "$TEAM_DIR/infra-cdk"
    mkdir -p "$TEAM_DIR/scripts"
    cp "${REPO_ROOT}/scripts/pipeline_eval.py" "$TEAM_DIR/scripts/"

    pushd "$TEAM_DIR" > /dev/null
    git add -A
    if git diff --cached --quiet 2>/dev/null; then
        echo "  No changes to push."
    else
        git commit -m "Initial scaffold from deploy $(date -u +%Y-%m-%dT%H:%M:%SZ)" --quiet
        if ! git remote get-url origin &>/dev/null; then
            git remote add origin "$CC_URL"
        fi
        git push origin HEAD:main --quiet 2>/dev/null || git push origin HEAD:main --force --quiet
        echo "  Pushed to ${CC_REPO} (main)."
    fi
    popd > /dev/null
    rm -rf "$CC_TMP"

    cd "$REPO_ROOT"

    cat > "${OUT_DIR}/single-$(date -u +%Y-%m-%dT%H-%M-%S).json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "single",
  "account": "${TARGET_ACCT}",
  "platform_prefix": "${PLATFORM_PREFIX}",
  "cdk_prefix": "${CDK_PREFIX}",
  "cognito_user_pool_id": "${COGNITO_POOL}",
  "runtime_arn": "${RUNTIME_ARN}",
  "memory_arn": "${MEMORY_ARN}"
}
EOF

    # --- Phase 4: Verify Transaction Search is ACTIVE ---
    # Single-account deploy runs in the caller's credentials, so no role
    # assumption needed — just poll X-Ray directly for up to ~3 min.
    echo ""
    echo "Phase 4: Verify Transaction Search readiness"
    local txn_attempts=0
    local txn_max=18   # 18 × 10s = 3 min
    local txn_state=""
    while (( txn_attempts < txn_max )); do
        txn_state=$(aws xray get-trace-segment-destination --region "$REGION" \
            --query 'Status' --output text 2>/dev/null || echo "UNKNOWN")
        [[ "$txn_state" == "ACTIVE" ]] && break
        (( txn_attempts++ ))
        sleep 10
    done
    if [[ "$txn_state" == "ACTIVE" ]]; then
        echo "  Transaction Search ACTIVE."
    else
        echo "  WARN - Transaction Search still ${txn_state} after ~3 min."
        echo "         First pipeline eval run may see incomplete spans; re-run if so."
    fi

    echo ""
    echo "  Single account deploy complete."
    echo "  Account: ${TARGET_ACCT}"
    echo "  Runtime: ${RUNTIME_ARN}"
    echo "  Output: ${OUT_DIR}/single-*.json"
    echo ""
}
