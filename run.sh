#!/usr/bin/env bash
# Start the Node-RED RPi5 monitor container (localhost-only, persistent, auto-restart).
# Idempotent: removes an existing container with the same name first.
#
# Bind-mounts the host filesystem under /hostroot inside the container so the
# disk-usage nodes can see real host usage rather than the overlay layer.

set -euo pipefail

CONTAINER_NAME="nodered"
DATA_DIR="/home/hermes-pi/nodered-data"
IMAGE="docker.io/nodered/node-red:latest-minimal"

# Ensure data dir exists and is writable by the in-container user (uid 1000)
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

# Pull latest image (skips if already up to date)
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
  -v /proc/uptime:/proc/uptime:ro \
  -v /proc/mounts:/proc/mounts:ro \
  -v /:/hostroot:ro \
  -v /mnt/data:/hostmnt/data:ro \
  --restart unless-stopped \
  "$IMAGE"

echo ""
echo "Container started. Now installing node-red-dashboard palette (one-time)..."
sleep 20  # let Node-RED finish first boot

# Install the dashboard palette and symlink into persistent volume
podman exec -u root "$CONTAINER_NAME" \
  npm install -g --unsafe-perm node-red-dashboard >/dev/null 2>&1

podman exec -u root "$CONTAINER_NAME" \
  ln -sfn /usr/local/lib/node_modules/node-red-dashboard \
            /data/node_modules/node-red-dashboard

# Load the flow file
if [[ -f "$(dirname "$0")/flows.json" ]]; then
  cp "$(dirname "$0")/flows.json" "$DATA_DIR/flows.json"
  echo "Loaded flows.json"
fi

podman restart "$CONTAINER_NAME"

echo ""
echo "=================================================="
echo "  Done. Container: $CONTAINER_NAME"
echo "  Wait ~30s then access via SSH tunnel:"
echo ""
echo "  ssh -N -L 1880:127.0.0.1:1880 hermes-pi@<pi-ip>"
echo ""
echo "  Editor:    http://127.0.0.1:1880"
echo "  Dashboard: http://127.0.0.1:1880/ui"
echo "=================================================="
