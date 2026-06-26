#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# =============================================================================
# Agentic AI Platform - Destroy-specific helpers
# Sourced by scripts/destroy.sh after lib/common.sh.
# Provides: report_error, delete_stack, delete_stackset, destroy_cdk_stack,
#           destroy_oam_link
# =============================================================================

# Error collector — callers check ERRORS array at the end for summary.
ERRORS=()

report_error() {
    local msg="$1"
    echo "  ERROR: ${msg}"
    ERRORS+=("$msg")
}

delete_stack() {
    local name="$1"
    echo "  Deleting stack ${name}..."
    if ! aws cloudformation describe-stacks --stack-name "$name" --region "$REGION" &>/dev/null; then
        echo "  Stack ${name} does not exist, skipping."
        return 0
    fi
    if ! aws cloudformation delete-stack --stack-name "$name" --region "$REGION" 2>&1; then
        report_error "Failed to initiate delete for stack ${name}"
        return 1
    fi
    echo "  Waiting for stack ${name} to delete..."
    if ! aws cloudformation wait stack-delete-complete --stack-name "$name" --region "$REGION" 2>&1; then
        local reason
        reason=$(aws cloudformation describe-stack-events --stack-name "$name" --region "$REGION" \
            --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
            --output text 2>/dev/null | head -5)
        report_error "Stack ${name} delete failed: ${reason}"
        return 1
    fi
    echo "  Stack ${name} deleted."
}

