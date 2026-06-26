#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
# =============================================================================
# Agentic AI Platform - Shared library (sourced by deploy.sh / destroy.sh)
#
# Provides config load, CloudFormation StackSet helpers, and cross-account
# role assumption utilities. This file is NOT executable — it is sourced.
# Callers must `set -euo pipefail` themselves.
#
# Exposed globals:
#   PROJECT, REGION, CONFIG_FILE, REPO_ROOT, SCRIPT_DIR, TEMPLATE_DIR,
#   CDK_DIR, OUT_DIR
#
# Exposed functions:
#   yaml_account_id <slug>          -- read enterpriseAccounts.<slug>AccountId
#   yaml_field <section> <field>    -- read a scalar under a top-level section
#   ss_param <key> <value>          -- format a CFN StackSet parameter
#   assume_role <acct> <session>    -- assume OrganizationAccountAccessRole
#   clear_role                      -- drop assumed-role env vars
#   deploy_stackset <name> <tpl> <acct> [params...]
# =============================================================================

# Resolve repo/script paths. SCRIPT_DIR is expected to already point at the
# scripts/ directory when this file is sourced from deploy.sh / destroy.sh.
: "${SCRIPT_DIR:?SCRIPT_DIR must be set before sourcing lib/common.sh}"
REPO_ROOT="${REPO_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
CONFIG_FILE="${CONFIG_FILE:-${REPO_ROOT}/infra/config.yaml}"
TEMPLATE_DIR="${TEMPLATE_DIR:-${REPO_ROOT}/infra/cloudformation}"
CDK_DIR="${CDK_DIR:-${REPO_ROOT}/agentcore/infra-cdk}"
OUT_DIR="${OUT_DIR:-${SCRIPT_DIR}/out}"
mkdir -p "$OUT_DIR"

# Load projectName + region from infra/config.yaml. Callers that need these
# to be required (e.g. deploy) should validate afterwards.
PROJECT="${PROJECT:-}"
REGION="${REGION:-}"
if [[ -f "$CONFIG_FILE" ]]; then
    _p=$(grep '^projectName:' "$CONFIG_FILE" | awk '{print $2}' || true)
    _r=$(grep '^region:' "$CONFIG_FILE" | awk '{print $2}' || true)
    [[ -n "${_p:-}" && -z "$PROJECT" ]] && PROJECT="$_p"
    [[ -n "${_r:-}" && -z "$REGION"  ]] && REGION="$_r"
fi

# Read a <name>AccountId field from enterpriseAccounts in config.yaml.
# Argument is the slug form (security, observability, shared-tooling, dev,
# staging, prod); we map it to the camelCase key under enterpriseAccounts.
yaml_account_id() {
    local sec="$1"
    python3 - "$CONFIG_FILE" "$sec" <<'PY' 2>/dev/null || echo ""
import sys, yaml
try:
    cfg = yaml.safe_load(open(sys.argv[1])) or {}
    accounts = cfg.get("enterpriseAccounts") or {}
    slug_to_key = {
        "security":       "securityAccountId",
        "observability":  "observabilityAccountId",
        "shared-tooling": "sharedToolingAccountId",
        "dev":            "devAccountId",
        "staging":        "stagingAccountId",
        "prod":           "prodAccountId",
    }
    key = slug_to_key.get(sys.argv[2])
    print(str(accounts.get(key) or "").strip() if key else "")
except Exception:
    print("")
PY
}

# Read a scalar field under a nested section using awk. Used by destroy.sh
# for its lightweight config probes.
yaml_field() {
    local sec="$1" fld="$2"
    awk -v s="$sec" -v f="$fld" '
        $0 ~ "^  "s":" { found=1; next }
        found && /^  [a-z]/ { found=0 }
        found && $0 ~ f":" { gsub(/.*: */, ""); gsub(/^"/, ""); gsub(/"$/, ""); print; exit }
    ' "$CONFIG_FILE"
}

ss_param() { echo "ParameterKey=$1,ParameterValue=$2"; }

