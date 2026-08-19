#!/usr/bin/env bash
# Look up the LLAMA_MODEL path for a given port, sourced from
# llama-port-config.env. Used by hermes-llama@.service template.
#
# Usage: source llama-resolve-config.sh <port>
#   exports: LLAMA_MODEL=<absolute_gguf_path>
#   exits non-zero with a clear message if <port> is not configured.
set -euo pipefail

CONFIG_FILE="/home/hermes-pi/.hermes/scripts/llama-port-config.env"
PORT="${1:-}"

if [[ -z "$PORT" ]]; then
  echo "llama-resolve-config: missing port argument" >&2
  exit 64
fi
if [[ ! -r "$CONFIG_FILE" ]]; then
  echo "llama-resolve-config: config file not found: $CONFIG_FILE" >&2
  exit 66
fi

match="$(awk -v p="$PORT" '!/^[[:space:]]*(#|$)/ && $1==p {print $2; exit}' "$CONFIG_FILE")"
if [[ -z "$match" ]]; then
  echo "llama-resolve-config: no model configured for port $PORT in $CONFIG_FILE" >&2
  exit 65
fi
if [[ ! -r "$match" ]]; then
  echo "llama-resolve-config: model file not readable: $match" >&2
  exit 67
fi

export LLAMA_MODEL="$match"
