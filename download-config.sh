#!/usr/bin/env bash
#
# Download Conduit network configs and update .env
#

set -euo pipefail

CONDUIT_API_URL="https://api.conduit.xyz"
STATICPEERS_API_PATH="/public/network/staticPeers/"
ELPEERS_API_PATH="/public/network/elPeers/"
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

get_bool_env() {
    local key="$1"
    local value="${!key:-}"

    if [[ -z "$value" ]]; then
        value="$(get_env "$key")"
    fi

    case "$value" in
        true|TRUE|1|yes|YES)
            echo "true"
            ;;
        *)
            echo "false"
            ;;
    esac
}

delete_env() {
    local key="$1"

    if [[ -f "$ENV_FILE" ]]; then
        sed -i.bak "/^${key}=/d" "$ENV_FILE"
        rm -f "${ENV_FILE}.bak"
    fi
}

get_eigenda_network_from_l1_chain_id() {
    local eth_rpc="$1"
    local response
    local chain_id

    response="$(curl -sfS --max-time 20 \
        -H 'content-type: application/json' \
        --data '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}' \
        "$eth_rpc")" || return 1

    chain_id="$(echo "$response" | jq -er '.result // empty')" || return 1

    case "$chain_id" in
        0x1|0X1)
            echo "mainnet"
            ;;
        0xaa36a7|0XAA36A7)
            echo "sepolia_testnet"
            ;;
        *)
            echo "Unsupported L1 chain ID for EigenDA: ${chain_id}" >&2
            return 1
            ;;
    esac
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

if [[ "$(get_bool_env "UPDATE_BEDROCK_BLOCK")" == "true" ]]; then
    case "$SLUG" in
        saigon-testnet-cc58e966ql)
            BEDROCK_BLOCK=45528550
            ;;
        ronin-mainnet-bfz9fadqzl)
            BEDROCK_BLOCK=55577500
            ;;
        zircuit-garfield-testnet)
            BEDROCK_BLOCK=21503691
            ;;
        zircuit-mainnet)
            BEDROCK_BLOCK=32956468
            ;;
        *)
            echo "UPDATE_BEDROCK_BLOCK=true is only supported for Ronin and Zircuit networks:"
            echo "  saigon-testnet-cc58e966ql"
            echo "  ronin-mainnet-bfz9fadqzl"
            echo "  zircuit-garfield-testnet"
            echo "  zircuit-mainnet"
            exit 1
            ;;
    esac

    echo "Updating genesis bedrockBlock to ${BEDROCK_BLOCK}..."
    jq --argjson block "$BEDROCK_BLOCK" \
        '.config.bedrockBlock = $block' \
        "${CONFIG_DIR}/genesis.json" > "${CONFIG_DIR}/genesis.json.tmp" && \
        mv "${CONFIG_DIR}/genesis.json.tmp" "${CONFIG_DIR}/genesis.json"
fi

# The CL static peer: how op-node follows the chain tip (gossip). The API
# returns op-elproxy's gossip multiaddr where it is deployed, else
# op-syncproxy's. There is no discovery network; this peer is the only CL
# connectivity the node has.
echo "Fetching static peers..."
STATIC_PEERS=$(curl -sf "${CONDUIT_API_URL}${STATICPEERS_API_PATH}${SLUG}") || {
    echo "Failed to fetch static peers"
    echo "Are external nodes enabled for this network?"
    exit 1
}

# Execution-layer peer.
#
# op-node v1.19.1 removed the req-resp consensus-layer sync client, so a node
# that falls behind no longer closes the gap by asking a CL peer for the blocks
# it missed; its execution layer fetches them from EL peers instead. Nothing
# else in this compose gives the EL a peer, so without this a node that falls
# behind can only derive the gap from L1/DA: slow, and impossible on altDA
# chains once the data has passed its retention window.
#
# Written to reth.toml as a *trusted* peer rather than a bootnode. That is
# load-bearing: if a requested range runs past what the peer retains it answers
# short, which reth treats as a bad message. Untrusted, a handful of those bans
# it for hours; trusted, the penalty is clamped and the ban is seconds.
#
# reth.toml is always written, even with no peer, because the compose files pass
# --config unconditionally.
echo "Fetching EL peer..."
EL_PEER=$(curl -sf "${CONDUIT_API_URL}${ELPEERS_API_PATH}${SLUG}") || EL_PEER=""

