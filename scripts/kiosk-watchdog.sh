#!/usr/bin/env bash
# Kiosk heartbeat watchdog
#
# The frontend pings GET /api/heartbeat every 30s; the server touches
# /dev/shm/kiosk-heartbeat on each ping. This script checks the file's
# mtime and escalates if it goes stale.
#
#   check-and-restart  — restart kiosk session (greetd) if stale > 5 min
#   check-and-reboot   — reboot if stale > 15 min (escalation tier)
#
# Both modes are invoked by separate systemd timers. The two thresholds
# are deliberately spaced (5 min vs 15 min) so the restart has 10 min
# to take effect before reboot escalation fires.

set -euo pipefail

HEARTBEAT="/dev/shm/kiosk-heartbeat"
RESTART_THRESHOLD=300    # 5 min
REBOOT_THRESHOLD=900     # 15 min

age_seconds() {
  if [[ ! -f "${HEARTBEAT}" ]]; then
    # No heartbeat yet — count from boot time so a Chromium that never
    # comes up still triggers escalation eventually.
    local boot_epoch
    boot_epoch=$(date -d "$(uptime -s)" +%s)
    echo $(( $(date +%s) - boot_epoch ))
  else
    echo $(( $(date +%s) - $(stat -c %Y "${HEARTBEAT}") ))
  fi
}

mode="${1:-check-and-restart}"
age=$(age_seconds)

case "${mode}" in
  check-and-restart)
    if (( age > RESTART_THRESHOLD )); then
      logger -t kiosk-watchdog "heartbeat ${age}s stale (>${RESTART_THRESHOLD}s) — restarting greetd"
      pkill -x chromium 2>/dev/null || true
      pkill -x chrome 2>/dev/null || true
      sleep 2
      systemctl restart greetd
      # Reset heartbeat clock so the new session has the full window
      # to come up before we'd consider restarting again.
      touch "${HEARTBEAT}"
    fi
    ;;
  check-and-reboot)
    if (( age > REBOOT_THRESHOLD )); then
      logger -t kiosk-watchdog "heartbeat ${age}s stale (>${REBOOT_THRESHOLD}s) — REBOOTING"
      systemctl reboot
    fi
    ;;
  *)
    echo "usage: $0 {check-and-restart|check-and-reboot}" >&2
    exit 2
    ;;
esac
