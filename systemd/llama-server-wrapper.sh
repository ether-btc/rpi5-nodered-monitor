#!/usr/bin/env bash
# Wrap llama-server for hermes-llama@.service.
# Resolves the model path for the requested port and exec's llama-server.
#
# Usage: llama-server-wrapper.sh <port>
#
# Env: none required. Model is resolved from llama-port-config.env.
set -euo pipefail

PORT="${1:-}"
if [[ -z "$PORT" ]]; then
  echo "llama-server-wrapper: missing port argument" >&2
  exit 64
fi

# Resolve model via the same lookup the unit's ExecStartPre used to do.
# We re-do it here because systemd does not propagate the resolved env var
# from ExecStartPre into the main ExecStart environment.
. /home/hermes-pi/.hermes/scripts/llama-resolve-config.sh "$PORT"

exec /home/hermes-pi/.local/llama-cpp/llama-server \
  -m "${LLAMA_MODEL}" \
  -c 4096 \
  --port "$PORT" \
  --host 127.0.0.1 \
  -tb 2 \
  --no-mmap \
  --mlock
