#!/usr/bin/env bash
# Pi Zero 2 W v2 setup — Wayland + labwc + greetd kiosk
# No swap. Hardware GL via VC4 KMS. Heartbeat watchdog.
# Runs on Raspberry Pi OS Lite Bookworm/Trixie 64-bit.
#
# Idempotent: safe to re-run. Cleans up v1 artifacts (swap file, openbox
# autostart, .bash_profile startx, Firefox profile) on the way through.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

USER_NAME="${SUDO_USER:-${USER}}"
USER_HOME="$(getent passwd "${USER_NAME}" | cut -d: -f6)"
APP_DIR="${USER_HOME}/calendar-app"

BOOT_FW="/boot/firmware"
[[ -d "${BOOT_FW}" ]] || BOOT_FW="/boot"
BOOT_CONFIG="${BOOT_FW}/config.txt"
BOOT_CMDLINE="${BOOT_FW}/cmdline.txt"

log()  { echo -e "\n\033[1;34m==>\033[0m $*"; }
warn() { echo -e "\033[1;33m!!\033[0m $*" >&2; }
die()  { echo -e "\033[1;31mXX\033[0m $*" >&2; exit 1; }

[[ "${EUID}" -eq 0 ]] && die "Don't run with sudo. Re-run as the regular user; sudo is invoked when needed."

log "Pi Zero 2 W v2 setup"
echo "  User:    ${USER_NAME}"
echo "  Home:    ${USER_HOME}"
echo "  App dir: ${APP_DIR}"
echo "  Repo:    ${REPO_ROOT}"
echo "  Boot fw: ${BOOT_FW}"
echo
read -r -p "Continue? [y/N] " confirm
[[ "${confirm}" =~ ^[Yy]$ ]] || die "Aborted by user"

# -----------------------------------------------------------------------------
# Step 1 — Clean up v1 artifacts, then update + remove unwanted packages
# -----------------------------------------------------------------------------
log "Step 1/11: Cleanup v1 artifacts and remove unwanted packages"

# v1 swap file
if [[ -f /swapfile-calendar ]]; then
  warn "Removing v1 swap file /swapfile-calendar"
  sudo swapoff /swapfile-calendar 2>/dev/null || true
  sudo rm -f /swapfile-calendar
  sudo sed -i '\|/swapfile-calendar|d' /etc/fstab
fi
sudo sed -i '/^vm\.swappiness/d' /etc/sysctl.conf 2>/dev/null || true

# v1 .bash_profile startx auto-launch
if [[ -f "${USER_HOME}/.bash_profile" ]] && grep -qE 'startx|openbox' "${USER_HOME}/.bash_profile"; then
  warn "Stripping startx/openbox from ~/.bash_profile (backed up to .bash_profile.v1bak)"
  cp "${USER_HOME}/.bash_profile" "${USER_HOME}/.bash_profile.v1bak"
  sed -i '/startx/d;/openbox/d' "${USER_HOME}/.bash_profile"
fi

# v1 openbox config + Firefox profile from the failed pivot
rm -rf "${USER_HOME}/.config/openbox" "${USER_HOME}/.firefox-kiosk"

# v1 cgroup_disable=memory if we added it during debug
if grep -q 'cgroup_disable=memory' "${BOOT_CMDLINE}" 2>/dev/null; then
  warn "Removing cgroup_disable=memory from cmdline.txt"
  sudo sed -i 's/ *cgroup_disable=memory//g' "${BOOT_CMDLINE}"
fi

# System update
sudo apt update
sudo apt full-upgrade -y

# Strip unwanted packages — saves ~50MB resident at runtime.
# Notably NOT removing network-manager: doing so mid-script over SSH kills
# the user's connection before any replacement networking can be brought
# up. v2 keeps NetworkManager (~30MB cost) in exchange for SSH safety and
# standard Wi-Fi tooling (nmtui, raspi-config).
sudo apt remove -y --purge \
  bluetooth bluez bluez-firmware \
  avahi-daemon \
  modemmanager \
  dphys-swapfile \
  triggerhappy \
  plymouth plymouth-themes 2>/dev/null || true
sudo apt autoremove -y --purge

