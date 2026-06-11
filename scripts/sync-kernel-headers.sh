#!/bin/bash
# Sync Rockchip kernel headers from the target device into violoop-pro/kernel-headers/.
#
# The headers live at /usr/src/linux-headers-6.1-rockchip on the device and are
# not shipped as a standard deb package, so they must be pulled directly.
#
# Requires: ssh alias `dev11` configured (or override via SSH_HOST); rsync on both sides.

set -euo pipefail

SSH_HOST="${SSH_HOST:-dev11}"
REMOTE_HEADERS="/usr/src/linux-headers-6.1-rockchip"

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$REPO_ROOT/violoop-pro/kernel-headers/linux-headers-6.1-rockchip"

mkdir -p "$DEST"

echo ">> syncing kernel headers from $SSH_HOST:$REMOTE_HEADERS"
rsync -a --delete \
    "$SSH_HOST:$REMOTE_HEADERS/" \
    "$DEST/"

echo ">> done. $(du -sh "$DEST" | awk '{print $1}') in $DEST"