if [[ -n "$EL_PEER" ]]; then
    echo "  EL peer: ${EL_PEER}"
    TRUSTED_NODES=$(printf '%s' "$EL_PEER" | tr ',' '\n' | sed '/^$/d' | sed 's/.*/  "&",/')
else
    echo "  No EL peer published for this network."
    echo "  Following the chain tip is unaffected, but closing a gap will fall"
    echo "  back to deriving from L1/DA, which cannot recover blocks whose data"
    echo "  has passed its retention window."
    TRUSTED_NODES=""
fi

cat > "${CONFIG_DIR}/reth.toml" <<RETH_TOML
# Generated by download-config.sh. Edits will be overwritten.
[peers]
trusted_nodes = [
${TRUSTED_NODES}
]
RETH_TOML

echo "Fetching fork timestamps..."
FORK_TIMESTAMPS=$(curl -sf "${CONDUIT_API_URL}${FORK_TIMESTAMPS_API_PATH}${SLUG}") || {
    echo "Failed to fetch fork timestamps"
    exit 1
}

PECTRA_BLOB_SCHEDULE_TIME=$(echo "$FORK_TIMESTAMPS" | jq -r '.pectrablobschedule_time // .pectra_blob_schedule_time // empty')
if [[ -n "$PECTRA_BLOB_SCHEDULE_TIME" ]]; then
    echo "Adding pectra_blob_schedule_time to rollup.json..."
    jq --argjson timestamp "$PECTRA_BLOB_SCHEDULE_TIME" \
        '.pectra_blob_schedule_time = $timestamp' \
        "${CONFIG_DIR}/rollup.json" > "${CONFIG_DIR}/rollup.json.tmp" && \
        mv "${CONFIG_DIR}/rollup.json.tmp" "${CONFIG_DIR}/rollup.json"
fi

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

echo "Validating L1 configuration..."
if [[ -f "$ENV_FILE" ]]; then
    set -a
    source "$ENV_FILE"
    set +a
fi

if [[ -z "${OP_NODE_L1_ETH_RPC:-}" ]]; then
    echo ""
    echo "WARNING: OP_NODE_L1_ETH_RPC is not set in .env"
    echo "  You must set this to your L1 Ethereum RPC URL before starting the node."
fi

if [[ -z "${OP_NODE_L1_BEACON:-}" ]]; then
    echo ""
    echo "WARNING: OP_NODE_L1_BEACON is not set in .env"
    echo "  You must set this to your L1 Beacon chain RPC URL before starting the node."
fi

echo "Updating .env..."
update_env "NETWORK" "${SLUG}"
SNAPSHOT_ENABLED_VALUE="$(get_env "SNAPSHOT_ENABLED")"
if [[ -z "$SNAPSHOT_ENABLED_VALUE" ]]; then
    SNAPSHOT_ENABLED_VALUE="false"
    update_env "SNAPSHOT_ENABLED" "$SNAPSHOT_ENABLED_VALUE"
fi
update_env "L2_REMOTE_RPC" "https://rpc-${SLUG}.t.conduit.xyz"
update_env "OP_NODE_P2P_STATIC" "${STATIC_PEERS}"
# Gone since op-node v1.19.1: bootnode discovery is unused (the CL peer is
# static) and the req-resp sync client these flags served no longer exists.
delete_env "OP_NODE_P2P_BOOTNODES"
delete_env "OP_NODE_P2P_SYNC_ONLYREQTOSTATIC"
if [[ -n "$PUBLIC_IP" ]]; then
    update_env "OP_NODE_P2P_ADVERTISE_IP" "$PUBLIC_IP"
fi