delete_stackset() {
    local name="$1"
    echo "  Removing StackSet ${name}..."
    if ! aws cloudformation describe-stack-set --stack-set-name "$name" --region "$REGION" &>/dev/null; then
        echo "  StackSet ${name} does not exist, skipping."
        return 0
    fi
    # Delete all instances first
    local accounts
    accounts=$(aws cloudformation list-stack-instances --stack-set-name "$name" --region "$REGION" \
        --query 'Summaries[].Account' --output text 2>/dev/null || echo "")
    if [[ -n "$accounts" && "$accounts" != "None" ]]; then
        for acct in $accounts; do
            echo "    Looking up stack resources in ${acct} for ${name}..."
            local stack_id
            stack_id=$(aws cloudformation list-stack-instances --stack-set-name "$name" \
                --stack-instance-account "$acct" --stack-instance-region "$REGION" --region "$REGION" \
                --query 'Summaries[0].StackId' --output text 2>/dev/null || echo "")

            if [[ -n "$stack_id" && "$stack_id" != "None" ]]; then
                if assume_role "$acct" "cleanup-${name}"; then
                    # Empty S3 buckets (including all versions and delete markers)
                    local buckets
                    buckets=$(aws cloudformation list-stack-resources --stack-name "$stack_id" --region "$REGION" \
                        --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || echo "")
                    for bucket in $buckets; do
                        [[ -z "$bucket" || "$bucket" == "None" ]] && continue
                        echo "      Emptying S3 bucket ${bucket}..."
                        aws s3 rm "s3://${bucket}" --recursive --quiet 2>&1 || true
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
        print(f'      Deleted {len(batch)} {key.lower()}')
" 2>&1 || echo "      Warning: version cleanup may be incomplete for ${bucket}"
                    done

                    # Delete ECR images
                    local ecr_repos
                    ecr_repos=$(aws cloudformation list-stack-resources --stack-name "$stack_id" --region "$REGION" \
                        --query "StackResourceSummaries[?ResourceType=='AWS::ECR::Repository'].PhysicalResourceId" --output text 2>/dev/null || echo "")
                    for repo in $ecr_repos; do
                        [[ -z "$repo" || "$repo" == "None" ]] && continue
                        echo "      Deleting images in ECR repo ${repo}..."
                        local image_ids
                        image_ids=$(aws ecr list-images --repository-name "$repo" --region "$REGION" \
                            --query 'imageIds[*]' --output json 2>/dev/null || echo '[]')
                        if [[ "$image_ids" != "[]" ]]; then
                            aws ecr batch-delete-image --repository-name "$repo" --image-ids "$image_ids" --region "$REGION" 2>&1 || \
                                echo "      Warning: failed to delete some images in ${repo}"
                        fi
                    done

                    clear_role
                fi
            fi

            echo "    Removing instance in ${acct}..."
            local op
            op=$(aws cloudformation delete-stack-instances --stack-set-name "$name" \
                --accounts "$acct" --regions "$REGION" --no-retain-stacks --region "$REGION" \
                --query 'OperationId' --output text 2>&1) || {
                report_error "Failed to delete StackSet instance ${name} in ${acct}: ${op}"
                continue
            }
            while true; do
                local st
                st=$(aws cloudformation describe-stack-set-operation --stack-set-name "$name" \
                    --operation-id "$op" --region "$REGION" \
                    --query 'StackSetOperation.Status' --output text 2>/dev/null || echo "SUCCEEDED")
                case $st in
                    SUCCEEDED) echo "    Instance removed."; break ;;
                    FAILED|STOPPED)
                        local fail_reason
                        fail_reason=$(aws cloudformation list-stack-set-operation-results \
                            --stack-set-name "$name" --operation-id "$op" --region "$REGION" \
                            --query 'Summaries[?Status==`FAILED`].StatusReason' --output text 2>/dev/null || echo "unknown")
                        echo "    Instance delete failed: ${fail_reason}"
                        echo "    Fallback: detaching instance and deleting stack directly..."
                        local op2
                        op2=$(aws cloudformation delete-stack-instances --stack-set-name "$name" \
                            --accounts "$acct" --regions "$REGION" --retain-stacks --region "$REGION" \
                            --query 'OperationId' --output text 2>/dev/null || echo "")
                        if [[ -n "$op2" && "$op2" != "None" ]]; then
                            while true; do
                                local st2
                                st2=$(aws cloudformation describe-stack-set-operation --stack-set-name "$name" \
                                    --operation-id "$op2" --region "$REGION" \
                                    --query 'StackSetOperation.Status' --output text 2>/dev/null || echo "SUCCEEDED")
                                case $st2 in SUCCEEDED|FAILED|STOPPED) break ;; *) sleep 5 ;; esac
                            done
                        fi
                        if assume_role "$acct" "direct-delete-${name}"; then
                            local stacks
                            stacks=$(aws cloudformation list-stacks --region "$REGION" \
                                --query "StackSummaries[?contains(StackName,'StackSet-${name}') && StackStatus!='DELETE_COMPLETE'].StackName" \
                                --output text 2>/dev/null || echo "")
                            for s in $stacks; do
                                echo "    Deleting ${s} directly..."
                                aws cloudformation delete-stack --stack-name "$s" --region "$REGION" 2>&1 || true
                                aws cloudformation wait stack-delete-complete --stack-name "$s" --region "$REGION" 2>&1 || \
                                    report_error "Failed to delete stack ${s} in ${acct}"
                            done
                            clear_role
                        else
                            report_error "Could not assume role to delete stack directly in ${acct}"
                        fi
                        break ;;
                    *) sleep 10 ;;
                esac
            done
        done
    fi
    sleep 5
    if ! aws cloudformation delete-stack-set --stack-set-name "$name" --region "$REGION" 2>&1; then
        report_error "Failed to delete StackSet ${name}"
    else
        echo "  StackSet ${name} deleted."
    fi
}

