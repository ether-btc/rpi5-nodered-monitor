# LLM Inference Endpoints (local llama.cpp)

This host runs three local `llama.cpp` inference endpoints, supervised by
systemd so they (a) start on boot/login and (b) auto-restart if they crash.
A watchdog cron job alerts Telegram if any endpoint stays down.

This replaced the old "nohup llama-server &" setup, where a crash silently
degraded everything that depended on the endpoint (notably Hermes-LCM summary
compression on `:8080`) with no alert.

## Port → model map (source of truth)

Edit bindings in **one file**: `~/.hermes/scripts/llama-port-config.env`.

| Port | Model | Role |
|------|-------|------|
| `:8080` | `Qwen2.5-0.5B-Instruct-Q4_K_M.gguf` | **Hermes-LCM summary compression — dedicated, do not repurpose** |
| `:8081` | `Qwen3-0.6B-Instruct-Q8_0.gguf` | General local agent |
| `:8082` | `microsoft_Phi-4-mini-instruct-Q4_K_M.gguf` | General local agent |

Three together = ~3.2 GiB RSS on a 7.9 GiB host (Pi 5). Do not add a fourth
without measuring headroom.

`:8080` is bound to `127.0.0.1` only and is referenced by
`~/.config/hermes-gateway.env` (`LCM_SUMMARY_MODEL=custom:llama-cpp/Qwen2.5-0.5B-Instruct-Q4_K_M`).
If you ever change the `:8080` model, update that env var too.

## How it works

```
systemd user unit: hermes-llama@.service   (template, one instance per port)
  └─ ExecStart=/home/hermes-pi/.hermes/scripts/llama-server-wrapper.sh %i
       └─ sources llama-resolve-config.sh → exports LLAMA_MODEL from llama-port-config.env
       └─ exec /home/hermes-pi/.local/llama-cpp/llama-server -m $LLAMA_MODEL \
            -c 4096 --port %i --host 127.0.0.1 -tb 2 --no-mmap --mlock
```

`%i` is the port (e.g. `systemctl --user start hermes-llama@8080.service`).
systemd units do **not** propagate env vars from `ExecStartPre` into `ExecStart`,
so the wrapper-script approach (resolve inside the wrapper, then `exec`) is used
instead of a separate resolve step.

### Unit key settings
```
Type=simple
Restart=always
RestartSec=5
OOMPolicy=stop
OOMScoreAdjust=-100
StartLimitIntervalSec=300
StartLimitBurst=10
```

Lingering must be enabled for the user so the units survive logout:
`loginctl show-user hermes-pi | grep Linger` → `Linger=yes`.

## Watchdog (alerting)

A cron job probes each port's `/v1/models` and alerts if it stays down.

- **Job:** `llm-endpoint-watchdog` (cron id `c7ee7503c959`)
- **Schedule:** every 5 min, `no_agent: true`
- **Delivery:** `telegram:505901752`
- **Probe:** `curl --fail --max-time 2 http://127.0.0.1:PORT/v1/models`
- **Debounce:** 3 consecutive failures → first `DOWN` alert; re-alerts every
  3600 s while still down (`STILL_DOWN` / `SUSTAINED_DOWN`). Quiet runs emit a
  stable `OK ...` line that the cron's hash-gate suppresses, so no noise.

Files:
- `~/.hermes/scripts/llm-endpoint-watchdog.sh` — prober + state/debounce logic
- `~/.hermes/scripts/llm-endpoint-watchdog-cron.sh` — formats the Telegram
  message (with `systemctl`/`journalctl` hints) only on state changes
- State: `~/.hermes/state/llm-watchdog/port-NNNN.state`
- Log: `~/.hermes/logs/llm-watchdog.log`

## Operations

### Add / change a model on a port
1. Edit `llama-port-config.env`.
2. `systemctl --user restart hermes-llama@PORT.service`.
3. Verify: `curl -s http://127.0.0.1:PORT/v1/models | grep '"id"'`.

### Restart all
```
for p in 8080 8081 8082; do systemctl --user restart hermes-llama@${p}.service; done
```

### Verify auto-restart works
```
kill -9 $(systemctl --user show -p MainPID --value hermes-llama@PORT.service)
# wait ~6s
systemctl --user show -p MainPID --value hermes-llama@PORT.service   # new PID
```

### Force a watchdog alert (test)
Stop a unit, wait 3 probes (~15 s), check Telegram; then restart.

## Gotchas
- `-mlock` may warn "Cannot allocate memory: try increasing RLIMIT_MEMLOCK"
  after 2+ instances are running. The model still loads; the warning is
  harmless (other instances got the same warning and still serve).
- `n_slots` left at default (`auto`) — saves ~1 GiB per instance vs. high.
- `Type=simple` is correct; llama-server never daemonizes.
- Do **not** repoint `:8080` away from the LCM model without also updating
  `~/.config/hermes-gateway.env`.

## Restore from this repo

The live unit + scripts are mirrored under `systemd/` in this repo. On a fresh
host (or after a botched local edit), rebuild with:

```bash
SRC=$(pwd)/systemd
cp "$SRC/llama-port-config.env"      ~/.hermes/scripts/
cp "$SRC/llama-resolve-config.sh"    ~/.hermes/scripts/
cp "$SRC/llama-server-wrapper.sh"    ~/.hermes/scripts/
cp "$SRC/llm-endpoint-watchdog.sh"   ~/.hermes/scripts/
cp "$SRC/llm-endpoint-watchdog-cron.sh" ~/.hermes/scripts/
chmod +x ~/.hermes/scripts/{llama-resolve-config,llama-server-wrapper,llm-endpoint-watchdog,llm-endpoint-watchdog-cron}.sh
mkdir -p ~/.config/systemd/user
cp "$SRC/hermes-llama@.service"      ~/.config/systemd/user/
systemctl --user daemon-reload
for p in 8080 8081 8082; do systemctl --user enable --now hermes-llama@${p}.service; done
```

(The scripts in `systemd/` are the source of truth for on-disk copies; the
cron job `llm-endpoint-watchdog` must be recreated separately via the Hermes
cron tool — its definition is not file-based.)