if [[ "$ALTDA_TYPE" == "eigenda" ]]; then
    L1_ETH_RPC_VALUE="$(get_env "OP_NODE_L1_ETH_RPC")"
    L1_BEACON_VALUE="$(get_env "OP_NODE_L1_BEACON")"

    if [[ -z "$L1_ETH_RPC_VALUE" || -z "$L1_BEACON_VALUE" ]]; then
        echo "ALTDA=eigenda requires OP_NODE_L1_ETH_RPC and OP_NODE_L1_BEACON to be set in .env before setup."
        exit 1
    fi

    if ! EIGENDA_NETWORK_VALUE="$(get_eigenda_network_from_l1_chain_id "$L1_ETH_RPC_VALUE")"; then
        echo "Failed to determine EigenDA network from OP_NODE_L1_ETH_RPC eth_chainId."
        echo "Supported L1 chain IDs are Ethereum mainnet (0x1) and Sepolia (0xaa36a7)."
        echo "OP_NODE_L1_ETH_RPC=${L1_ETH_RPC_VALUE}"
        echo "OP_NODE_L1_BEACON=${L1_BEACON_VALUE}"
        exit 1
    fi

    case "$EIGENDA_NETWORK_VALUE" in
        mainnet)
            EIGENDA_VERIFIER_ADDR="0x1be7258230250Bc6a4548F8D59d576a87D216C12"
            EIGENDA_DISPERSER_RPC_DEFAULT="disperser.eigenda.xyz:443"
            ;;
        sepolia_testnet)
            EIGENDA_VERIFIER_ADDR="0x17ec4112c4BbD540E2c1fE0A49D264a280176F0D"
            EIGENDA_DISPERSER_RPC_DEFAULT="disperser-testnet-sepolia.eigenda.xyz:443"
            ;;
    esac

    EIGENDA_DISPERSER_RPC_VALUE="$EIGENDA_DISPERSER_RPC_DEFAULT"

    update_env "EIGENDA_PROXY_EIGENDA_V2_NETWORK" "$EIGENDA_NETWORK_VALUE"
    update_env "EIGENDA_PROXY_EIGENDA_V2_CERT_VERIFIER_ROUTER_OR_IMMUTABLE_VERIFIER_ADDR" "$EIGENDA_VERIFIER_ADDR"
    update_env "EIGENDA_PROXY_STORAGE_BACKENDS_TO_ENABLE" "V2"
    update_env "EIGENDA_PROXY_STORAGE_DISPERSAL_BACKEND" "V2"
    update_env "EIGENDA_PROXY_EIGENDA_V2_DISPERSER_RPC" "$EIGENDA_DISPERSER_RPC_VALUE"
    delete_env "EIGENDA_DIRECTORY"
fi

# Parse fork timestamps and set OP_NODE-only override env vars
OPNODE_FORKS=("canyon" "delta" "ecotone" "fjord" "granite" "holocene" "isthmus" "jovian" "karst")

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
    chmod 600 "$JWTSECRET_FILE"
else
    echo "Creating jwtsecret file..."
    # Remove if it's a directory (Docker might have created it)
    rm -rf "$JWTSECRET_FILE"
    # Generate random 32-byte hex secret with restrictive permissions
    openssl rand -hex 32 > "$JWTSECRET_FILE"
    chmod 600 "$JWTSECRET_FILE"
    echo "Created jwtsecret file with new random secret"
fi

echo ""
echo "Done! Config files saved to ${CONFIG_DIR}/"
echo "Updated .env with:"
echo "  NETWORK=${SLUG}"
echo "  SNAPSHOT_ENABLED=${SNAPSHOT_ENABLED_VALUE}"
echo "  L2_REMOTE_RPC=https://rpc-${SLUG}.t.conduit.xyz"
echo "  OP_NODE_P2P_STATIC=${STATIC_PEERS}"
if [[ "$ALTDA_TYPE" == "eigenda" ]]; then
    echo "  OP_RETH_IMAGE=$(get_env "OP_RETH_IMAGE")"
    echo "  OP_RETH_VERSION=$(get_env "OP_RETH_VERSION")"
    echo "  EIGENDA_PROXY_EIGENDA_V2_NETWORK=${EIGENDA_NETWORK_VALUE}"
    echo "  EIGENDA_PROXY_EIGENDA_V2_CERT_VERIFIER_ROUTER_OR_IMMUTABLE_VERIFIER_ADDR=${EIGENDA_VERIFIER_ADDR}"
    echo "  EIGENDA_PROXY_STORAGE_BACKENDS_TO_ENABLE=V2"
    echo "  EIGENDA_PROXY_STORAGE_DISPERSAL_BACKEND=V2"
    echo "  EIGENDA_PROXY_EIGENDA_V2_DISPERSER_RPC=${EIGENDA_DISPERSER_RPC_VALUE}"
fi
echo "  Fork timestamp overrides for op-node (OP_NODE_OVERRIDE_*)"
echo ""
echo "JWT secret file: ${JWTSECRET_FILE}"
