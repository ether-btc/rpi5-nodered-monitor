@echo off
REM One-click Windows shortcut to open the Node-RED RPi5 monitor.
REM Edit HERMES_PI to match your Pi's LAN IP (or Tailscale IP).

set HERMES_PI=192.168.0.205
set LOCAL_PORT=1880

echo Opening Node-RED tunnel to %HERMES_PI%...
echo Keep this window open while using the dashboard.
echo Close it (or Ctrl+C) to disconnect.
echo.

start "" "http://127.0.0.1:%LOCAL_PORT%/ui"

ssh -N -L %LOCAL_PORT%:127.0.0.1:%LOCAL_PORT% hermes-pi@%HERMES_PI%
