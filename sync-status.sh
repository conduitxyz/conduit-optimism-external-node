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
L2_REMOTE_RPC="${L2_REMOTE_RPC:-${OP_GETH_SEQUENCER_HTTP:-}}"

while true; do
    clear
    echo "=== Sync Status - $(date) ==="
    echo ""

    RESULT=$(curl -s --max-time 5 -X POST "$OP_NODE_RPC" \
        -H "Content-Type: application/json" \
        -d '{"jsonrpc":"2.0","method":"optimism_syncStatus","params":[],"id":1}' 2>/dev/null) || RESULT=""

    if [[ -z "$RESULT" ]] || ! echo "$RESULT" | jq -e '.result' >/dev/null 2>&1; then
        echo "ERROR: Cannot reach op-node at $OP_NODE_RPC"
        echo "  - Is the node running? Try: docker compose ps"
        echo "  - Check logs: docker compose logs node --tail 50"
        echo ""
        echo "Retrying in 10s... (Ctrl+C to exit)"
        sleep 10
        continue
    fi

    # Extract values
    HEAD_L1=$(echo "$RESULT" | jq -r '.result.head_l1.number // 0')
    SAFE_L1=$(echo "$RESULT" | jq -r '.result.safe_l1.number // 0')
    FINALIZED_L1=$(echo "$RESULT" | jq -r '.result.finalized_l1.number // 0')
    UNSAFE_L2=$(echo "$RESULT" | jq -r '.result.unsafe_l2.number // 0')
    SAFE_L2=$(echo "$RESULT" | jq -r '.result.safe_l2.number // 0')
    FINALIZED_L2=$(echo "$RESULT" | jq -r '.result.finalized_l2.number // 0')

    # Get latest block from remote L2 RPC
    LATEST_L2_REMOTE="N/A"
    if [[ -n "$L2_REMOTE_RPC" ]]; then
        LATEST_L2_REMOTE=$(curl -s --max-time 5 -X POST "$L2_REMOTE_RPC" \
            -H "Content-Type: application/json" \
            -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | \
            jq -r '.result // "0x0"' | xargs printf "%d" 2>/dev/null || echo "N/A")
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

    # Show sync progress if remote is available
    if [[ "$LATEST_L2_REMOTE" != "N/A" ]] && [[ "$LATEST_L2_REMOTE" -gt 0 ]] 2>/dev/null; then
        BEHIND=$((LATEST_L2_REMOTE - UNSAFE_L2))
        if [[ "$LATEST_L2_REMOTE" -gt 0 ]]; then
            PCT=$(echo "scale=2; $UNSAFE_L2 * 100 / $LATEST_L2_REMOTE" | bc 2>/dev/null || echo "N/A")
        else
            PCT="N/A"
        fi
        echo "┌─────────────────────────────────┐"
        echo "│         Sync Progress           │"
        echo "├─────────────────┬───────────────┤"
        printf "│ %-15s │ %12s%% │\n" "Progress" "$PCT"
        printf "│ %-15s │ %13s │\n" "Behind by" "$BEHIND blocks"
        echo "└─────────────────┴───────────────┘"
    fi

    echo ""
    echo "Refreshing in 10s... (Ctrl+C to exit)"
    sleep 10
done
