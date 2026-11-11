#!/usr/bin/env bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/source/snapshot/db" "$WORK/source/snapshot/static_files"
printf 'offline snapshot database\n' > "$WORK/source/snapshot/db/mdbx.dat"
printf 'static snapshot content\n' > "$WORK/source/snapshot/static_files/header"
# Real tar bytes split across headers and file contents, not independent archives.
tar -cf "$WORK/snapshot.tar" -C "$WORK/source" snapshot
split -b 700 "$WORK/snapshot.tar" "$WORK/snapshot_part_"
for part in "$WORK"/snapshot_part_*; do mv "$part" "${part}.tar.part"; done

# Only the transport is replaced; execute the repository's real restore script.
cat > "$WORK/bin/gcloud" <<'GCLOUD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "$CALLS"
[[ "$1" == --billing-project=offline-billing ]] || exit 90
shift
[[ "$1" == storage ]] || exit 91
shift
case "$1" in
    ls)
        pattern="${2#gs://conduit-networks-snapshots/fixture/}"
        found=false
        # Reverse order deliberately: the downloader must select filename order.
        while IFS= read -r path; do
            if [[ "${path##*/}" == $pattern ]]; then
                printf 'gs://conduit-networks-snapshots/fixture/%s\n' "${path##*/}"
                found=true
            fi
        done < <(printf '%s\n' "$OBJECTS"/* | sort -r)
        "$found"
        ;;
    objects)
        [[ "$2" == describe ]] || exit 92
        path="$OBJECTS/${3##*/}"
        [[ -f "$path" ]] || exit 1
        wc -c < "$path"
        ;;
    cat)
        shift
        for url in "$@"; do
            [[ "$url" == gs://conduit-networks-snapshots/fixture/* ]] || exit 93
            cat "$OBJECTS/${url##*/}" || exit 1
        done
        ;;
    *) exit 94 ;;
esac
GCLOUD
chmod +x "$WORK/bin/gcloud"
export PATH="$WORK/bin:$PATH" GCP_PROJECT=offline-billing
export CALLS="$WORK/calls" OBJECTS="$WORK/objects"
mkdir -p "$OBJECTS"

restore() {
    local case_name="$1"
    : > "$CALLS"
    if ! (cd "$WORK" && DATADIR="$WORK/restored-$case_name" bash "$REPO_DIR/download-snapshot.sh" fixture) > "$WORK/$case_name.log" 2>&1; then
        cat "$WORK/$case_name.log" >&2
        return 1
    fi
    cmp "$WORK/source/snapshot/db/mdbx.dat" "$WORK/restored-$case_name/db/mdbx.dat"
    cmp "$WORK/source/snapshot/static_files/header" "$WORK/restored-$case_name/static_files/header"
    if [[ -e "$WORK/restored-$case_name/snapshot" ]]; then
        echo "Unexpected archive parent directory" >&2
        exit 1
    fi
    echo "PASS: $case_name"
}

cp "$WORK"/snapshot_part_*.tar.part "$OBJECTS/"
restore multipart
# Retaining a stale single archive must not override the documented split format.
printf 'stale non-archive object\n' > "$OBJECTS/latest.tar"
restore multipart-preferred
rm "$OBJECTS"/snapshot_part_*.tar.part
cp "$WORK/snapshot.tar" "$OBJECTS/latest.tar"
restore single

# Preserve the existing no-overwrite contract, without even requesting storage.
: > "$CALLS"
printf 'existing database\n' > "$WORK/restored-single/db/mdbx.dat"
(cd "$WORK" && DATADIR="$WORK/restored-single" bash "$REPO_DIR/download-snapshot.sh" fixture) > "$WORK/skip.log" 2>&1
[[ "$(cat "$WORK/restored-single/db/mdbx.dat")" == 'existing database' ]]
[[ ! -s "$CALLS" ]]
echo 'PASS: existing database skipped without cloud access'
