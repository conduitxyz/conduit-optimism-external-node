#!/usr/bin/env bash
#
# Download Conduit network configs and update .env
#

set -euo pipefail

CONDUIT_API_URL="https://api.conduit.xyz"
BOOTNODES_API_PATH="/public/network/bootnodes/"
STATICPEERS_API_PATH="/public/network/staticPeers/"
ROLLUP_API_PATH="/file/v1/optimism/rollup/"
GENESIS_API_PATH="/file/v1/optimism/genesis/"
FORK_TIMESTAMPS_API_PATH="/file/v1/optimism/forkTimestamps/"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${SCRIPT_DIR}/config"
ENV_FILE="${SCRIPT_DIR}/.env"

usage() {
    echo "Use 'make setup NETWORK=<slug>' instead of calling this script directly."
    echo "For Celestia DA: 'make setup NETWORK=<slug> ALTDA=celestia'"
    echo "For EigenDA: 'make setup NETWORK=<slug> ALTDA=eigenda'"
    exit 1
}

# Update or append a variable in .env
update_env() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "$ENV_FILE" 2>/dev/null; then
        # Update existing variable
        sed -i.bak "s|^${key}=.*|${key}=${value}|" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    else
        # Append new variable
        echo "${key}=${value}" >> "$ENV_FILE"
    fi
}

get_env() {
    local key="$1"

    if [[ -f "$ENV_FILE" ]]; then
        awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); exit }' "$ENV_FILE"
    fi
}

ALTDA_TYPE=""
SLUG=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --altda=*)
            ALTDA_TYPE="${1#*=}"
            shift
            ;;
        -*)
            echo "Unknown option: $1"
            usage
            ;;
        *)
            SLUG="$1"
            shift
            ;;
    esac
done

if [[ -z "$SLUG" ]]; then
    usage
fi

# Create config directory
mkdir -p "${CONFIG_DIR}"

echo "Downloading rollup.json..."
if ! curl -sf "${CONDUIT_API_URL}${ROLLUP_API_PATH}${SLUG}" -o "${CONFIG_DIR}/rollup.json"; then
    echo "Failed to download rollup.json"
    echo "Do you have the right network slug?"
    exit 1
fi

# Remove DA-related fields from root if present (breaks node)
echo "Removing DA-related fields from root if present..."
jq 'del(.da_challenge_contract_address, .da_challenge_address, .da_challenge_window, .da_resolve_window, .use_plasma)' \
    "${CONFIG_DIR}/rollup.json" > "${CONFIG_DIR}/rollup.json.tmp" && \
    mv "${CONFIG_DIR}/rollup.json.tmp" "${CONFIG_DIR}/rollup.json"

echo "Adding chain_op_config to rollup.json..."
jq '. + {"chain_op_config": {"eip1559Elasticity": 6, "eip1559Denominator": 50, "eip1559DenominatorCanyon": 250}}' \
    "${CONFIG_DIR}/rollup.json" > "${CONFIG_DIR}/rollup.json.tmp" && \
    mv "${CONFIG_DIR}/rollup.json.tmp" "${CONFIG_DIR}/rollup.json"

if [[ "$ALTDA_TYPE" == "celestia" ]]; then
    echo "Adding alt_da config for Celestia to rollup.json..."
    jq '. + {"alt_da": {"da_challenge_contract_address": "0x0000000000000000000000000000000000000000", "da_commitment_type": "GenericCommitment", "da_challenge_window": 160, "da_resolve_window": 160}}' \
        "${CONFIG_DIR}/rollup.json" > "${CONFIG_DIR}/rollup.json.tmp" && \
        mv "${CONFIG_DIR}/rollup.json.tmp" "${CONFIG_DIR}/rollup.json"
elif [[ "$ALTDA_TYPE" == "eigenda" ]]; then
    echo "Adding alt_da config for EigenDA to rollup.json..."
    jq '. + {"alt_da": {"da_challenge_contract_address": "0x0000000000000000000000000000000000000000", "da_commitment_type": "GenericCommitment", "da_challenge_window": 300, "da_resolve_window": 300}}' \
        "${CONFIG_DIR}/rollup.json" > "${CONFIG_DIR}/rollup.json.tmp" && \
        mv "${CONFIG_DIR}/rollup.json.tmp" "${CONFIG_DIR}/rollup.json"
fi

echo "Downloading genesis.json..."
if ! curl -sf "${CONDUIT_API_URL}${GENESIS_API_PATH}${SLUG}" -o "${CONFIG_DIR}/genesis.json"; then
    echo "Failed to download genesis.json"
    echo "Do you have the right network slug?"
    exit 1
fi

