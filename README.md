# rpi5-nodered-monitor

Lightweight **Raspberry Pi 5 hardware monitor** running as a podman container,
backed by a USB drive, exposed via the [Node-RED](https://nodered.org/) dashboard.

Access from any LAN/Tailscale client through an SSH tunnel → `http://127.0.0.1:1880/ui`.

## What it shows

| Metric | Source | Polling | Display |
|--------|--------|---------|---------|
| CPU Temperature | `/sys/class/thermal/thermal_zone0/temp` | 5 s | Gauge + 5-min chart + text |
| Load Average (1m / 5m / 15m) | `/proc/loadavg` | 5 s | Multi-line chart |
| RAM Used | `/proc/meminfo` | 5 s | Gauge + chart + text (MB) |
| Disk usage (SD + USB) & Uptime | `df` + `/proc/uptime` | 30 s | 2 gauges + text + uptime |

**Disk readout note:** the flow uses host bind mounts (`/` → `/hostroot:ro`,
`/mnt/data` → `/hostmnt/data:ro`) so `df` inside the container sees the host's
filesystems instead of the overlay. The parser keys off the block-device
(`/dev/mmcblk0p2`, `/dev/sda1`) rather than the mount-point, because BusyBox
`df` reports the container's overlay mount-point for bind-mounted subtrees.

## Architecture

```
RPi5 (Debian 12, aarch64)
  └─ /mnt/data  (128 GB USB stick, ext4)
       └─ containers/storage/         ← podman image + overlay layers
       └─ home/hermes-pi/nodered-data/ ← /data inside container (flows, settings, modules)
            └─ flows.json
            └─ node_modules/node-red-dashboard → symlink to image global

  Container "nodered"
    - base:    docker.io/nodered/node-red:latest-minimal
    - userns:  keep-id (so /data is writable as host uid 1000)
    - bind:    127.0.0.1:1880:1880   (LOCALHOST ONLY — SSH tunnel required)
    - restart: unless-stopped
    - extras:  global install of node-red-dashboard (symlinked into /data)
```

## Why localhost-only binding?

Node-RED's editor has **no built-in authentication** and is a flow-RCE surface
(see [CVE-2022-32292](https://nodered.org/blog/2022/09/01/node-red-3-0-2-released.html)
and the 2023 dashboard RCE). Binding to `0.0.0.0:1880` on a home LAN is fine-ish
for trusted networks but exposes the editor to every device on the WiFi and to
all Tailscale peers.

This setup binds to `127.0.0.1` only. Access requires an SSH session that is
itself authenticated. This removes the entire "is my LAN actually safe" concern.

## Quick start (fresh install)

Requires:
- RPi5 (or any aarch64 Linux) with **podman 4.x + fuse-overlayfs**
- A USB drive mounted at `/mnt/data` (or change paths in `install.sh`)
- 1.5 GB free for the image + a few hundred MB for `/data`

```bash
# 1. Create persistent dirs (USB-backed)
mkdir -p /home/hermes-pi/nodered-data
chmod 777 /home/hermes-pi/nodered-data   # uid mapping handled by --userns=keep-id

# 2. Pull the image
podman pull docker.io/nodered/node-red:latest-minimal

# 3. Start the container (installs dashboard palette + loads flows.json)
./run.sh

# 4. Tunnel from a client
ssh -N -L 1880:127.0.0.1:1880 hermes-pi@<pi-ip>
# open http://127.0.0.1:1880/ui
```

> `run.sh` is now self-contained: it pulls the image, creates the container with
> all required bind mounts, installs the dashboard palette, symlinks it into the
> persistent volume, copies `flows.json`, and restarts. `install-dashboard.sh`
> is the recovery script to run after a manually-pulled new image.

## Files

- `flows.json` — the exported Node-RED flow with the dashboard
- `run.sh` — podman run command (localhost-only, keep-id, restart, all bind mounts, auto-installs dashboard palette)
- `install-dashboard.sh` — recovery script for re-installing the dashboard palette after a manual image pull
- `tunnel.cmd` — Windows shortcut that opens the tunnel and the browser

## Customising the flow

Open `http://127.0.0.1:1880` (the editor, not the dashboard) to add nodes,
change poll intervals, or add new metrics. The flows are persisted in
`/home/hermes-pi/nodered-data/flows.json` on the USB drive.

Useful nodes to add later:
- `exec` running `vcgencmd measure_temp` for an alternative temp source
- `node-red-node-pi-gpio` for pin/IO monitoring
- `node-red-node-sensehat-pi` if a Sense HAT is attached
- `e-mail` / `telegram` nodes for threshold alerts

## Security notes

- **No auth on Node-RED by default.** Combined with localhost binding, this is
  acceptable for a personal dashboard. If you ever expose 1880 to a broader
  network, enable `adminAuth` in `settings.js` (use bcrypt — not plaintext).
- **Read-only `/proc` and `/sys` mounts** are passed into the container; the
  container can read but not modify the host system.
- The container **cannot** reach the host network beyond the `127.0.0.1` port
  binding (it has no `--network host`).

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `EACCES: permission denied, copyfile` on first start | `/data` is owned by host user, container runs as `node-red` | Start with `--userns=keep-id` (already in `run.sh`) |
| `ReferenceError: require is not defined` in function node | Node-RED v3+ function nodes are sandboxed | Use the `exec` node for shell commands, parse output in a function node with safe JS only |
| `TypeError: Cannot read properties of undefined (reading 'replace')` on `ui_gauge` | `format` field missing in node config | Add `"format": "{{value}}"` to each gauge in the flow JSON |
| Dashboard palette not loaded after container restart | Global install is in the image layer, lost on image rebuild | `install-dashboard.sh` symlinks the global module into `/data/node_modules` so it survives |
| LAN browser can't reach `192.168.0.205:1880` | By design — bound to 127.0.0.1 only | Use the SSH tunnel from `tunnel.cmd` |
| Disk gauges show 0% / 0G / 0G | Bind mounts `/hostroot` (host `/`) or `/hostmnt/data` (host `/mnt/data`) not present | Re-run `./run.sh` to recreate the container with the full mount set |
| `df` inside container returns overlay numbers | Expected — container's root is overlayfs; bind mounts don't change *its* disk usage | That's why the flow uses host bind mounts and keys off block devices (not paths) |

## Related

- **[Local LLM endpoints](docs/LLM-ENDPOINTS.md)** — the three systemd-supervised
  `llama.cpp` servers on this host (incl. the one Hermes-LCM compression uses on
  `:8080`), plus the watchdog cron job that alerts Telegram if one goes down.

## License

MIT.
