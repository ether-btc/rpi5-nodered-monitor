#!/usr/bin/env bash
# Recover the node-red-dashboard palette after an image rebuild.
#
# run.sh does this automatically on first launch. Run this script manually
# if you ever pulled a new node-red image (which destroys the in-container
# writable layer where the palette lives).
#
# Why this dance:
#   `npm install -g node-red-dashboard` inside the container lands in the
#   writable overlay layer. That layer is destroyed whenever the container
#   is recreated (e.g. on a new image pull). The persistent /data volume
#   survives, so we symlink the dashboard module there for the next start.

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-nodered}"

if ! podman container exists "$CONTAINER_NAME"; then
  echo "ERROR: container $CONTAINER_NAME not found. Run run.sh first." >&2
  exit 1
fi

echo "[1/4] Installing node-red-dashboard globally inside the container..."
podman exec -u root "$CONTAINER_NAME" \
  npm install -g --unsafe-perm node-red-dashboard 2>&1 | tail -3

echo "[2/4] Symlinking into persistent /data/node_modules..."
podman exec -u root "$CONTAINER_NAME" mkdir -p /data/node_modules
podman exec -u root "$CONTAINER_NAME" \
  ln -sfn /usr/local/lib/node_modules/node-red-dashboard \
            /data/node_modules/node-red-dashboard

echo "[3/4] Restarting container to pick up the new palette..."
podman restart "$CONTAINER_NAME"

echo "[4/4] Waiting for boot (~25s)..."
sleep 25

echo ""
echo "Done. Open http://127.0.0.1:1880/ui via SSH tunnel."