# -----------------------------------------------------------------------------
# Step 2 — Install required packages
# -----------------------------------------------------------------------------
log "Step 2/11: Install required packages"

# Node.js 22 LTS via NodeSource if not already current
if ! command -v node >/dev/null || [[ "$(node --version | sed 's/v\([0-9]*\).*/\1/')" -lt 22 ]]; then
  curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
fi

sudo apt install -y --no-install-recommends \
  greetd labwc seatd wlr-randr \
  chromium \
  nodejs \
  pipx \
  curl ca-certificates rsync \
  cron

# vdirsyncer via pipx (avoids system Python conflicts)
pipx install vdirsyncer 2>/dev/null || pipx upgrade vdirsyncer
pipx ensurepath
# Make sure the pipx bin dir applies in this script
export PATH="${USER_HOME}/.local/bin:${PATH}"

# Make sure ~/.bashrc is sourced from .bash_profile so SSH sessions inherit
# the pipx PATH (which ensurepath wrote into .bashrc)
if [[ -f "${USER_HOME}/.bash_profile" ]] && ! grep -q '\.bashrc' "${USER_HOME}/.bash_profile"; then
  echo '[ -f ~/.bashrc ] && . ~/.bashrc' >> "${USER_HOME}/.bash_profile"
fi

# -----------------------------------------------------------------------------
# Step 3 — Verify network connectivity (NetworkManager handles Wi-Fi on v2)
# -----------------------------------------------------------------------------
log "Step 3/11: Verify network connectivity"

# v2 keeps NetworkManager installed and active (see Step 1 comment for why).
# Wi-Fi is configured via the Raspberry Pi Imager's pre-flash settings, or
# manually via nmtui / raspi-config. This step just confirms there's a
# working internet path before continuing — every subsequent step needs it.
if ! ip route get 1.1.1.1 &>/dev/null; then
  warn "No network detected. NetworkManager manages Wi-Fi on v2."
  warn "Options:"
  warn "  - Configure interactively:  sudo nmtui"
  warn "  - Configure via Raspberry Pi tooling:  sudo raspi-config"
  warn "  - Re-flash the SD card with the Imager and pre-set Wi-Fi via 'Edit Settings'"
  die "Aborting until network is configured"
fi
echo "Network up: $(ip -o -4 addr show | grep -v ' lo ' | awk '{print $2, $4}')"

# -----------------------------------------------------------------------------
# Step 4 — Boot params: VC4 KMS GL + hardware watchdog
# -----------------------------------------------------------------------------
log "Step 4/11: Configure boot params (VC4 KMS + watchdog)"

ensure_config_line() {
  local file="$1" line="$2"
  if ! sudo grep -qF "${line}" "${file}"; then
    echo "${line}" | sudo tee -a "${file}" >/dev/null
  fi
}

ensure_config_line "${BOOT_CONFIG}" "dtoverlay=vc4-kms-v3d"
ensure_config_line "${BOOT_CONFIG}" "gpu_mem=64"
ensure_config_line "${BOOT_CONFIG}" "dtparam=watchdog=on"

# -----------------------------------------------------------------------------
# Step 5 — vdirsyncer + iCloud
# -----------------------------------------------------------------------------
log "Step 5/11: Configure iCloud sync via vdirsyncer"

VDIR_CONFIG_DIR="${USER_HOME}/.config/vdirsyncer"
VDIR_DATA_DIR="${USER_HOME}/.local/share/calendar"
VDIR_LOG_DIR="${USER_HOME}/.local/share/vdirsyncer"
mkdir -p "${VDIR_CONFIG_DIR}" "${VDIR_DATA_DIR}" "${VDIR_LOG_DIR}"

if [[ ! -f "${VDIR_CONFIG_DIR}/config" ]]; then
  read -r -p "Apple ID (iCloud email): " APPLE_ID
  read -r -s -p "App-specific password (https://account.apple.com → Sign-In and Security → App-Specific Passwords): " APP_PASS
  echo

  cat > "${VDIR_CONFIG_DIR}/config" <<EOF
[general]
status_path = "${USER_HOME}/.vdirsyncer/status/"

