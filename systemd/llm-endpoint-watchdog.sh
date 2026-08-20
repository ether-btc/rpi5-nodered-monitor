#!/usr/bin/env bash
# LLM endpoint watchdog — stable-state emitter for hermes cron monitor_script.
#
# This is the lightweight layer. For each known port, it probes /v1/models
# (with a short timeout), debounces consecutive failures (FAIL_THRESHOLD
# before declaring DOWN), and emits ONE OF:
#
#   - "OK 8080 8081"   — when every port is UP (identical bytes when
#     state is stable; cron monitor_script hash-suppresses delivery).
#   - "DOWN 8080 was_up=true" / "DOWN 8082 was_up=true"   — the FIRST run
#     after a transition to DOWN (different bytes; cron delivers).
#   - "UP 8080 was_down=true"    — on recovery (different bytes; cron delivers).
#   - "UP_RECONCILED"   — one-shot baseline suppression on first run.
#
# Bytes are deliberately deterministic (no timestamps, no random ordering)
# so the cron monitor hash-gate suppresses quiet runs entirely.
#
# Counter persistence and threshold tuning live here, not in cron.
set -uo pipefail

PORTS_DEFAULT="8080 8081"
PROBE_TIMEOUT="${WATCHDOG_PROBE_TIMEOUT:-2}"
FAIL_THRESHOLD="${WATCHDOG_FAIL_THRESHOLD:-3}"

STATE_DIR="${HOME}/.hermes/state/llm-watchdog"
LOG_FILE="${HOME}/.hermes/logs/llm-watchdog.log"
mkdir -p "$STATE_DIR" "$(dirname "$LOG_FILE")"

PORTS="${WATCHDOG_PORTS:-$PORTS_DEFAULT}"

# Re-alert interval (epoch seconds). Default 3600 = 1 hour, ensures a
# sustained outage that the operator has not acted on still produces a
# periodic signal rather than going quiet. The cron's hash-gate
# suppresses the steady-state "OK" lines.
REALERT_INTERVAL="${WATCHDOG_REALERT_INTERVAL_SECONDS:-3600}"

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
log() { echo "[$(now)] $*" >>"$LOG_FILE"; }

probe() {
  local port="$1"
  curl --silent --fail --max-time "$PROBE_TIMEOUT" \
    "http://127.0.0.1:${port}/v1/models" 2>/dev/null \
    | grep -qE '"id":"[^"]+"'
}

# Sort port list so output bytes are deterministic regardless of input order.
read -ra PORT_ARR <<< "$(printf '%s\n' $PORTS | sort -u | tr '\n' ' ')"

declare -A transition_lines=()  # collect transition lines, emit at end
declare -a down_ports=()        # current DOWN state for the OK-line decision

for port in "${PORT_ARR[@]}"; do
  state_file="$STATE_DIR/port-${port}.state"
  fail_file="$STATE_DIR/port-${port}.consecutive_failures"
  alert_file="$STATE_DIR/port-${port}.last_alert_epoch"

  [[ -f "$state_file" ]] || echo "UNKNOWN" >"$state_file"
  [[ -f "$fail_file" ]]  || echo 0       >"$fail_file"
  [[ -f "$alert_file" ]] || echo 0       >"$alert_file"

  prior_state=$(<"$state_file")
  prior_fails=$(<"$fail_file")

  if probe "$port"; then
    new_state="UP"
    new_fails=0
  else
    new_fails=$((prior_fails + 1))
    if (( new_fails >= FAIL_THRESHOLD )); then
      new_state="DOWN"
    else
      new_state="$prior_state"
    fi
  fi

  echo "$new_state" >"$state_file"
  echo "$new_fails"  >"$fail_file"

  # Suppress baseline UP transitions on first-ever run.
  if [[ "$prior_state" == "UNKNOWN" && "$new_state" == "UP" ]]; then
    log "BASELINE port=${port} UP at first run"
    continue
  fi

  if [[ "$new_state" != "$prior_state" ]]; then
    if [[ "$new_state" == "DOWN" ]]; then
      log "TRANSITION port=${port} DOWN (after ${new_fails} consecutive failures; prior=$prior_state)"
      transition_lines["DOWN_${port}"]="DOWN ${port} was_up=$([ "$prior_state" == "UP" ] && echo true || echo false)"
      date +%s >"$alert_file"
    else
      log "TRANSITION port=${port} UP (prior=$prior_state)"
      transition_lines["UP_${port}"]="UP ${port} was_down=true"
      echo 0 >"$alert_file"
    fi
  elif [[ "$new_state" == "DOWN" ]]; then
    # Sustained-down re-alert: emit a "STILL_DOWN" line if the port has
    # been DOWN continuously AND the last alert was more than
    # REALERT_INTERVAL seconds ago.
    #
    # If alert_epoch is 0 (uninitialized — happens when the file existed
    # but no transition ever fired on this port, e.g. we forced it via
    # test setup, or the file pre-dates the persistent alert feature),
    # treat the very first probe at DOWN as a fresh transition line and
    # baseline the epoch. This avoids emitting absurd "for_mins=29785966"
    # placeholders when there is no real prior alert history.
    last_alert=$(<"$alert_file")
    now_epoch=$(date +%s)
    if (( last_alert == 0 )); then
      log "TRANSITION port=${port} DOWN (forced/preexisting prior state)"
      transition_lines["DOWN_${port}"]="DOWN ${port} was_up=$([ "$prior_state" == "UP" ] && echo true || echo false)"
      date +%s >"$alert_file"
    elif (( now_epoch - last_alert >= REALERT_INTERVAL )); then
      log "SUSTAINED port=${port} DOWN (last_alert=$last_alert, now=$now_epoch)"
      mins=$(( (now_epoch - last_alert) / 60 ))
      transition_lines["STILL_DOWN_${port}"]="STILL_DOWN ${port} for_mins=$mins"
      date +%s >"$alert_file"
    fi
  fi

  if [[ "$new_state" == "DOWN" ]]; then
    down_ports+=("$port")
  fi
done

# Emit bytes ONLY in one of these modes:
#  1. Any transition occurred this run (UP, DOWN, STILL_DOWN re-alert):
#     emit the transition line(s) — different bytes from prior run, so
#     the cron monitor hash-gate delivers them.
#  2. No transition AND all UP — emit a single stable "OK ..." line —
#     every happy run produces identical bytes and is suppressed.
#  3. No transition AND at least one DOWN — emit a stable
#     "SUSTAINED_DOWN ports=..." line — also byte-identical between
#     probes (sorted, deterministic) and suppressed between re-alerts.

if (( ${#transition_lines[@]} > 0 )); then
  for k in $(printf '%s\n' "${!transition_lines[@]}" | sort); do
    echo "${transition_lines[$k]}"
  done
elif (( ${#down_ports[@]} > 0 )); then
  sorted_downs="$(printf '%s\n' "${down_ports[@]}" | sort | tr '\n' ',' | sed 's/,$//')"
  printf "SUSTAINED_DOWN ports=%s\n" "$sorted_downs"
else
  port_list="$(printf '%s\n' "${PORT_ARR[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"
  printf "OK %s\n" "$port_list"
fi
