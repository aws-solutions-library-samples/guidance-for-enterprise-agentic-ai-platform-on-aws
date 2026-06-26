#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# =============================================================================
# Agentic AI Platform - Single-account destroy
# Sourced by scripts/destroy.sh. Expects lib/common.sh + lib/destroy-common.sh.
# =============================================================================

destroy_single() {
    # Match deploy-single.sh: platform prefix owns CFN-managed resources,
    # CDK prefix owns Gateway + per-agent stacks.
    local PLATFORM_STACK="agentic-ai-platform-single"
    local PLATFORM_PREFIX="agentic-ai-platform-single"
    local CDK_PREFIX="fastagent-single"

    local TARGET_ACCT
    TARGET_ACCT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "")
    if [[ -z "$TARGET_ACCT" ]]; then
        report_error "Could not determine current AWS account (check credentials)."
        return 1
    fi

    echo "Destroying single-account resources in ${TARGET_ACCT} (${REGION})..."

    # --- 1. CDK stacks (gateway + per-agent) --------------------------------
    # `cdk destroy --all` needs the same context that deploy used, otherwise
    # the app can't synth. Pull Cognito IDs from the platform stack if it
    # still exists; otherwise pass placeholders (CDK only needs the context
    # to synth — destroy itself doesn't reach into Cognito).
    local COGNITO_POOL="" COGNITO_CLIENT_ID="" COGNITO_DOMAIN="" MACHINE_CLIENT_ID=""
    if aws cloudformation describe-stacks --stack-name "$PLATFORM_STACK" --region "$REGION" &>/dev/null; then
        COGNITO_POOL=$(aws cloudformation describe-stacks --stack-name "$PLATFORM_STACK" --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue' --output text 2>/dev/null || echo "")
        COGNITO_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name "$PLATFORM_STACK" --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`CognitoClientId`].OutputValue' --output text 2>/dev/null || echo "")
        COGNITO_DOMAIN=$(aws cloudformation describe-stacks --stack-name "$PLATFORM_STACK" --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`CognitoDomain`].OutputValue' --output text 2>/dev/null || echo "")
        MACHINE_CLIENT_ID=$(aws cloudformation describe-stacks --stack-name "$PLATFORM_STACK" --region "$REGION" \
            --query 'Stacks[0].Outputs[?OutputKey==`MachineClientId`].OutputValue' --output text 2>/dev/null || echo "")
    fi
    : "${COGNITO_POOL:=placeholder}"
    : "${COGNITO_CLIENT_ID:=placeholder}"
    : "${COGNITO_DOMAIN:=placeholder}"
    : "${MACHINE_CLIENT_ID:=placeholder}"

    if [[ -d "${CDK_DIR}" ]]; then
        echo "  Running cdk destroy --all in ${CDK_DIR}..."
        (
            cd "$CDK_DIR"
            npm install --silent 2>/dev/null || true
            cdk destroy --all --force \
                --context stack_name="${CDK_PREFIX}" \
                --context project_name="${PROJECT}" \
                --context cognito_user_pool_id="${COGNITO_POOL}" \
                --context cognito_user_pool_client_id="${COGNITO_CLIENT_ID}" \
                --context cognito_user_pool_domain="${COGNITO_DOMAIN}" \
                --context machine_client_id="${MACHINE_CLIENT_ID}" 2>&1
        ) || report_error "cdk destroy --all failed (see output above)"
    else
        echo "  CDK dir ${CDK_DIR} missing, skipping cdk destroy."
    fi

    # --- 2 + 3. Empty S3 buckets, then delete platform stack ---------------
    if aws cloudformation describe-stacks --stack-name "$PLATFORM_STACK" --region "$REGION" &>/dev/null; then
        echo "  Emptying S3 buckets owned by ${PLATFORM_STACK}..."
        local buckets
        buckets=$(aws cloudformation list-stack-resources --stack-name "$PLATFORM_STACK" --region "$REGION" \
            --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" \
            --output text 2>/dev/null || echo "")
        for bucket in $buckets; do
            [[ -z "$bucket" || "$bucket" == "None" ]] && continue
            empty_bucket_fully "$bucket"
        done

        # ECR repos can't be deleted by CFN while they contain images.
        echo "  Emptying ECR repos owned by ${PLATFORM_STACK}..."
        local ecr_repos
        ecr_repos=$(aws cloudformation list-stack-resources --stack-name "$PLATFORM_STACK" --region "$REGION" \
            --query "StackResourceSummaries[?ResourceType=='AWS::ECR::Repository'].PhysicalResourceId" \
            --output text 2>/dev/null || echo "")
        for repo in $ecr_repos; do
            [[ -z "$repo" || "$repo" == "None" ]] && continue
            echo "    Purging images in ${repo}..."
            local image_ids
            image_ids=$(aws ecr list-images --repository-name "$repo" --region "$REGION" \
                --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')
            if [[ "$image_ids" != "[]" && -n "$image_ids" ]]; then
                aws ecr batch-delete-image --repository-name "$repo" --region "$REGION" \
                    --image-ids "$image_ids" >/dev/null 2>&1 \
                    || echo "      Warning: failed to delete some images in ${repo}"
            fi
        done

        # Pipeline eval secret + Cognito SSM params are created post-deploy
        # (not owned by the stack). Remove them so a re-deploy is clean.
        aws secretsmanager delete-secret --secret-id "/${PLATFORM_PREFIX}/pipeline_eval_credentials" \
            --force-delete-without-recovery --region "$REGION" &>/dev/null || true
        aws ssm delete-parameter --name "/${PLATFORM_PREFIX}/cognito-user-pool-id" --region "$REGION" &>/dev/null || true
        aws ssm delete-parameter --name "/${PLATFORM_PREFIX}/cognito-user-pool-client-id" --region "$REGION" &>/dev/null || true

        delete_stack "$PLATFORM_STACK"
    else
        echo "  Platform stack ${PLATFORM_STACK} not present, skipping."
    fi

    echo "  Single-account destroy done."
}
