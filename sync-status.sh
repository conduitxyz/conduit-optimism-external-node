#!/usr/bin/env bash
#
# Monitor op-node sync status
#

set -euo pipefail

# Load environment variables
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    set -a
    source "$SCRIPT_DIR/.env"
    set +a
fi

OP_NODE_RPC="${OP_NODE_RPC:-http://localhost:7545}"
L2_REMOTE_RPC="${L2_REMOTE_RPC:-}"

while true; do
    clear
    echo "=== Sync Status - $(date) ==="
    echo ""

    RESULT=$(curl -s -X POST "$OP_NODE_RPC" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}')

    # Extract values
    HEAD_L1=$(echo "$RESULT" | jq -r '.result.head_l1.number // 0')
    SAFE_L1=$(echo "$RESULT" | jq -r '.result.safe_l1.number // 0')
    FINALIZED_L1=$(echo "$RESULT" | jq -r '.result.finalized_l1.number // 0')
    UNSAFE_L2=$(echo "$RESULT" | jq -r '.result.unsafe_l2.number // 0')
    SAFE_L2=$(echo "$RESULT" | jq -r '.result.safe_l2.number // 0')
    FINALIZED_L2=$(echo "$RESULT" | jq -r '.result.finalized_l2.number // 0')

    # Get latest block from remote L2 RPC if configured
    if [[ -n "$L2_REMOTE_RPC" ]]; then
        LATEST_L2_REMOTE=$(curl -s -X POST "$L2_REMOTE_RPC" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
            jq -r '.result // "0x0"' | xargs printf "%d" 2>/dev/null || echo "N/A")
    else
        LATEST_L2_REMOTE="N/A"
    fi

    # L1 Table
    echo "┌─────────────────────────────────┐"
    echo "│           L1 Status             │"
    echo "├─────────────────┬───────────────┤"
    printf "│ %-15s │ %13s │\n" "Head" "$HEAD_L1"
    printf "│ %-15s │ %13s │\n" "Safe" "$SAFE_L1"
    printf "│ %-15s │ %13s │\n" "Finalized" "$FINALIZED_L1"
    echo "└─────────────────┴───────────────┘"

    echo ""

    # L2 Table
    echo "┌─────────────────────────────────┐"
    echo "│           L2 Status             │"
    echo "├─────────────────┬───────────────┤"
    printf "│ %-15s │ %13s │\n" "Unsafe" "$UNSAFE_L2"
    printf "│ %-15s │ %13s │\n" "Safe" "$SAFE_L2"
    printf "│ %-15s │ %13s │\n" "Finalized" "$FINALIZED_L2"
    printf "│ %-15s │ %13s │\n" "Remote Latest" "$LATEST_L2_REMOTE"
    echo "└─────────────────┴───────────────┘"

    echo ""
    echo "Refreshing in 10s... (Ctrl+C to exit)"
    sleep 1
done
