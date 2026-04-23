#!/bin/bash
# Sync -dev package contents from the target device into violoop-pro/sysroot/.
#
# Seeds are the direct Build-Depends of gstreamer1.0-rockchip
# (see /home/alex/project/mirrors/debian/control). The script walks the
# installed dependency closure on the device and rsyncs the files those
# packages own into the local sysroot, preserving paths.
#
# Requires: ssh alias `dev` configured; dpkg/rsync on dev.

set -euo pipefail

SSH_HOST="${SSH_HOST:-dev}"

SEEDS=(
    librockchip-mpp-dev
    librga-dev
    libx11-dev
    libdrm-dev
    libgstreamer1.0-dev
    libgstreamer-plugins-base1.0-dev
)

# Packages whose files we never want in the sysroot.
# libllvm15: pulled transitively by the Mesa stack (libgl-dev / libegl-dev);
# ships a 106 MB libLLVM-15.so.1 that exceeds GitHub's 100 MB file limit.
# gstreamer1.0-rockchip doesn't link LLVM, so dropping it is safe.
BLACKLIST=(
    libllvm15
)

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SYSROOT="$REPO_ROOT/violoop-pro/sysroot"

if [ ! -d "$SYSROOT" ]; then
    echo "sysroot not found: $SYSROOT" >&2
    exit 1
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo ">> collecting closure + filelist from $SSH_HOST (seeds: ${SEEDS[*]})"

# Single remote session:
#   1. BFS installed Depends closure from SEEDS
#   2. Union `dpkg -L` of the closure, filter to header/lib/pkgconfig paths,
#      drop directories
#   3. Print closure and filelist, separated by a sentinel
ssh "$SSH_HOST" bash -s -- "${#BLACKLIST[@]}" "${BLACKLIST[@]}" "${SEEDS[@]}" >"$TMP/remote.out" <<'REMOTE'
set -euo pipefail

nblack="$1"; shift
declare -A BLACK
for ((i=0; i<nblack; i++)); do BLACK[$1]=1; shift; done

is_installed() {
    local s
    s=$(dpkg-query -W -f='${Status}' "$1" 2>/dev/null || true)
    [ "$s" = "install ok installed" ] || [ "$s" = "hold ok installed" ]
}

declare -A SEEN
QUEUE=("$@")

while [ ${#QUEUE[@]} -gt 0 ]; do
    pkg="${QUEUE[0]}"
    QUEUE=("${QUEUE[@]:1}")
    [ -n "${SEEN[$pkg]:-}" ] && continue
    [ -n "${BLACK[$pkg]:-}" ] && continue
    is_installed "$pkg" || continue
    SEEN[$pkg]=1

    deps=$(dpkg-query -W -f='${Depends}\n${Pre-Depends}\n' "$pkg" 2>/dev/null || true)
    IFS=',' read -ra parts <<< "$deps"
    for part in "${parts[@]}"; do
        IFS='|' read -ra alts <<< "$part"
        for alt in "${alts[@]}"; do
            name=$(echo "$alt" | sed -E 's/\(.*\)//; s/:[a-zA-Z0-9]+//; s/^[[:space:]]+//; s/[[:space:]]+$//')
            [ -z "$name" ] && continue
            if is_installed "$name"; then
                QUEUE+=("$name")
                break
            fi
        done
    done
done

CLOSURE=$(printf '%s\n' "${!SEEN[@]}" | sort)

echo "### CLOSURE ###"
printf '%s\n' "$CLOSURE"

echo "### FILES ###"
printf '%s\n' "$CLOSURE" | xargs -r dpkg -L 2>/dev/null | \
    awk '
    /^\/usr\/include\// ||
    /^\/usr\/lib\/aarch64-linux-gnu\// ||
    /^\/usr\/share\/pkgconfig\// ||
    /^\/usr\/share\/aclocal\// ||
    /^\/lib\/aarch64-linux-gnu\// ||
    /^\/usr\/lib\/ld-/ ||
    /^\/lib\/ld-/ { print }
    ' | sort -u | while IFS= read -r path; do
        # keep regular files and symlinks; drop directories and nonexistent
        if [ -L "$path" ] || { [ -f "$path" ] && [ ! -d "$path" ]; }; then
            printf '%s\n' "$path"
        fi
    done
REMOTE

awk '/^### CLOSURE ###$/{m=1;next} /^### FILES ###$/{m=2;next} m==1{print >"'"$TMP"'/closure"} m==2{print >"'"$TMP"'/files"}' "$TMP/remote.out"

PKG_COUNT=$(wc -l <"$TMP/closure")
FILE_COUNT=$(wc -l <"$TMP/files")
echo ">> closure: $PKG_COUNT packages"
sed 's/^/   /' "$TMP/closure"
echo ">> files to transfer: $FILE_COUNT"

BEFORE=$(du -sb "$SYSROOT" | awk '{print $1}')

echo ">> streaming files via tar-over-ssh into $SYSROOT"
# tar -T - reads NUL/newline-separated filenames; it strips leading '/'
# (with a warning we silence) so paths land under $SYSROOT unchanged.
# --dereference=no (default) preserves symlinks as-is.
ssh "$SSH_HOST" 'tar -cf - --no-recursion -T - 2>/dev/null' <"$TMP/files" | \
    tar -xf - -C "$SYSROOT"

if command -v symlinks >/dev/null 2>&1; then
    echo ">> relativizing absolute symlinks"
    symlinks -cr "$SYSROOT" >/dev/null
else
    echo "!! 'symlinks' not installed locally; skipping relativization"
fi

AFTER=$(du -sb "$SYSROOT" | awk '{print $1}')
DELTA_KIB=$(( (AFTER - BEFORE) / 1024 ))
echo ">> done. sysroot grew by ${DELTA_KIB} KiB (now $(du -sh "$SYSROOT" | awk '{print $1}'))"
