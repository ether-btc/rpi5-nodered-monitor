#!/usr/bin/env bash
# One-time install of the node-red-dashboard palette into the container.
# Idempotent — safe to re-run.
#
# Why this exists:
#   The image ships node-red globally in /usr/local/lib/node_modules. A
#   plain `npm install -g node-red-dashboard` lands in the image layer, so
#   the next image rebuild loses it. We work around that by symlinking
#   the dashboard module into the persistent /data/node_modules, which
#   Node-RED always scans on startup.

set -euo pipefail

CONTAINER_NAME="${CONTAINER_NAME:-nodered}"

if ! podman container exists "$CONTAINER_NAME"; then
  echo "ERROR: container $CONTAINER_NAME not found. Run run.sh first." >&2
  exit 1
fi

echo "[1/3] Installing node-red-dashboard globally inside the container..."
podman exec -u root "$CONTAINER_NAME" \
  npm install -g --unsafe-perm node-red-dashboard 2>&1 | tail -3

echo "[2/3] Symlinking into persistent /data/node_modules..."
podman exec -u root "$CONTAINER_NAME" \
  ln -sfn /usr/local/lib/node_modules/node-red-dashboard \
            /data/node_modules/node-red-dashboard

echo "[3/3] Restarting container to pick up the new palette..."
podman restart "$CONTAINER_NAME"

echo "Done. Wait ~20s, then open http://127.0.0.1:1880 in a browser"
echo "       (via SSH tunnel). The 'dashboard' group should appear in the"
echo "       left palette under the 'dashboard' category."