[pair family_calendar]
a = "icloud_local"
b = "icloud_remote"
collections = ["from b"]
metadata = ["color", "displayname"]
conflict_resolution = "b wins"

[storage icloud_local]
type = "filesystem"
path = "${VDIR_DATA_DIR}"
fileext = ".ics"

[storage icloud_remote]
type = "caldav"
url = "https://caldav.icloud.com/"
username = "${APPLE_ID}"
password = "${APP_PASS}"
EOF
  chmod 600 "${VDIR_CONFIG_DIR}/config"
else
  echo "Existing vdirsyncer config preserved at ${VDIR_CONFIG_DIR}/config"
fi

# vdirsyncer's `discover` will ask "Should vdirsyncer attempt to create it?"
# for every iCloud collection it finds. There's no "skip" option — saying N
# to any prompt is treated as a fatal error and aborts discover entirely.
# Auto-confirm all collections so the script can complete; the user narrows
# down which calendars actually sync via restrict-calendars.sh below.
echo
echo "vdirsyncer will now create local copies for ALL iCloud collections."
echo "(Saying N to any prompt would abort discover — auto-confirming all.)"
echo "To narrow down which calendars sync after setup, run:"
echo "    bash ${APP_DIR}/scripts/restrict-calendars.sh"
echo
# Disable pipefail just for the yes pipeline. `yes` runs forever and gets
# SIGPIPE (exit 141) when vdirsyncer closes stdin. With pipefail on, that
# 141 wins over vdirsyncer's clean 0 exit and set -e silently kills the
# script with no error message. Turning pipefail off here makes the
# pipeline return vdirsyncer's exit status, which is what we actually
# care about. Re-enable immediately after.
set +o pipefail
yes | vdirsyncer discover family_calendar
set -o pipefail
vdirsyncer sync

# Cron job for sync every 5 min (only add if not already present)
if ! crontab -l 2>/dev/null | grep -q "vdirsyncer sync"; then
  ( crontab -l 2>/dev/null; echo "*/5 * * * * ${USER_HOME}/.local/bin/vdirsyncer sync >> ${VDIR_LOG_DIR}/sync.log 2>&1" ) | crontab -
fi

# -----------------------------------------------------------------------------
# Step 6 — Install calendar app
# -----------------------------------------------------------------------------
log "Step 6/11: Install calendar app to ${APP_DIR}"

if [[ "${REPO_ROOT}" != "${APP_DIR}" ]]; then
  mkdir -p "${APP_DIR}"
  rsync -a --delete \
    --exclude='.git' --exclude='node_modules' --exclude='.DS_Store' \
    --exclude='*.bak.*' --exclude='*.v1bak' \
    "${REPO_ROOT}/" "${APP_DIR}/"
fi

cd "${APP_DIR}/app"
npm install --omit=dev

# Install calendar.service from the template
sudo sed \
  -e "s|__USER__|${USER_NAME}|g" \
  -e "s|__APP_DIR__|${APP_DIR}|g" \
  "${APP_DIR}/systemd/calendar.service" \
  | sudo tee /etc/systemd/system/calendar.service >/dev/null

sudo systemctl daemon-reload
sudo systemctl enable --now calendar.service

# -----------------------------------------------------------------------------
# Step 7 — Kiosk display stack: greetd + labwc + Chromium
# -----------------------------------------------------------------------------
log "Step 7/11: Install kiosk display stack (greetd + labwc + Chromium)"

# greetd config — autologin into labwc on vt7
sudo mkdir -p /etc/greetd
sudo tee /etc/greetd/config.toml >/dev/null <<EOF
[terminal]
vt = 7

[default_session]
command = "/usr/bin/labwc"
user = "${USER_NAME}"
EOF

# labwc per-user config
mkdir -p "${USER_HOME}/.config/labwc"
install -m 755 "${APP_DIR}/config/labwc/autostart" "${USER_HOME}/.config/labwc/autostart"
install -m 644 "${APP_DIR}/config/labwc/rc.xml"   "${USER_HOME}/.config/labwc/rc.xml"

