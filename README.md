![Conduit](logo.png)

# Conduit Node

Conduit provides fully-managed, production-grade rollups on Ethereum. We highly recommend using a Conduit RPC for the fastest and most reliable experience, visit the [Conduit App](https://app.conduit.xyz/nodes) to create your very own RPC.

This repository contains the relevant Docker builds to run your own node on OP Stack networks deployed via Conduit.

[![Website conduit.xyz](https://img.shields.io/website-up-down-green-red/https/conduit.xyz.svg)](https://conduit.xyz)
[![Status](https://img.shields.io/badge/status-up-green)](https://status.conduit.xyz/)
[![Blog](https://img.shields.io/badge/blog-up-green)](https://conduit.xyz/blog)
[![Docs](https://img.shields.io/badge/docs-up-green)](https://docs.conduit.xyz/overview)
[![Twitter Conduit](https://img.shields.io/twitter/follow/conduitxyz?style=social)](https://twitter.com/conduitxyz)

## Prerequisites

- Docker and Docker Compose
- `make`
- `jq`
- `curl` and `bc`

## Hardware Requirements

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU | 4 cores | 8+ cores |
| RAM | 16 GB | 32 GB |
| Storage | 500 GB SSD | 1 TB+ NVMe SSD |

## Node Mode

**The node runs in archive mode by default.** Archive mode retains full historical state, which requires more disk space but allows querying any historical block.

To switch to full mode (non-archive), edit the docker-compose file and comment out the gcmode flag:

```yaml
# - "--gcmode=archive"    # Comment this line for full mode
```

| Mode | Description | Disk Usage |
|------|-------------|------------|
| `archive` | Retains all historical state | Higher |
| `full` | Prunes old state, keeps recent | Lower |

## Image Versions

Default Docker image versions (can be overridden in `.env`):

| Variable | Default |
|----------|---------|
| `OP_GETH_VERSION` | `v1.101605.0` |
| `OP_NODE_VERSION` | `v1.16.5` |
| `CELESTIA_DA_SERVER_VERSION` | `0.9.0` |
| `EIGENDA_PROXY_VERSION` | `2.4.1` |

## Required Environment Variables

Before starting, configure these in your `.env` file:

| Variable | Description |
|----------|-------------|
| `OP_NODE_L1_ETH_RPC` | L1 Ethereum RPC URL |
| `OP_NODE_L1_BEACON` | L1 Beacon chain RPC URL |

**Note:** `OP_GETH_SEQUENCER_HTTP` is automatically set by `make setup`. For production usage, create an API key in the [Conduit application](https://app.conduit.xyz/nodes) and append it to the URL:
```
OP_GETH_SEQUENCER_HTTP=https://rpc-<network-slug>.t.conduit.xyz/<api-key>
```


### Optional Environment Variables (if ALT DA is enabled)

### Celestia DA Specific

| Variable | Description |
|----------|-------------|
| `CELESTIA_RPC` | Celestia RPC endpoint |
| `CELESTIA_AUTH_TOKEN` | Celestia authentication token (optional) |
| `CELESTIA_NAMESPACE` | Celestia namespace |

### EigenDA Specific (V2)

| Variable | Description |
|----------|-------------|
| `EIGENDA_DIRECTORY` | EigenDA directory contract address |
| `EIGENDA_PROXY_EIGENDA_V2_CERT_VERIFIER_ROUTER_OR_IMMUTABLE_VERIFIER_ADDR` | V2 cert verifier/router address |
| `EIGENDA_PROXY_STORAGE_BACKENDS_TO_ENABLE` | Storage backend (set to `V2`) |
| `EIGENDA_PROXY_STORAGE_DISPERSAL_BACKEND` | Dispersal backend (set to `V2`) |
| `EIGENDA_PROXY_EIGENDA_V2_DISPERSER_RPC` | V2 disperser RPC endpoint |

## Quick Start

### 1. Configure Environment

```bash
cp .env.example .env
```

Edit `.env` with the required variables listed above.

### 2. Setup and Run

**Standard OP Stack chains:**
```bash
make setup NETWORK=<network-slug>
make up
```

**Celestia (Alt DA) chains:**
```bash
make setup NETWORK=<network-slug> ALTDA=celestia
make up ALTDA=celestia
```

**EigenDA (Alt DA) chains:**
```bash
make setup NETWORK=<network-slug> ALTDA=eigenda
make up ALTDA=eigenda
```

### 3. Monitor and Manage

```bash
make status    # Show sync progress
make logs      # Show container logs
make down      # Stop containers (add ALTDA=celestia/eigenda if enabled)
make clean     # Stop and remove all data (add ALTDA=celestia/eigenda if enabled)
```

## Make Commands

| Command | Description |
|---------|-------------|
| `make setup NETWORK=<slug>` | Download config and initialize geth |
| `make setup NETWORK=<slug> ALTDA=celestia` | Download config for Celestia DA chains |
| `make setup NETWORK=<slug> ALTDA=eigenda` | Download config for EigenDA chains |
| `make up` | Start containers (add `ALTDA=celestia/eigenda` if using Alt DA) |
| `make down` | Stop containers (add `ALTDA=celestia/eigenda` if using Alt DA) |
| `make logs` | Show container logs |
| `make status` | Show sync progress |
| `make clean` | Stop and remove all data (add `ALTDA=celestia/eigenda` if using Alt DA) |

## Configuration Files

| File | Description |
|------|-------------|
| `Makefile` | Make commands for setup and management |
| `docker-compose.yml` | Standard OP Stack configuration |
| `docker-compose.celestia.yml` | Celestia DA configuration |
| `docker-compose.eigenda.yaml` | EigenDA configuration |
| `.env.example` | Environment variable template |
| `download-config.sh` | Downloads rollup.json and genesis.json from Conduit API |
| `sync-status.sh` | Monitors node sync progress |

## Data Storage

Node data is stored in `./data/`

## Disclaimer

THE NODE SOFTWARE AND SMART CONTRACTS CONTAINED HEREIN ARE FURNISHED AS IS, WHERE IS, WITH ALL FAULTS AND WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING ANY WARRANTY OF MERCHANTABILITY, NON- INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE. IN PARTICULAR, THERE IS NO REPRESENTATION OR WARRANTY THAT THE NODE SOFTWARE AND SMART CONTRACTS WILL PROTECT YOUR ASSETS — OR THE ASSETS OF THE USERS OF YOUR APPLICATION — FROM THEFT, HACKING, CYBER ATTACK, OR OTHER FORM OF LOSS OR DEVALUATION.
