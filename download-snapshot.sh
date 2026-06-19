#!/usr/bin/env bash

set -euo pipefail

NETWORK="${1:-${NETWORK:-}}"
DATADIR="${DATADIR:-./data}"
DB_PATH="${DATADIR}/db/mdbx.dat"
TMP_SNAPSHOT=""

cleanup() {
    if [[ -n "$TMP_SNAPSHOT" && -f "$TMP_SNAPSHOT" ]]; then
        rm -f "$TMP_SNAPSHOT"
    fi
}
trap cleanup EXIT

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

if [[ -z "${GCP_PROJECT:-}" && -f .env ]]; then
    GCP_PROJECT="$(
        awk -F= '/^GCP_PROJECT=/{print substr($0, index($0, "=") + 1); exit}' .env |
            sed -e 's/^["'\'']//; s/["'\'']$//'
    )"
fi

if [[ -z "${GCP_PROJECT:-}" ]] && command -v gcloud >/dev/null 2>&1; then
    GCP_PROJECT="$(gcloud config get-value project 2>/dev/null || true)"
    if [[ "$GCP_PROJECT" == "(unset)" ]]; then
        GCP_PROJECT=""
    fi
fi

if ! command -v gsutil >/dev/null 2>&1; then
    echo "Error: gsutil is required to restore requester-pays snapshots."
    echo "Install the Google Cloud SDK and configure billing."
    exit 1
fi

if [[ -z "${GCP_PROJECT:-}" ]]; then
    echo "Error: GCP_PROJECT is required to restore requester-pays snapshots."
    echo "Add GCP_PROJECT=<project-id> to .env, export it, or run: gcloud config set project <project-id>"
    exit 1
fi

SNAPSHOT_URL="gs://conduit-networks-snapshots/${NETWORK}/latest.tar"
TMP_SNAPSHOT="$(mktemp "${TMPDIR:-/tmp}/conduit-snapshot.XXXXXX")"

echo "Downloading snapshot from ${SNAPSHOT_URL} into ${DATADIR}..."
gsutil -u "$GCP_PROJECT" cp "$SNAPSHOT_URL" "$TMP_SNAPSHOT"

tar --no-same-owner --no-same-permissions -xvf "$TMP_SNAPSHOT" -C "$DATADIR" --strip-components=1
echo "Snapshot restore complete."
