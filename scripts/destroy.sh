#!/usr/bin/env bash
# Copyright Amazon.com, Inc. or its affiliates. All Rights Reserved.
# SPDX-License-Identifier: MIT-0
set -euo pipefail

# =============================================================================
# Agentic AI Platform - Destroy
#
# Usage:
#   ./scripts/destroy.sh single
#   ./scripts/destroy.sh enterprise
#
# =============================================================================

MODE="${1:-}"
[[ -z "$MODE" ]] && echo "Usage: $0 <single|enterprise>" && exit 1
shift || true

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/destroy-common.sh"

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo "unknown")

echo "============================================================"
echo "  Agentic AI Platform - Destroy"
echo "  Mode:    ${MODE}"
echo "  Region:  ${REGION}"
echo "  Account: ${ACCOUNT_ID}"
echo "============================================================"
echo ""

case $MODE in
    single)
        source "${SCRIPT_DIR}/lib/destroy-single.sh"
        destroy_single
        ;;
    enterprise)
        source "${SCRIPT_DIR}/lib/destroy-enterprise.sh"
        destroy_enterprise
        ;;
    *)
        echo "Unknown mode: ${MODE}."
        exit 1
        ;;
esac

echo ""
echo "============================================================"
if [[ ${#ERRORS[@]} -eq 0 ]]; then
    echo "  Destroy complete (${MODE}). No errors."
else
    echo "  Destroy complete (${MODE}) with ${#ERRORS[@]} error(s):"
    echo ""
    for err in "${ERRORS[@]}"; do
        echo "  ✗ ${err}"
    done
    echo ""
    echo "  Review errors above and retry or clean up manually."
fi
echo "============================================================"

[[ ${#ERRORS[@]} -eq 0 ]] && exit 0 || exit 1
