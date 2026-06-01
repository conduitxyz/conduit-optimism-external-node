#!/usr/bin/env bash

set -euo pipefail

NETWORK="${1:-${NETWORK:-}}"
DATADIR="${DATADIR:-./data}"
DB_PATH="${DATADIR}/db/mdbx.dat"

if [[ -z "$NETWORK" ]]; then
    echo "Usage: ./download-snapshot.sh <network-slug>"
    echo "Or set NETWORK in the environment."
    exit 1
fi

mkdir -p "$DATADIR"

if [[ -f "$DB_PATH" ]]; then
    echo "Snapshot restore skipped: ${DB_PATH} already exists."
    exit 0
fi

SNAPSHOT_URL="https://storage.googleapis.com/conduit-networks-snapshots/${NETWORK}/latest.tar"
echo "Downloading snapshot from ${SNAPSHOT_URL} into ${DATADIR}..."
curl -fL --retry 5 --retry-delay 5 "$SNAPSHOT_URL" | tar --no-same-owner --no-same-permissions -xvf - -C "$DATADIR" --strip-components=1
echo "Snapshot restore complete."
