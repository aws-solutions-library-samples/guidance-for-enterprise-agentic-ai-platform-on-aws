#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# =============================================================================
# Agentic AI Platform - Enterprise (multi-account) deploy
# Sourced by scripts/deploy.sh. Expects lib/common.sh to already be loaded.
# =============================================================================

deploy_enterprise() {
    local PREFIX="fastagent-enterprise"
    local STACK_NAME="${PREFIX}"
    local MGMT_ID
    MGMT_ID=$(aws sts get-caller-identity --query Account --output text)

    # Verify we're running from the management account
    local CALLER_ARN
    CALLER_ARN=$(aws sts get-caller-identity --query Arn --output text)
    if [[ "$CALLER_ARN" == *"assumed-role"* && "$CALLER_ARN" == *"OrganizationAccountAccessRole"* ]]; then
        echo "ERROR: You're running from an assumed role in a member account."
        echo "       Enterprise deploy must run from the management account."
        echo "       Run: unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN"
        exit 1
    fi

    # --- Resolve account IDs (must happen before banner so we can print them) ---
    local SEC_ID OBS_ID ST_ID DEV_ID STAGING_ID PROD_ID
    SEC_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/security"       --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || yaml_account_id "security")
    OBS_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/observability"  --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || yaml_account_id "observability")
    ST_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/shared-tooling"  --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || yaml_account_id "shared-tooling")
    DEV_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/dev"            --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || yaml_account_id "dev")
    STAGING_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/staging"    --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || yaml_account_id "staging")
    PROD_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/prod"          --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || yaml_account_id "prod")

    local missing=()
    [[ -z "$SEC_ID"     ]] && missing+=("security")
    [[ -z "$OBS_ID"     ]] && missing+=("observability")
    [[ -z "$ST_ID"      ]] && missing+=("shared-tooling")
    [[ -z "$DEV_ID"     ]] && missing+=("dev")
    [[ -z "$STAGING_ID" ]] && missing+=("staging")
    [[ -z "$PROD_ID"    ]] && missing+=("prod")
    if (( ${#missing[@]} > 0 )); then
        echo "ERROR: Missing account IDs for: ${missing[*]}"
        echo ""
        echo "Populate enterpriseAccounts in infra/config.yaml with the 6"
        echo "account IDs. Provision accounts via AWS Control Tower Account"
        echo "Factory, AFT, or 'aws organizations create-account'."
        exit 1
    fi

    echo "============================================================"
    echo "  Agentic AI Platform - Deploy Enterprise"
    echo "  Region: ${REGION}"
    echo "  Accounts:"
    echo "    Management:     ${MGMT_ID}"
    echo "    Security:       ${SEC_ID}"
    echo "    Observability:  ${OBS_ID}"
    echo "    Shared Tooling: ${ST_ID}"
    echo "    Dev:            ${DEV_ID}"
    echo "    Staging:        ${STAGING_ID}"
    echo "    Prod:           ${PROD_ID}"
    echo "============================================================"
    echo ""

    # Ensure StackSet prerequisites (idempotent, always runs)
    echo "Ensuring StackSet prerequisites..."
    aws organizations enable-aws-service-access --service-principal member.org.stacksets.cloudformation.amazonaws.com --region "$REGION" 2>/dev/null || true
    aws cloudformation activate-organizations-access --region "$REGION" 2>/dev/null || true
    if ! aws iam get-role --role-name AWSCloudFormationStackSetAdministrationRole &>/dev/null; then
        aws iam create-role --role-name AWSCloudFormationStackSetAdministrationRole \
            --assume-role-policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Principal":{"Service":"cloudformation.amazonaws.com"},"Action":"sts:AssumeRole"}]}' > /dev/null
        aws iam put-role-policy --role-name AWSCloudFormationStackSetAdministrationRole --policy-name AssumeExecutionRole \
            --policy-document '{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":"sts:AssumeRole","Resource":"arn:aws:iam::*:role/OrganizationAccountAccessRole"}]}'
    fi

    # Verify every target account has an assumable OrganizationAccountAccessRole.
    local missing_targets=()
    local tgt_acct tgt_label
    for pair in \
        "security:${SEC_ID}" \
        "observability:${OBS_ID}" \
        "shared-tooling:${ST_ID}" \
        "dev:${DEV_ID}" \
        "staging:${STAGING_ID}" \
        "prod:${PROD_ID}"; do
        tgt_label="${pair%%:*}"
        tgt_acct="${pair##*:}"
        [[ -z "$tgt_acct" ]] && continue
        if ! aws sts assume-role \
                --role-arn "arn:aws:iam::${tgt_acct}:role/OrganizationAccountAccessRole" \
                --role-session-name prereq-check \
                --duration-seconds 900 &>/dev/null; then
            missing_targets+=("${tgt_label} (${tgt_acct})")
        fi
    done
    if (( ${#missing_targets[@]} > 0 )); then
        echo ""
        echo "ERROR: OrganizationAccountAccessRole is missing or not assumable"
        echo "       in the following ${#missing_targets[@]} account(s):"
        echo ""
        for t in "${missing_targets[@]}"; do
            echo "  - ${t}"
        done
        echo ""
        echo "(Other target accounts passed the check — only the ones above need fixing.)"
        echo ""
        echo "This role is required for StackSets in self-managed"
        echo "(OrganizationAccountAccessRole) mode. Accounts created via"
        echo "'aws organizations create-account' get this role automatically."
        echo "Invited accounts, or accounts created out-of-band, do not."
        echo ""
        echo "For EACH account listed above, run (as that account's admin, or"
        echo "via a role in that account with IAM admin rights):"
        echo ""
        echo "  aws iam create-role --role-name OrganizationAccountAccessRole \\"
        echo "    --assume-role-policy-document '{\"Version\":\"2012-10-17\",\"Statement\":["
        echo "      {\"Effect\":\"Allow\",\"Principal\":{\"AWS\":\"arn:aws:iam::<MGMT_ACCOUNT_ID>:root\"},"
        echo "       \"Action\":\"sts:AssumeRole\"}]}'"
        echo ""
        echo "  aws iam attach-role-policy --role-name OrganizationAccountAccessRole \\"
        echo "    --policy-arn arn:aws:iam::aws:policy/AdministratorAccess"
        echo ""
        echo "Then re-run this script."
        exit 1
    fi
    echo "  All target accounts have OrganizationAccountAccessRole."
    echo ""

    # Persist account IDs to SSM
    aws ssm put-parameter --name "/${PROJECT}/accounts/security"       --value "$SEC_ID"     --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/accounts/observability"  --value "$OBS_ID"     --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/accounts/shared-tooling" --value "$ST_ID"      --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/accounts/dev"            --value "$DEV_ID"     --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/accounts/staging"        --value "$STAGING_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/accounts/prod"           --value "$PROD_ID"    --type String --overwrite --region "$REGION" 2>/dev/null || true

    # --- Phase 1: Platform StackSets ---
    echo "Phase 1: Platform stacks"

    # Enable CloudTrail trusted access before creating org trail
    aws organizations enable-aws-service-access \
        --service-principal cloudtrail.amazonaws.com --region "$REGION" 2>/dev/null || true

    aws cloudformation deploy --template-file "${TEMPLATE_DIR}/enterprise/platform/management.yaml" \
        --stack-name "${PROJECT}-management" --region "$REGION" --capabilities CAPABILITY_NAMED_IAM \
        --no-fail-on-empty-changeset --parameter-overrides "ProjectName=${PROJECT}" "SecurityAccountId=${SEC_ID}"
    echo ""

    deploy_stackset "${PROJECT}-security" "${TEMPLATE_DIR}/enterprise/platform/security.yaml" "$SEC_ID" \
        "$(ss_param ProjectName "$PROJECT")" "$(ss_param StackName "$STACK_NAME")" \
        "$(ss_param ManagementAccountId "$MGMT_ID")" \
        "$(ss_param ObservabilityAccountId "$OBS_ID")" "$(ss_param SharedToolingAccountId "$ST_ID")" \
        "$(ss_param DevAccountId "$DEV_ID")" "$(ss_param StagingAccountId "${STAGING_ID}")" \
        "$(ss_param ProdAccountId "${PROD_ID}")"

    deploy_stackset "${PROJECT}-observability" "${TEMPLATE_DIR}/enterprise/platform/observability.yaml" "$OBS_ID" \
        "$(ss_param ProjectName "$PROJECT")" \
        "$(ss_param SharedToolingAccountId "$ST_ID")" "$(ss_param DevAccountId "$DEV_ID")" \
        "$(ss_param StagingAccountId "${STAGING_ID}")" "$(ss_param ProdAccountId "${PROD_ID}")"

    deploy_stackset "${PROJECT}-shared-tooling" "${TEMPLATE_DIR}/enterprise/platform/shared-tooling.yaml" "$ST_ID" \
        "$(ss_param ProjectName "$PROJECT")" "$(ss_param StackName "$STACK_NAME")" \
        "$(ss_param DevAccountId "$DEV_ID")" "$(ss_param StagingAccountId "${STAGING_ID}")" \
        "$(ss_param ProdAccountId "${PROD_ID}")" "$(ss_param ObservabilityAccountId "$OBS_ID")" \
        "$(ss_param CognitoUserPoolId "")" "$(ss_param CognitoClientId "")" \
        "$(ss_param CognitoUserPoolDomain "")" \
        "$(ss_param DevMachineClientId "")" "$(ss_param StagingMachineClientId "")" \
        "$(ss_param ProdMachineClientId "")" \
        "$(ss_param MachineClientDescribeRoleArn "")"

    # Get observability sink ARN for cross-account metrics
    local SINK_ARN=""
    SINK_ARN=$(aws ssm get-parameter --name "/${PROJECT}/observability/sink-arn" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    if [[ -z "$SINK_ARN" ]]; then
        assume_role "$OBS_ID" "get-sink-arn"
        SINK_ARN=$(aws ssm get-parameter --name "/${PROJECT}/observability/sink-arn" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
        clear_role
        if [[ -n "$SINK_ARN" ]]; then
            aws ssm put-parameter --name "/${PROJECT}/observability/sink-arn" --value "$SINK_ARN" --type String --overwrite --region "$REGION" 2>/dev/null || true
        fi
    fi

    deploy_stackset "${PROJECT}-dev" "${TEMPLATE_DIR}/enterprise/workloads/dev.yaml" "$DEV_ID" \
        "$(ss_param ProjectName "$PROJECT")" "$(ss_param Environment "dev")" \
        "$(ss_param SharedToolingAccountId "$ST_ID")"

    deploy_stackset "${PROJECT}-staging" "${TEMPLATE_DIR}/enterprise/workloads/dev.yaml" "$STAGING_ID" \
        "$(ss_param ProjectName "$PROJECT")" "$(ss_param Environment "staging")" \
        "$(ss_param SharedToolingAccountId "$ST_ID")"

    deploy_stackset "${PROJECT}-prod" "${TEMPLATE_DIR}/enterprise/workloads/dev.yaml" "$PROD_ID" \
        "$(ss_param ProjectName "$PROJECT")" "$(ss_param Environment "prod")" \
        "$(ss_param SharedToolingAccountId "$ST_ID")"

    # --- Phase 2: Read identity outputs from the Security account ---
    echo "Phase 2: Read identity outputs from security account"
    assume_role "$SEC_ID" "enterprise-identity-read"

    local COGNITO_POOL_ID COGNITO_CLIENT_ID COGNITO_DOMAIN
    local SECURITY_STACK
    SECURITY_STACK=$(aws cloudformation list-stacks --region "$REGION" \
        --query "StackSummaries[?starts_with(StackName, 'StackSet-${PROJECT}-security-') && StackStatus=='CREATE_COMPLETE' || StackStatus=='UPDATE_COMPLETE'].StackName | [0]" \
        --output text 2>/dev/null || echo "")
    if [[ -z "$SECURITY_STACK" || "$SECURITY_STACK" == "None" ]]; then
        SECURITY_STACK=$(aws cloudformation list-stacks --region "$REGION" \
            --query "StackSummaries[?starts_with(StackName, 'StackSet-${PROJECT}-security-')].StackName | [0]" \
            --output text 2>/dev/null || echo "")
    fi
    if [[ -z "$SECURITY_STACK" || "$SECURITY_STACK" == "None" ]]; then
        echo "ERROR: Couldn't find security stack instance in Security account."
        exit 1
    fi
    echo "  Security stack: ${SECURITY_STACK}"

    COGNITO_POOL_ID=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolId'].OutputValue" --output text)
    COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolClientId'].OutputValue" --output text)
    COGNITO_DOMAIN=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='UserPoolDomain'].OutputValue" --output text)

    local DEV_MC_ID STAGING_MC_ID PROD_MC_ID
    DEV_MC_ID=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='DevMachineClientId'].OutputValue" --output text 2>/dev/null || echo "")
    STAGING_MC_ID=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='StagingMachineClientId'].OutputValue" --output text 2>/dev/null || echo "")
    PROD_MC_ID=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='ProdMachineClientId'].OutputValue" --output text 2>/dev/null || echo "")

    local MACHINE_CLIENT_DESCRIBE_ROLE_ARN
    MACHINE_CLIENT_DESCRIBE_ROLE_ARN=$(aws cloudformation describe-stacks --stack-name "$SECURITY_STACK" --region "$REGION" \
        --query "Stacks[0].Outputs[?OutputKey=='MachineClientDescribeRoleArn'].OutputValue" --output text 2>/dev/null || echo "")

    # Create pipeline test user for eval (idempotent)
    echo "  Creating pipeline test user..."
    local PIPELINE_USER="pipeline-eval@${PROJECT}.internal"
    local PIPELINE_PASS
    PIPELINE_PASS=$(python3 -c "import secrets,string; print(secrets.token_urlsafe(16) + '!A1a')" 2>/dev/null)
    if ! aws cognito-idp admin-get-user --user-pool-id "$COGNITO_POOL_ID" --username "$PIPELINE_USER" --region "$REGION" &>/dev/null; then
        aws cognito-idp admin-create-user --user-pool-id "$COGNITO_POOL_ID" --username "$PIPELINE_USER" \
            --user-attributes Name=email,Value="$PIPELINE_USER" Name=email_verified,Value=true \
            --message-action SUPPRESS --region "$REGION" > /dev/null
        aws cognito-idp admin-set-user-password --user-pool-id "$COGNITO_POOL_ID" --username "$PIPELINE_USER" \
            --password "$PIPELINE_PASS" --permanent --region "$REGION"
        echo "  Pipeline test user created: ${PIPELINE_USER}"
    else
        echo "  Pipeline test user already exists, updating password..."
        aws cognito-idp admin-set-user-password --user-pool-id "$COGNITO_POOL_ID" --username "$PIPELINE_USER" \
            --password "$PIPELINE_PASS" --permanent --region "$REGION"
    fi
    aws secretsmanager create-secret --name "/${STACK_NAME}/pipeline_eval_credentials" \
        --secret-string "{\"username\":\"${PIPELINE_USER}\",\"password\":\"${PIPELINE_PASS}\"}" \
        --region "$REGION" 2>/dev/null \
    || aws secretsmanager put-secret-value --secret-id "/${STACK_NAME}/pipeline_eval_credentials" \
        --secret-string "{\"username\":\"${PIPELINE_USER}\",\"password\":\"${PIPELINE_PASS}\"}" \
        --region "$REGION" 2>/dev/null || true
    echo "  Pipeline eval credentials stored in Secrets Manager."

    clear_role

    # Store in management account SSM
    aws ssm put-parameter --name "/${PROJECT}/agentcore/cognito-user-pool-id" --value "$COGNITO_POOL_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/agentcore/cognito-client-id" --value "$COGNITO_CLIENT_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true
    aws ssm put-parameter --name "/${PROJECT}/agentcore/auth-account-id" --value "$SEC_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true
    echo "  Cognito User Pool: ${COGNITO_POOL_ID}"
    echo "  Cognito Domain:    ${COGNITO_DOMAIN}"
    echo ""

    # Prepare shared CDK directory for workload deploys
    npm install -g aws-cdk 2>/dev/null
    cd "$CDK_DIR"
    npm install --silent 2>/dev/null

    # --- Phase 3: AgentCore workloads → dev, staging, prod ---
    deploy_workload() {
        local env_name="$1" acct_id="$2"
        [[ -z "$acct_id" ]] && return

        local MC_ID=""
        case "$env_name" in
            dev)     MC_ID="${DEV_MC_ID:-}" ;;
            staging) MC_ID="${STAGING_MC_ID:-}" ;;
            prod)    MC_ID="${PROD_MC_ID:-}" ;;
        esac
        if [[ -z "$MC_ID" ]]; then
            local cap_env
            cap_env="$(tr '[:lower:]' '[:upper:]' <<< "${env_name:0:1}")${env_name:1}"
            echo "  ERROR: Missing machine client for env=${env_name} in security stack outputs."
            echo "         Expected ${cap_env}MachineClientId."
            return 1
        fi

        echo ""
        echo "--- Deploying workload → ${env_name} (${acct_id}) ---"
        assume_role "$acct_id" "enterprise-${env_name}"
        if ! cdk bootstrap --app '' "aws://${acct_id}/${REGION}"; then
            echo "  ERROR: cdk bootstrap failed for aws://${acct_id}/${REGION}."
            return 1
        fi

        # Sync pipeline eval credentials to workload account
        aws secretsmanager create-secret --name "/${STACK_NAME}/pipeline_eval_credentials" \
            --secret-string "{\"username\":\"${PIPELINE_USER}\",\"password\":\"${PIPELINE_PASS}\"}" \
            --region "$REGION" 2>/dev/null \
        || aws secretsmanager put-secret-value --secret-id "/${STACK_NAME}/pipeline_eval_credentials" \
            --secret-string "{\"username\":\"${PIPELINE_USER}\",\"password\":\"${PIPELINE_PASS}\"}" \
            --region "$REGION" 2>/dev/null || true

        # Sync Cognito discovery info into local SSM
        aws ssm put-parameter --name "/${STACK_NAME}/cognito-user-pool-id" --value "$COGNITO_POOL_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true
        aws ssm put-parameter --name "/${STACK_NAME}/cognito-user-pool-client-id" --value "$COGNITO_CLIENT_ID" --type String --overwrite --region "$REGION" 2>/dev/null || true

        cd "$CDK_DIR"
        cdk deploy --all \
            --context stack_name="${STACK_NAME}" \
            --context cognito_user_pool_id="${COGNITO_POOL_ID}" \
            --context cognito_user_pool_client_id="${COGNITO_CLIENT_ID}" \
            --context cognito_user_pool_domain="${COGNITO_DOMAIN}" \
            --context machine_client_id="${MC_ID}" \
            --context machine_client_describe_role_arn="${MACHINE_CLIENT_DESCRIBE_ROLE_ARN}" \
            --context project_name="${PROJECT}" \
            --require-approval never \
            --outputs-file "/tmp/ac-enterprise-${env_name}.json" \
            2>&1

        local RT_ARN MEM_ARN
        RT_ARN=$(python3 -c "
import json
data = json.load(open('/tmp/ac-enterprise-${env_name}.json'))
for name, outputs in data.items():
    if name.startswith('${STACK_NAME}-agent-') and outputs.get('RuntimeArn'):
        print(outputs['RuntimeArn']); break
" 2>/dev/null || echo "")
        MEM_ARN=$(python3 -c "
import json
data = json.load(open('/tmp/ac-enterprise-${env_name}.json'))
for name, outputs in data.items():
    if name.startswith('${STACK_NAME}-agent-') and outputs.get('MemoryArn'):
        print(outputs['MemoryArn']); break
" 2>/dev/null || echo "")

        # Deploy observability link (idempotent)
        if [[ -n "${SINK_ARN:-}" ]]; then
            local existing_link
            existing_link=$(aws oam list-links --region "$REGION" --query 'Items[0].Arn' --output text 2>/dev/null || echo "None")
            if [[ "$existing_link" == "None" || -z "$existing_link" ]]; then
                echo "  Deploying observability link..."
                aws cloudformation deploy \
                    --template-file "${TEMPLATE_DIR}/enterprise/workloads/workload-observability-link.yaml" \
                    --stack-name "${PROJECT}-observability-link" \
                    --region "$REGION" \
                    --no-fail-on-empty-changeset \
                    --parameter-overrides \
                        "ProjectName=${PROJECT}" \
                        "Environment=${env_name}" \
                        "ObservabilitySinkArn=${SINK_ARN}"
                echo "  Observability link ready."
            else
                echo "  Observability link already exists, skipping."
            fi
        else
            echo "  WARNING: No observability sink ARN — skipping OAM link."
        fi

        # Deploy Transaction Search
        local txn_sampling
        case "$env_name" in
            dev)     txn_sampling="100.0" ;;
            staging) txn_sampling="100.0" ;;
            prod)    txn_sampling="50.0" ;;
            *)       txn_sampling="100.0" ;;
        esac
        echo "  Deploying Transaction Search (${txn_sampling}% sampling)..."
        aws cloudformation deploy \
            --template-file "${TEMPLATE_DIR}/enterprise/workloads/workload-transaction-search.yaml" \
            --stack-name "${PROJECT}-transaction-search" \
            --region "$REGION" \
            --capabilities CAPABILITY_NAMED_IAM \
            --no-fail-on-empty-changeset \
            --parameter-overrides \
                "ProjectName=${PROJECT}" \
                "Environment=${env_name}" \
                "SamplingPercentage=${txn_sampling}"

        clear_role

        echo "  ${env_name} deploy complete."
        echo "    Runtime: ${RT_ARN}"
        echo "    Memory:  ${MEM_ARN}"

        # Store in management account SSM
        aws ssm put-parameter --name "/${PROJECT}/workloads/${env_name}/runtime-arn" --value "$RT_ARN" --type String --overwrite --region "$REGION" 2>/dev/null || true
        aws ssm put-parameter --name "/${PROJECT}/workloads/${env_name}/memory-arn" --value "$MEM_ARN" --type String --overwrite --region "$REGION" 2>/dev/null || true
    }

    echo "Phase 3: AgentCore workloads"
    deploy_workload "dev" "$DEV_ID"
    deploy_workload "staging" "$STAGING_ID"
    deploy_workload "prod" "$PROD_ID"

    clear_role

    # --- Phase 4: Update shared-tooling with Cognito values for pipeline ---
    echo ""
    echo "Phase 4: Update shared-tooling pipeline config"
    deploy_stackset "${PROJECT}-shared-tooling" "${TEMPLATE_DIR}/enterprise/platform/shared-tooling.yaml" "$ST_ID" \
        "$(ss_param ProjectName "$PROJECT")" "$(ss_param StackName "$STACK_NAME")" \
        "$(ss_param DevAccountId "$DEV_ID")" "$(ss_param StagingAccountId "${STAGING_ID}")" \
        "$(ss_param ProdAccountId "${PROD_ID}")" "$(ss_param ObservabilityAccountId "$OBS_ID")" \
        "$(ss_param CognitoUserPoolId "$COGNITO_POOL_ID")" "$(ss_param CognitoClientId "$COGNITO_CLIENT_ID")" \
        "$(ss_param CognitoUserPoolDomain "$COGNITO_DOMAIN")" \
        "$(ss_param DevMachineClientId "${DEV_MC_ID:-}")" \
        "$(ss_param StagingMachineClientId "${STAGING_MC_ID:-}")" \
        "$(ss_param ProdMachineClientId "${PROD_MC_ID:-}")" \
        "$(ss_param MachineClientDescribeRoleArn "${MACHINE_CLIENT_DESCRIBE_ROLE_ARN:-}")"
    echo "  Promotion pipeline ready."

    # --- Phase 5: Scaffold example team repo in CodeCommit ---
    echo ""
    echo "Phase 5: Scaffold example team repo in CodeCommit"

    if ! pip show git-remote-codecommit &>/dev/null; then
        echo "  Installing git-remote-codecommit..."
        pip install git-remote-codecommit --quiet
    fi

    assume_role "$ST_ID" "codecommit-push"

    local CC_TMP
    CC_TMP=$(mktemp -d)
    trap "rm -rf $CC_TMP" EXIT

    local EXAMPLE_AGENT="strands-single-agent"
    local CC_REPO="${PROJECT}-agents"
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