destroy_cdk_stack() {
    local acct="$1" label="$2"
    [[ -z "$acct" ]] && return 0
    echo ""
    echo "  --- Destroying CDK stack: ${label} (${acct}) ---"
    if ! assume_role "$acct" "destroy-${label}"; then
        return 1
    fi

    local stack_name="fastagent-enterprise"
    if ! aws cloudformation describe-stacks --stack-name "$stack_name" --region "$REGION" &>/dev/null; then
        echo "  Stack ${stack_name} does not exist in ${label}, skipping."
        clear_role
        return 0
    fi

    # Empty S3 buckets first
    echo "  Emptying S3 buckets..."
    local buckets
    buckets=$(aws cloudformation list-stack-resources --stack-name "$stack_name" --region "$REGION" \
        --query "StackResourceSummaries[?ResourceType=='AWS::S3::Bucket'].PhysicalResourceId" --output text 2>/dev/null || echo "")
    for bucket in $buckets; do
        [[ -z "$bucket" || "$bucket" == "None" ]] && continue
        echo "    Emptying ${bucket}..."
        aws s3 rm "s3://${bucket}" --recursive --quiet 2>/dev/null || true
        aws s3api list-object-versions --bucket "$bucket" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null | \
            python3 -c "
import sys,json,boto3
data = json.load(sys.stdin)
if data.get('Objects'):
    boto3.client('s3').delete_objects(Bucket='${bucket}', Delete=data)
" 2>/dev/null || true
        aws s3api list-object-versions --bucket "$bucket" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null | \
            python3 -c "
import sys,json,boto3
data = json.load(sys.stdin)
if data.get('Objects'):
    boto3.client('s3').delete_objects(Bucket='${bucket}', Delete=data)
" 2>/dev/null || true
    done

    echo "  Deleting CloudFormation stack ${stack_name}..."
    if ! aws cloudformation delete-stack --stack-name "$stack_name" --region "$REGION" 2>&1; then
        report_error "Failed to initiate delete for ${stack_name} in ${label} (${acct})"
        clear_role
        return 1
    fi

    echo "  Waiting for stack delete (this may take a few minutes)..."
    if ! aws cloudformation wait stack-delete-complete --stack-name "$stack_name" --region "$REGION" 2>&1; then
        local reason
        reason=$(aws cloudformation describe-stack-events --stack-name "$stack_name" --region "$REGION" \
            --query 'StackEvents[?ResourceStatus==`DELETE_FAILED`].[LogicalResourceId,ResourceStatusReason]' \
            --output text 2>/dev/null | head -5)
        report_error "Stack ${stack_name} delete failed in ${label} (${acct}): ${reason}"
        clear_role
        return 1
    fi
    echo "  CDK stack destroyed in ${label}."
    clear_role
}

destroy_oam_link() {
    local acct="$1" label="$2"
    [[ -z "$acct" ]] && return 0
    if ! assume_role "$acct" "destroy-oam-${label}"; then
        return 1
    fi
    delete_stack "${PROJECT}-observability-link"
    clear_role
}

# Fully empty an S3 bucket (current objects + all versions + delete markers),
# paginating until list-object-versions returns nothing. Pure bash + awscli,
# no python/boto3 dependency. Safe to call on a missing bucket (no-op).
empty_bucket_fully() {
    local bucket="$1"
    [[ -z "$bucket" || "$bucket" == "None" ]] && return 0

    if ! aws s3api head-bucket --bucket "$bucket" &>/dev/null; then
        echo "    Bucket ${bucket} not accessible/missing, skipping."
        return 0
    fi

    echo "    Emptying ${bucket}..."

    # Fast path for non-versioned content first.
    aws s3 rm "s3://${bucket}" --recursive --quiet 2>/dev/null || true

    # Versioned deletes — loop until list returns empty for BOTH Versions and
    # DeleteMarkers. Page size 1000 matches the delete-objects API limit.
    local total=0 page=0
    while :; do
        local payload
        payload=$(aws s3api list-object-versions --bucket "$bucket" --max-items 1000 \
            --query '{Objects: [Versions, DeleteMarkers][].{Key:Key, VersionId:VersionId} | [?Key!=null]}' \
            --output json 2>/dev/null || echo '{"Objects":[]}')

        # Break when there's nothing left to delete.
        local count
        count=$(echo "$payload" | awk '/"Key"/{c++} END{print c+0}')
        (( count == 0 )) && break

        if ! aws s3api delete-objects --bucket "$bucket" --delete "$payload" \
                --output text >/dev/null 2>&1; then
            report_error "Failed to delete a batch of objects in ${bucket}"
            return 1
        fi
        total=$((total + count))
        page=$((page + 1))
        echo "      Purged ${count} versioned entries (page ${page}, total ${total})"

        # Guard against pathological loops (shouldn't hit in practice).
        (( page > 1000 )) && {
            report_error "Gave up emptying ${bucket} after 1000 pages"
            return 1
        }
    done

    # Abort incomplete multipart uploads — they also block bucket delete.
    local mpus
    mpus=$(aws s3api list-multipart-uploads --bucket "$bucket" \
        --query 'Uploads[].[Key,UploadId]' --output text 2>/dev/null || echo "")
    if [[ -n "$mpus" && "$mpus" != "None" ]]; then
        while read -r key upload_id; do
            [[ -z "$key" ]] && continue
            aws s3api abort-multipart-upload --bucket "$bucket" \
                --key "$key" --upload-id "$upload_id" >/dev/null 2>&1 || true
        done <<< "$mpus"
        echo "      Aborted in-flight multipart uploads"
    fi
}
