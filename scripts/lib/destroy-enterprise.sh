#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# =============================================================================
# Agentic AI Platform - Enterprise (multi-account) destroy
# Sourced by scripts/destroy.sh. Expects lib/common.sh + lib/destroy-common.sh.
# =============================================================================

destroy_enterprise() {
    echo "============================================================"
    echo "  Destroying Enterprise Resources"
    echo "============================================================"
    echo ""

    local SEC_ID OBS_ID ST_ID DEV_ID STAGING_ID PROD_ID
    SEC_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/security" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    OBS_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/observability" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    ST_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/shared-tooling" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    DEV_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/dev" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    STAGING_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/staging" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")
    PROD_ID=$(aws ssm get-parameter --name "/${PROJECT}/accounts/prod" --region "$REGION" --query 'Parameter.Value' --output text 2>/dev/null || echo "")

    echo "  Security:       ${SEC_ID:-none}"
    echo "  Observability:  ${OBS_ID:-none}"
    echo "  Shared Tooling: ${ST_ID:-none}"
    echo "  Dev:            ${DEV_ID:-none}"
    echo "  Staging:        ${STAGING_ID:-none}"
    echo "  Prod:           ${PROD_ID:-none}"
    echo ""

    # --- Phase 1: Destroy CDK stacks ---
    echo "Phase 1: Destroy AgentCore CDK stacks"
    destroy_cdk_stack "$DEV_ID" "dev"
    destroy_cdk_stack "${STAGING_ID:-}" "staging"
    destroy_cdk_stack "${PROD_ID:-}" "prod"
    destroy_cdk_stack "$SEC_ID" "security-auth"
    echo ""

    # --- Phase 2: Destroy OAM links ---
    echo "Phase 2: Destroy observability links"
    destroy_oam_link "$DEV_ID" "dev"
    destroy_oam_link "${STAGING_ID:-}" "staging"
    destroy_oam_link "${PROD_ID:-}" "prod"
    echo ""

    # --- Phase 2b: Destroy Transaction Search stack (dev only) ---
    echo "Phase 2b: Destroy Transaction Search stack"
    if [[ -n "$DEV_ID" ]]; then
        if assume_role "$DEV_ID" "destroy-txn-search"; then
            delete_stack "${PROJECT}-transaction-search"
            clear_role
        fi
    fi
    echo ""

    # --- Phase 3: Destroy StackSets ---
    echo "Phase 3: Destroy StackSets"
    clear_role
    delete_stackset "${PROJECT}-dev"
    delete_stackset "${PROJECT}-shared-tooling"
    delete_stackset "${PROJECT}-observability"
    delete_stackset "${PROJECT}-security"
    echo ""

    # --- Phase 3b: Clean up orphaned stacks ---
    echo "Phase 3b: Clean up orphaned stacks"
    cleanup_orphaned_stacks() {
        local acct="$1" label="$2"
        [[ -z "$acct" ]] && return 0
        if ! assume_role "$acct" "cleanup-orphan-${label}"; then
            return 1
        fi
        local stacks
        stacks=$(aws cloudformation list-stacks --region "$REGION" \
            --query "StackSummaries[?(contains(StackName,'StackSet-${PROJECT}') || contains(StackName,'${PROJECT}')) && (StackStatus=='DELETE_FAILED' || StackStatus=='CREATE_COMPLETE' || StackStatus=='UPDATE_COMPLETE')].StackName" \
            --output text 2>/dev/null || echo "")
        if [[ -z "$stacks" || "$stacks" == "None" ]]; then
            echo "  No orphaned stacks in ${label}."
            clear_role
            return 0
        fi
        for s in $stacks; do
            [[ "$s" == "CDKToolkit" ]] && continue
            echo "  Deleting orphaned stack ${s} in ${label} (${acct})..."
            local buckets
            buckets=$(aws cloudformation list-stack-resources --stack-name "$s" --region "$REGION" \
                --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || echo "")
            for bucket in $buckets; do
                [[ -z "$bucket" || "$bucket" == "None" ]] && continue
                echo "    Emptying ${bucket}..."
                aws s3 rm "s3://${bucket}" --recursive --quiet 2>/dev/null || true
                local versions
                versions=$(aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null || echo '{}')
                echo "$versions" | python3 -c "
import sys, json, os, boto3
data = json.load(sys.stdin)
s3 = boto3.client('s3', region_name=os.environ.get('AWS_DEFAULT_REGION', '${REGION}'))
for key in ('Versions', 'DeleteMarkers'):
    objects = data.get(key, [])
    if objects:
        batch = [{'Key': o['Key'], 'VersionId': o['VersionId']} for o in objects]
        for i in range(0, len(batch), 1000):
            s3.delete_objects(Bucket='${bucket}', Delete={'Objects': batch[i:i+1000]})
" 2>/dev/null || true
            done
            local ecr_repos
            ecr_repos=$(aws cloudformation list-stack-resources --stack-name "$s" --region "$REGION" \
                --query "StackResourceSummaries[?ResourceType=='AWS::ECR::Repository'].PhysicalResourceId" --output text 2>/dev/null || echo "")
            for repo in $ecr_repos; do
                [[ -z "$repo" || "$repo" == "None" ]] && continue
                echo "    Deleting images in ${repo}..."
                local image_ids
                image_ids=$(aws ecr list-images --repository-name "$repo" --region "$REGION" \
                    --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')
                if [[ "$image_ids" != "[]" ]]; then
                    aws ecr batch-delete-image --repository-name "$repo" --image-ids "$image_ids" --region "$REGION" 2>&1 || true
                fi
            done
            aws cloudformation delete-stack --stack-name "$s" --region "$REGION" 2>&1 || true
            echo "    Waiting..."
            if ! aws cloudformation wait stack-delete-complete --stack-name "$s" --region "$REGION" 2>&1; then
                report_error "Failed to delete orphaned stack ${s} in ${label} (${acct})"
            else
                echo "    Deleted ${s}."
            fi
        done
        clear_role
    }
    cleanup_orphaned_stacks "$SEC_ID" "security"
    cleanup_orphaned_stacks "$OBS_ID" "observability"
    cleanup_orphaned_stacks "$ST_ID" "shared-tooling"
    cleanup_orphaned_stacks "$DEV_ID" "dev"
    cleanup_orphaned_stacks "${STAGING_ID:-}" "staging"
    cleanup_orphaned_stacks "${PROD_ID:-}" "prod"
    echo ""

    # --- Phase 4: Destroy management stack ---
    echo "Phase 4: Destroy management stack"
    clear_role
    local mgmt_buckets
    mgmt_buckets=$(aws cloudformation list-stack-resources --stack-name "${PROJECT}-management" --region "$REGION" \
        --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || echo "")
    for bucket in $mgmt_buckets; do
        [[ -z "$bucket" || "$bucket" == "None" ]] && continue
        echo "  Emptying ${bucket}..."
        aws s3 rm "s3://${bucket}" --recursive --quiet 2>/dev/null || true
        local versions
        versions=$(aws s3api list-object-versions --bucket "$bucket" --output json 2>/dev/null || echo '{}')
        echo "$versions" | python3 -c "
import sys, json, os, boto3
data = json.load(sys.stdin)
s3 = boto3.client('s3', region_name=os.environ.get('AWS_DEFAULT_REGION', '${REGION}'))
for key in ('Versions', 'DeleteMarkers'):
    objects = data.get(key, [])
    if objects:
        batch = [{'Key': o['Key'], 'VersionId': o['VersionId']} for o in objects]
        for i in range(0, len(batch), 1000):
            s3.delete_objects(Bucket='${bucket}', Delete={'Objects': batch[i:i+1000]})
        print(f'  Deleted {len(batch)} {key.lower()}')
" 2>/dev/null || true
    done
    delete_stack "${PROJECT}-management"
    echo ""

    # --- Phase 5: Clean up SSM parameters ---
    echo "Phase 5: Clean up SSM parameters"
    for param in \
        "/${PROJECT}/accounts/security" \
        "/${PROJECT}/accounts/observability" \
        "/${PROJECT}/accounts/shared-tooling" \
        "/${PROJECT}/accounts/dev" \
        "/${PROJECT}/accounts/staging" \
        "/${PROJECT}/accounts/prod" \
        "/${PROJECT}/agentcore/cognito-user-pool-id" \
        "/${PROJECT}/agentcore/cognito-client-id" \
        "/${PROJECT}/agentcore/auth-account-id" \
        "/${PROJECT}/observability/sink-arn" \
        "/${PROJECT}/workloads/dev/runtime-arn" \
        "/${PROJECT}/workloads/dev/memory-arn" \
        "/${PROJECT}/workloads/staging/runtime-arn" \
        "/${PROJECT}/workloads/staging/memory-arn" \
        "/${PROJECT}/workloads/prod/runtime-arn" \
        "/${PROJECT}/workloads/prod/memory-arn"; do
        aws ssm delete-parameter --name "$param" --region "$REGION" 2>/dev/null || true
    done
    echo "  SSM parameters cleaned up."
    echo ""
}