ENV UV_SYSTEM_PYTHON=1 \
    UV_COMPILE_BYTECODE=1 \
    DOCKER_CONTAINER=1 \
    OTEL_PYTHON_LOG_CORRELATION=true \
    PYTHONUNBUFFERED=1

# Copy shared libs and agent requirements
COPY shared/gateway/ gateway/
COPY agents/strands-single-agent/requirements.txt requirements.txt
RUN uv pip install --no-cache -r requirements.txt && \
    uv pip install --no-cache aws-opentelemetry-distro==0.12.2 requests>=2.31.0

# Create non-root user
RUN useradd -m -u 1000 bedrock_agentcore
USER bedrock_agentcore

EXPOSE 8080

# Copy agent code and shared utils
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
# Evaluation cases — pipeline runs these before promotion
# See: scripts/pipeline_eval.py for format details
cases:
  - name: "Basic greeting"
    prompt: "Hello, how are you? What can you help me with?"
    assertions:
      - "Agent responded politely"
      - "Agent described its capabilities or available tools"
    trajectory: []
EVALEOF
    fi

    rm -rf "$TEAM_DIR/shared"
    mkdir -p "$TEAM_DIR/shared"
    cp -r "${REPO_ROOT}/agentcore/patterns/utils" "$TEAM_DIR/shared/utils"
    [[ -d "${REPO_ROOT}/agentcore/gateway" ]] && cp -r "${REPO_ROOT}/agentcore/gateway" "$TEAM_DIR/shared/gateway"
    [[ -d "${REPO_ROOT}/agentcore/tools" ]] && cp -r "${REPO_ROOT}/agentcore/tools" "$TEAM_DIR/shared/tools"

    rm -rf "$TEAM_DIR/infra-cdk"
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

    cd "$REPO_ROOT"
    clear_role

    echo ""
    echo "  To scale to multiple domains, fork this repo per domain:"
    echo "    e.g. ${PROJECT}-supply-chain, ${PROJECT}-production"
    echo "  Each domain repo owns its own agents.yaml and deploys independently."

    cat > "${OUT_DIR}/enterprise-$(date -u +%Y-%m-%dT%H-%M-%S).json" <<EOF
{
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "mode": "enterprise",
  "prefix": "${PREFIX}",
  "accounts": {
    "management": "${MGMT_ID}",
    "security": "${SEC_ID}",
    "observability": "${OBS_ID}",
    "shared_tooling": "${ST_ID}",
    "dev": "${DEV_ID}",
    "staging": "${STAGING_ID}",
    "prod": "${PROD_ID}"
  },
  "auth_layer": {
    "account": "${SEC_ID}",
    "cognito_user_pool_id": "${COGNITO_POOL_ID}",
    "cognito_client_id": "${COGNITO_CLIENT_ID}",
    "cognito_domain": "${COGNITO_DOMAIN}"
  }
}
EOF

    # --- Phase 6: Verify Transaction Search is ACTIVE in each workload ---
    echo ""
    echo "Phase 6: Verify Transaction Search readiness"
    local env_name acct_id
    for env_name in dev staging prod; do
        case "$env_name" in
            dev)     acct_id="${DEV_ID}" ;;
            staging) acct_id="${STAGING_ID}" ;;
            prod)    acct_id="${PROD_ID}" ;;
        esac
        [[ -z "$acct_id" ]] && continue

        assume_role "$acct_id" "txn-search-check-${env_name}"
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
            echo "  ${env_name}: Transaction Search ACTIVE."
        else
            echo "  ${env_name}: WARN - Transaction Search still ${txn_state} after ~3 min."
            echo "           First pipeline eval run may see incomplete spans; re-run if so."
        fi
        clear_role
    done

    echo ""
    echo "  Enterprise deploy complete."
    echo "  Auth (security): ${SEC_ID}"
    echo "  Workloads: dev=${DEV_ID} staging=${STAGING_ID} prod=${PROD_ID}"
    echo "  Output: ${OUT_DIR}/enterprise-*.json"
    echo ""
}
