#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
set -euo pipefail

# =============================================================================
# Agentic AI Platform - Deploy
#
# Usage:
#   ./scripts/deploy.sh single       # single account (default)
#   ./scripts/deploy.sh enterprise   # multi-account
# =============================================================================

MODE="${1:-single}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"

if [[ -z "$PROJECT" ]]; then
    echo "ERROR: No project name configured. Set 'projectName:' in infra/config.yaml"
    exit 1
fi
if [[ -z "$REGION" ]]; then
    echo "ERROR: No region configured. Set 'region:' in infra/config.yaml"
    exit 1
fi

case $MODE in
    single)
        source "${SCRIPT_DIR}/lib/deploy-single.sh"
        deploy_single
        ;;
    enterprise)
        source "${SCRIPT_DIR}/lib/deploy-enterprise.sh"
        deploy_enterprise
        ;;
    *)
        echo "Unknown mode: ${MODE}. Use: ./scripts/deploy.sh [single|enterprise]"
        exit 1
        ;;
esac

echo "============================================================"
echo "  Deploy complete (${MODE})."
echo "============================================================"
