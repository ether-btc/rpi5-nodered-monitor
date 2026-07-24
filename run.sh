#!/usr/bin/env bash
# Start the Node-RED RPi5 monitor container (localhost-only, persistent, auto-restart).
# Idempotent: removes an existing container with the same name first.

set -euo pipefail

CONTAINER_NAME="nodered"
DATA_DIR="/home/hermes-pi/nodered-data"
IMAGE="docker.io/nodered/node-red:latest-minimal"

# Ensure data dir exists and is writable
if [[ ! -d "$DATA_DIR" ]]; then
  echo "Creating $DATA_DIR"
  mkdir -p "$DATA_DIR"
fi
chmod 777 "$DATA_DIR"

# Remove existing container (ignore if missing)
if podman container exists "$CONTAINER_NAME" 2>/dev/null; then
  echo "Removing existing container: $CONTAINER_NAME"
  podman rm -f "$CONTAINER_NAME" >/dev/null
fi

# Pull latest image (will skip if already up to date)
echo "Pulling $IMAGE"
podman pull "$IMAGE"

# Run the container
echo "Starting $CONTAINER_NAME on 127.0.0.1:1880"
podman run -d \
  --name "$CONTAINER_NAME" \
  --userns=keep-id \
  -p 127.0.0.1:1880:1880 \
  -v "$DATA_DIR:/data" \
  -v /sys/class/thermal:/sys/class/thermal:ro \
  -v /proc/stat:/proc/stat:ro \
  -v /proc/meminfo:/proc/meminfo:ro \
  -v /proc/loadavg:/proc/loadavg:ro \
  --restart unless-stopped \
  "$IMAGE"

echo "Container started. Wait ~20s, then access via SSH tunnel."
echo "Local test: curl http://127.0.0.1:1880/"
echo "Tunnel:     ssh -N -L 1880:127.0.0.1:1880 hermes-pi@<pi-ip>"
