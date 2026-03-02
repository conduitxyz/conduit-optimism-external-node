# Troubleshooting Guide

Common issues and solutions for running Conduit OP Stack external nodes.

## Node Won't Start

### `execution` container exits immediately

**Symptom:** `docker compose ps` shows the execution container as `exited` or `restarting`.

**Check logs:**
```bash
docker compose logs execution --tail 100
```

**Common causes:**

| Error | Solution |
|-------|----------|
| `Fatal: Failed to register the Ethereum service: datadir already used by another process` | Another instance is running. Stop it first: `docker compose down` |
| `Fatal: Error starting protocol stack: missing block number for head header hash` | Corrupted state. Re-initialize: `make clean && make setup NETWORK=<slug>` |
| `Fatal: invalid genesis` | Wrong genesis.json for this network. Re-run: `make setup NETWORK=<slug>` |
| `Fatal: could not open jwt secret` | JWT file missing or wrong permissions. Check `ls -la jwtsecret` |

### `node` (op-node) container exits immediately

**Check logs:**
```bash
docker compose logs node --tail 100
```

**Common causes:**

| Error | Solution |
|-------|----------|
| `failed to dial L1` | `OP_NODE_L1_ETH_RPC` is empty or unreachable. Test: `curl -X POST $OP_NODE_L1_ETH_RPC -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'` |
| `failed to fetch L1 beacon` | `OP_NODE_L1_BEACON` is empty or unreachable. Test: `curl $OP_NODE_L1_BEACON/eth/v1/beacon/headers/head` |
| `JWT authentication failed` | JWT secret mismatch. Delete `jwtsecret` and re-run setup |
| `rollup config does not match` | Wrong `rollup.json`. Re-download: `make setup NETWORK=<slug>` |

---

## Node Not Syncing

### Unsafe head is stalled (no new blocks)

1. **Check P2P connectivity:**
   ```bash
   # Verify ports are open from outside
   nc -zv <your_public_ip> 9222
   nc -zv <your_public_ip> 30303
   ```

2. **Verify advertise IP matches your public IP:**
   ```bash
   grep OP_NODE_P2P_ADVERTISE_IP .env
   curl -s ifconfig.me
   ```

3. **Check bootnodes are configured:**
   ```bash
   grep OP_NODE_P2P_BOOTNODES .env
   ```

4. **Restart the node:**
   ```bash
   docker compose restart node
   ```

### Safe head is falling behind unsafe head

This means the derivation pipeline is stalling. The batcher may not be posting data to L1.

1. **Check L1 head tracking:**
   ```bash
   make status
   ```
   If L1 head numbers are stale, your L1 RPC connection is the problem.

2. **Test L1 RPC directly:**
   ```bash
   curl -X POST "$OP_NODE_L1_ETH_RPC" \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}'
   ```

3. If L1 is working but safe head is still behind, the batcher may be down — this is a sequencer-side issue. Contact Conduit support.

---

## Performance Issues

### High disk usage

Archive mode stores full historical state. Check usage:
```bash
du -sh ./data
df -h .
```

To reduce disk usage, switch to **full mode** by commenting out the archive flag in your docker-compose file:
```yaml
# - "--gcmode=archive"
```

Then re-sync from scratch:
```bash
make clean
make setup NETWORK=<slug>
make up
```

### High memory usage / OOM kills

Check if the node was OOM killed:
```bash
dmesg | grep -i oom | tail -10
```

Minimum recommended: 16 GB RAM. For archive nodes: 32 GB.

If running on limited memory, reduce `--maxpeers` in the docker-compose file (default: 100).

### Slow sync speed

- Ensure you're using an NVMe SSD, not a spinning disk
- Check I/O wait: `iostat -x 1 5`
- Increase `--maxpeers` if you have bandwidth headroom
- Verify your L1 RPC isn't rate-limiting you

---

## Networking Issues

### Required ports

| Port | Protocol | Service | Direction |
|------|----------|---------|-----------|
| 8545 | TCP | Execution RPC (HTTP) | Inbound (if serving RPC) |
| 8546 | TCP | Execution RPC (WebSocket) | Inbound (if serving WS) |
| 30303 | TCP+UDP | Execution P2P | Inbound + Outbound |
| 9222 | TCP+UDP | OP Node P2P | Inbound + Outbound |

### RPC not accessible

If you can't reach the RPC from outside:

1. Check Docker is mapping ports: `docker compose port execution 8545`
2. Check firewall: `sudo iptables -L -n | grep 8545`
3. The RPC binds to `0.0.0.0` by default. If behind a reverse proxy, ensure the proxy forwards to port 8545.

> **Security note:** The default config has `--http.corsdomain=*` and `--http.vhosts=*`. In production, place the RPC behind a reverse proxy with authentication. Do not expose it directly to the internet.

---

## Upgrading

### Updating node versions

1. Edit `.env` with new version numbers:
   ```bash
   OP_GETH_VERSION=v1.101605.0
   OP_NODE_VERSION=v1.16.5
   ```

2. Pull new images and restart:
   ```bash
   docker compose pull
   docker compose up -d
   ```

3. Verify the node is syncing:
   ```bash
   make status
   ```

### After a hard fork

After a network upgrade (Canyon, Ecotone, Fjord, Granite, etc.):

1. Re-run setup to get updated fork timestamps:
   ```bash
   ./download-config.sh <network-slug>
   ```

2. Update node versions if required, then restart:
   ```bash
   docker compose pull && docker compose up -d
   ```

---

## Getting Help

1. Check [Conduit Status](https://status.conduit.xyz/) for platform-wide issues
2. Review [Conduit Docs](https://docs.conduit.xyz/overview) for setup guides
3. Collect diagnostics before contacting support:
   ```bash
   make status                                    # Sync progress
   docker compose ps                              # Container status
   docker compose logs execution --tail 200       # Geth logs
   docker compose logs node --tail 200            # OP Node logs
   df -h ./data                                   # Disk usage
   free -h                                        # Memory
   ```