echo "Normalizing OP Stack fork timestamps in genesis.json..."
jq '
    if .config.canyonTime != null then
        .config.shanghaiTime = .config.canyonTime
    else
        .
    end
    | if .config.ecotoneTime != null then
        .config.cancunTime = .config.ecotoneTime
    else
        .
    end
    | if .config.isthmusTime != null then
        .config.pragueTime = .config.isthmusTime
    else
        .
    end
' "${CONFIG_DIR}/genesis.json" > "${CONFIG_DIR}/genesis.json.tmp" && \
    mv "${CONFIG_DIR}/genesis.json.tmp" "${CONFIG_DIR}/genesis.json"

echo "Fetching bootnodes..."
BOOTNODES=$(curl -sf "${CONDUIT_API_URL}${BOOTNODES_API_PATH}${SLUG}") || {
    echo "Failed to fetch bootnodes"
    echo "Are external nodes enabled for this network?"
    exit 1
}

echo "Fetching static peers..."
STATIC_PEERS=$(curl -sf "${CONDUIT_API_URL}${STATICPEERS_API_PATH}${SLUG}") || {
    echo "Failed to fetch static peers"
    echo "Are external nodes enabled for this network?"
    exit 1
}

echo "Fetching fork timestamps..."
FORK_TIMESTAMPS=$(curl -sf "${CONDUIT_API_URL}${FORK_TIMESTAMPS_API_PATH}${SLUG}") || {
    echo "Failed to fetch fork timestamps"
    exit 1
}

echo "Fetching public IP..."
PUBLIC_IP=""
for provider in "http://ifconfig.me" "http://api.ipify.org" "http://ipecho.net/plain" "http://v4.ident.me"; do
    PUBLIC_IP=$(curl -s --max-time 10 --connect-timeout 5 "$provider") || continue
    if echo "$PUBLIC_IP" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        echo "Public IP: $PUBLIC_IP"
        break
    fi
    PUBLIC_IP=""
done

if [[ -z "$PUBLIC_IP" ]]; then
    echo "Warning: Could not fetch public IP. You may need to set OP_NODE_P2P_ADVERTISE_IP manually."
fi

echo "Updating .env..."
update_env "NETWORK" "${SLUG}"
SNAPSHOT_ENABLED_VALUE="$(get_env "SNAPSHOT_ENABLED")"
if [[ -z "$SNAPSHOT_ENABLED_VALUE" ]]; then
    SNAPSHOT_ENABLED_VALUE="false"
    update_env "SNAPSHOT_ENABLED" "$SNAPSHOT_ENABLED_VALUE"
fi
update_env "L2_REMOTE_RPC" "https://rpc-${SLUG}.t.conduit.xyz"
update_env "OP_NODE_P2P_BOOTNODES" "${BOOTNODES}"
update_env "OP_NODE_P2P_STATIC" "${STATIC_PEERS}"
if [[ -n "$PUBLIC_IP" ]]; then
    update_env "OP_NODE_P2P_ADVERTISE_IP" "$PUBLIC_IP"
fi

# Parse fork timestamps and set OP_NODE-only override env vars
OPNODE_FORKS=("canyon" "delta" "ecotone" "fjord" "granite" "holocene" "isthmus" "jovian")

for fork in "${OPNODE_FORKS[@]}"; do
    timestamp=$(echo "$FORK_TIMESTAMPS" | jq -r ".${fork}_time // empty")
    if [[ -n "$timestamp" ]]; then
        fork_upper=$(echo "$fork" | tr '[:lower:]' '[:upper:]')
        update_env "OP_NODE_OVERRIDE_${fork_upper}" "$timestamp"
    fi
done

# Create jwtsecret file if it doesn't exist
JWTSECRET_FILE="${SCRIPT_DIR}/jwtsecret"
if [[ -f "$JWTSECRET_FILE" ]]; then
    echo "jwtsecret file already exists, keeping existing secret"
else
    echo "Creating jwtsecret file..."
    # Remove if it's a directory (Docker might have created it)
    rm -rf "$JWTSECRET_FILE"
    # Generate random 32-byte hex secret
    openssl rand -hex 32 > "$JWTSECRET_FILE"
    echo "Created jwtsecret file with new random secret"
fi

echo ""
echo "Done! Config files saved to ${CONFIG_DIR}/"
echo "Updated .env with:"
echo "  NETWORK=${SLUG}"
echo "  SNAPSHOT_ENABLED=${SNAPSHOT_ENABLED_VALUE}"
echo "  L2_REMOTE_RPC=https://rpc-${SLUG}.t.conduit.xyz"
echo "  OP_NODE_P2P_BOOTNODES=${BOOTNODES}"
echo "  OP_NODE_P2P_STATIC=${STATIC_PEERS}"
echo "  Fork timestamp overrides for op-node (OP_NODE_OVERRIDE_*)"
echo ""
echo "JWT secret file: ${JWTSECRET_FILE}"