# Some distros' seatd postinst creates a 'seat' group; Debian Trixie's
# doesn't. When greetd is the login manager (our setup), it handles seat
# permissions itself via the session abstraction, so group membership
# isn't required for labwc/Chromium to launch. Add the user to the group
# only if it exists, so the script works on either flavor of distro.
if getent group seat &>/dev/null; then
  sudo usermod -aG seat "${USER_NAME}"
fi

# Boot to graphical target (greetd will spawn labwc on vt7)
sudo systemctl enable greetd
sudo systemctl set-default graphical.target

# -----------------------------------------------------------------------------
# Step 8 — Heartbeat watchdog
# -----------------------------------------------------------------------------
log "Step 8/11: Install heartbeat watchdog"

sudo install -m 755 "${APP_DIR}/scripts/kiosk-watchdog.sh" /usr/local/bin/kiosk-watchdog.sh

for unit in kiosk-watchdog.service kiosk-watchdog.timer kiosk-reboot.service kiosk-reboot.timer; do
  sudo install -m 644 "${APP_DIR}/systemd/${unit}" "/etc/systemd/system/${unit}"
done

sudo systemctl daemon-reload
sudo systemctl enable --now kiosk-watchdog.timer
sudo systemctl enable --now kiosk-reboot.timer

# -----------------------------------------------------------------------------
# Step 9 — Runtime config on /boot/firmware (editable from any computer)
# -----------------------------------------------------------------------------
log "Step 9/11: Install runtime config to ${BOOT_FW}/calendar.env"

if [[ ! -f "${BOOT_FW}/calendar.env" ]]; then
  sudo cp "${APP_DIR}/config/calendar.env.template" "${BOOT_FW}/calendar.env"
  echo "Default calendar.env installed at ${BOOT_FW}/calendar.env"
  echo "Edit it on the SD card to customize weather location and sleep schedule."
else
  echo "Existing ${BOOT_FW}/calendar.env preserved"
fi

# -----------------------------------------------------------------------------
# Step 10 — systemd hardware watchdog (BCM2835)
# -----------------------------------------------------------------------------
log "Step 10/11: Enable systemd hardware watchdog"

sudo sed -i \
  -e 's|^#*RuntimeWatchdogSec=.*|RuntimeWatchdogSec=30s|' \
  -e 's|^#*ShutdownWatchdogSec=.*|ShutdownWatchdogSec=10min|' \
  /etc/systemd/system.conf

# Force append if patterns weren't present (fresh systemd.conf)
sudo grep -q '^RuntimeWatchdogSec' /etc/systemd/system.conf || \
  echo 'RuntimeWatchdogSec=30s' | sudo tee -a /etc/systemd/system.conf >/dev/null
sudo grep -q '^ShutdownWatchdogSec' /etc/systemd/system.conf || \
  echo 'ShutdownWatchdogSec=10min' | sudo tee -a /etc/systemd/system.conf >/dev/null

# -----------------------------------------------------------------------------
# Step 11 — Done
# -----------------------------------------------------------------------------
log "Step 11/11: Setup complete"

cat <<EOF

=== Pi Zero 2 W v2 setup complete ===

Stack installed:
  - Wayland + labwc + greetd  (boots straight to graphical.target on vt7)
  - Vanilla Chromium with native VC4 GL  (no SwiftShader, no wrapper bypass)
  - Node.js calendar app at ${APP_DIR}, served via calendar.service on :8080
  - vdirsyncer cron job syncing iCloud every 5 min
  - kiosk-watchdog.timer (60s)  -> restart kiosk if heartbeat > 5 min stale
  - kiosk-reboot.timer (5 min)  -> reboot if heartbeat > 15 min stale
  - BCM2835 hardware watchdog via systemd
  - NO swap file (intentional - see docs/V2-ARCHITECTURE.md)

Per-deployment config: ${BOOT_FW}/calendar.env
  Editable from any computer by popping the SD card.

To narrow down which iCloud calendars sync (skip Reminders, duplicates, etc.):
  bash ${APP_DIR}/scripts/restrict-calendars.sh

Reboot to start the kiosk:
  sudo reboot

Expected first-paint: 60-90s after boot.

Logs:
  sudo journalctl -u calendar.service -u greetd -u kiosk-watchdog.service -f
EOF