assume_role() {
    local acct="$1" sess="$2"
    echo "  Assuming role in ${acct}..."
    local c
    if ! c=$(aws sts assume-role \
            --role-arn "arn:aws:iam::${acct}:role/OrganizationAccountAccessRole" \
            --role-session-name "$sess" --duration-seconds 3600 --output json 2>&1); then
        # Destroy paths track errors via report_error; deploy just fails hard.
        if declare -F report_error >/dev/null 2>&1; then
            report_error "Failed to assume role in ${acct}: ${c}"
            return 1
        fi
        echo "ERROR: Failed to assume role in ${acct}: ${c}" >&2
        return 1
    fi
    export AWS_ACCESS_KEY_ID=$(echo "$c" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['AccessKeyId'])")
    export AWS_SECRET_ACCESS_KEY=$(echo "$c" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SecretAccessKey'])")
    export AWS_SESSION_TOKEN=$(echo "$c" | python3 -c "import sys,json; print(json.load(sys.stdin)['Credentials']['SessionToken'])")
    export CDK_DEFAULT_ACCOUNT="$acct" CDK_DEFAULT_REGION="$REGION"
}

clear_role() { unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN CDK_DEFAULT_ACCOUNT 2>/dev/null || true; }

deploy_stackset() {
    local name="$1" template="$2" acct="$3"; shift 3; local params=("$@")
    echo "==> StackSet ${name} → ${acct}..."
    local exec_role="OrganizationAccountAccessRole"
    if aws cloudformation describe-stack-set --stack-set-name "$name" --region "$REGION" &>/dev/null; then
        aws cloudformation update-stack-set --stack-set-name "$name" --template-body "file://${template}" \
            --capabilities CAPABILITY_NAMED_IAM --execution-role-name "$exec_role" --parameters "${params[@]}" --region "$REGION" 2>/dev/null || true
    else
        aws cloudformation create-stack-set --stack-set-name "$name" --template-body "file://${template}" \
            --capabilities CAPABILITY_NAMED_IAM --execution-role-name "$exec_role" --parameters "${params[@]}" --region "$REGION"
    fi
    local existing; existing=$(aws cloudformation list-stack-instances --stack-set-name "$name" --stack-instance-account "$acct" --stack-instance-region "$REGION" --region "$REGION" --query 'Summaries[0].Status' --output text 2>/dev/null || echo "NONE")
    if [[ "$existing" == "NONE" || "$existing" == "None" ]]; then
        local op; op=$(aws cloudformation create-stack-instances --stack-set-name "$name" --accounts "$acct" --regions "$REGION" --operation-preferences "MaxConcurrentCount=1,FailureToleranceCount=0" --region "$REGION" --query 'OperationId' --output text)
        echo "    Creating instance, waiting..."
        while true; do
            local st; st=$(aws cloudformation describe-stack-set-operation --stack-set-name "$name" --operation-id "$op" --region "$REGION" --query 'StackSetOperation.Status' --output text)
            case $st in SUCCEEDED) echo "    Done."; break ;; FAILED|STOPPED)
                local fail_reason
                fail_reason=$(aws cloudformation list-stack-set-operation-results \
                    --stack-set-name "$name" --operation-id "$op" --region "$REGION" \
                    --query 'Summaries[?Status==`FAILED`].StatusReason' --output text 2>/dev/null || echo "unknown")
                echo "    ${st}: ${fail_reason}"
                exit 1 ;; *) sleep 10 ;; esac
        done
    elif [[ "$existing" == "OUTDATED" ]]; then
        echo "    Instance outdated, updating..."
        local op; op=$(aws cloudformation update-stack-instances --stack-set-name "$name" --accounts "$acct" --regions "$REGION" --operation-preferences "MaxConcurrentCount=1,FailureToleranceCount=0" --region "$REGION" --query 'OperationId' --output text 2>/dev/null || echo "")
        if [[ -n "$op" && "$op" != "None" ]]; then
            while true; do
                local st; st=$(aws cloudformation describe-stack-set-operation --stack-set-name "$name" --operation-id "$op" --region "$REGION" --query 'StackSetOperation.Status' --output text)
                case $st in SUCCEEDED) echo "    Done."; break ;; FAILED|STOPPED) echo "    ${st} (non-fatal, continuing)"; break ;; *) sleep 10 ;; esac
            done
        else
            echo "    No updates needed."
        fi
    else echo "    Instance exists (${existing})"; fi
    echo ""
}
