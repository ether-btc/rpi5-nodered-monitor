#!/usr/bin/env bash
# Cron wrapper for llm-endpoint-watchdog.sh.
#
# Runs the watchdog, captures its output, and passes it through ONLY when
# the watchdog emitted a state change (any line starting with "DOWN " or
# "UP " or "STILL_DOWN"). On a quiet "OK ..." run, this wrapper exits
# emitting nothing, so the cron's `deliver: telegram` mechanism has no
# payload to deliver — quiet ticks are silent for the operator.
#
# We intentionally also forward sustained-DOWN re-alerts because those
# mean the operator's first alert was apparently ignored or the outage
# is still ongoing.
set -uo pipefail

out="$("$HOME/.hermes/scripts/llm-endpoint-watchdog.sh" 2>/dev/null || true)"
if [[ -z "$out" ]]; then
  exit 0
fi

filtered="$(printf '%s\n' "$out" | grep -E '^(DOWN |UP |STILL_DOWN |SUSTAINED_DOWN )' || true)"
if [[ -z "$filtered" ]]; then
  exit 0
fi

# Extract the affected ports from the filtered lines so the operator
# gets actionable context rather than the placeholder "PORT".
affected_ports="$(printf '%s\n' "$filtered" \
  | awk '/^SUSTAINED_DOWN/ {sub(/^SUSTAINED_DOWN ports=/, ""); gsub(/,/, " "); print; next} {print $2}' \
  | tr '\n' ' ' | sed 's/ $//' | tr ' ' '\n' | sort -u | tr '\n' ' ' | sed 's/ $//')"

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "[$ts] LLM endpoint watchdog — state change:"
echo ""
echo "$filtered"
echo ""
if [[ -n "$affected_ports" ]]; then
  echo "Affected port(s): $affected_ports"
  echo "Investigate one of:"
  for port in $affected_ports; do
    echo "  systemctl --user status hermes-llama@${port}.service"
    echo "  journalctl --user -u hermes-llama@${port}.service -n 30 --no-pager"
  done
else
  echo "Investigate: systemctl --user status 'hermes-llama@*.service'"
fi
