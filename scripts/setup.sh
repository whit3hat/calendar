#!/bin/bash
# ================================================================
# Pi Family Calendar — Phase 1 Setup (Pi Zero 2 W variant)
# ================================================================
# Tested on: Raspberry Pi OS Lite (64-bit), Pi Zero 2 W
#
# This branch targets the Pi Zero 2 W (512MB RAM, quad-core ARMv8).
# The script provisions a 1GB swap file before launching Chromium
# kiosk and passes memory-pressure flags so the browser is less
# likely to be OOM-killed under load.
#
# Prerequisites (do these before running this script):
#   - Pi is connected to WiFi or Ethernet
#   - SSH is enabled OR keyboard/monitor is attached
#   - Running as the default user (not root)
#   - An app-specific password ready from appleid.apple.com
#     → Sign-In and Security → App-Specific Passwords → +
#
# Usage:
#   bash setup.sh
#
# What this script does:
#   1. Updates the system and installs dependencies
#   2. Installs Node.js 22.x LTS
#   3. Installs vdirsyncer (iCloud CalDAV sync tool)
#   4. Configures vdirsyncer with your iCloud credentials
#   5. Discovers your iCloud calendars and runs initial sync
#   6. Sets up a 1GB swap file (Pi Zero 2 W only has 512MB RAM)
#   7. Sets up Chromium kiosk (auto-launches on every boot)
#   8. Adds a cron job to sync calendars every 5 minutes
# ================================================================

set -e  # Exit immediately on any error

# ── Colours ──────────────────────────────────────────────────
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

step()  { echo -e "\n${GREEN}${BOLD}==> $1${NC}"; }
ok()    { echo -e "${GREEN}  ✓  $1${NC}"; }
info()  { echo -e "     $1"; }
warn()  { echo -e "${YELLOW}  ⚠  $1${NC}"; }
abort() { echo -e "${RED}  ✗  $1${NC}"; exit 1; }

# ── Paths ─────────────────────────────────────────────────────
CALENDAR_DIR="$HOME/.local/share/calendar"
STATUS_DIR="$HOME/.local/share/vdirsyncer/status"
LOG_DIR="$HOME/.local/share/vdirsyncer"
VDIR_CONFIG="$HOME/.config/vdirsyncer/config"
APP_DIR="$HOME/calendar-app"
OPENBOX_CONFIG="$HOME/.config/openbox"
KIOSK_URL="http://localhost:8080"
NODE_MAJOR="22"

# ── Sanity checks ─────────────────────────────────────────────
if [ "$EUID" -eq 0 ]; then
  abort "Do not run this script as root. Run as your normal Pi user."
fi

if ! ping -c 1 8.8.8.8 &>/dev/null; then
  abort "No internet connection detected. Connect to WiFi or Ethernet first."
fi

# ── Banner ────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}Pi Family Calendar — Phase 1 Setup (Pi Zero 2 W variant)${NC}"
echo "────────────────────────────────────────────────────"
echo "This will configure your Pi as a family wall calendar."
echo "Total estimated time: 10–20 minutes."
echo ""
echo "You will be prompted for your iCloud credentials."
echo "These are stored only on this Pi, never sent anywhere else."
echo ""
read -rp "Press Enter to begin, or Ctrl+C to cancel..."

# ─────────────────────────────────────────────────────────────
# 1. SYSTEM UPDATE
# ─────────────────────────────────────────────────────────────
step "1/8  Updating system packages"
sudo apt-get update -qq
sudo apt-get upgrade -y -qq
ok "System is up to date"

# ─────────────────────────────────────────────────────────────
# 2. DEPENDENCIES
# ─────────────────────────────────────────────────────────────
step "2/8  Installing dependencies"
sudo apt-get install -y -qq \
  curl \
  git \
  gnupg \
  python3 \
  python3-venv \
  pipx \
  xserver-xorg \
  x11-xserver-utils \
  xinit \
  openbox \
  chromium \
  unclutter \
  xdotool
ok "Dependencies installed"

# Node.js
if command -v node &>/dev/null && [[ "$(node -v)" == v${NODE_MAJOR}* ]]; then
  ok "Node.js $(node -v) already installed — skipping"
else
  info "Installing Node.js ${NODE_MAJOR}.x LTS..."
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | sudo gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
  echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list > /dev/null
  sudo apt-get update -qq
  sudo apt-get install -y nodejs
  ok "Node.js $(node -v) installed"
fi

# ─────────────────────────────────────────────────────────────
# 3. VDIRSYNCER
# ─────────────────────────────────────────────────────────────
step "3/8  Installing vdirsyncer"
pipx install vdirsyncer

# Ensure ~/.local/bin is in PATH
if ! echo "$PATH" | grep -q "$HOME/.local/bin"; then
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.bashrc"
  export PATH="$HOME/.local/bin:$PATH"
fi
ok "vdirsyncer installed"

# ─────────────────────────────────────────────────────────────
# 4. CREATE DIRECTORIES
# ─────────────────────────────────────────────────────────────
step "4/8  Creating data directories"
mkdir -p \
  "$CALENDAR_DIR" \
  "$STATUS_DIR" \
  "$LOG_DIR" \
  "$APP_DIR" \
  "$OPENBOX_CONFIG" \
  "$(dirname "$VDIR_CONFIG")"
ok "Directories created"

# ─────────────────────────────────────────────────────────────
# 5. ICLOUD CONFIG + SYNC
# ─────────────────────────────────────────────────────────────
step "5/8  Configuring iCloud CalDAV"

if [ -f "$VDIR_CONFIG" ]; then
  warn "vdirsyncer config already exists — skipping credential setup."
  info "To update credentials:  nano $VDIR_CONFIG"
else
  echo ""
  echo "  ┌─────────────────────────────────────────────────────┐"
  echo "  │  iCloud App-Specific Password                       │"
  echo "  │                                                     │"
  echo "  │  1. Open https://appleid.apple.com on your phone    │"
  echo "  │  2. Sign-In and Security → App-Specific Passwords   │"
  echo "  │  3. Tap + and label it  vdirsyncer                  │"
  echo "  │  4. Copy the password shown (xxxx-xxxx-xxxx-xxxx)   │"
  echo "  └─────────────────────────────────────────────────────┘"
  echo ""
  read -rp "  iCloud email address: " ICLOUD_EMAIL
  read -rsp "  App-specific password: " ICLOUD_PASS
  echo ""

  # Write config (no variable expansion inside heredoc for password safety)
  cat > "$VDIR_CONFIG" <<EOF
[general]
status_path = "$STATUS_DIR"

[pair family_calendar]
a = "family_local"
b = "family_icloud"
collections = ["from a", "from b"]
conflict_resolution = "b wins"

[storage family_local]
type = "filesystem"
path = "$CALENDAR_DIR"
fileext = ".ics"

[storage family_icloud]
type = "caldav"
url = "https://caldav.icloud.com/"
username = "$ICLOUD_EMAIL"
password = "$ICLOUD_PASS"
EOF

  # Restrict permissions so only this user can read the credentials
  chmod 600 "$VDIR_CONFIG"
  ok "Config written (permissions: 600 — owner read/write only)"
fi

echo ""
info "Discovering iCloud calendars..."
info "If asked to create collections, type 'yes' and press Enter."
echo ""
vdirsyncer discover family_calendar || abort "Discovery failed. Check credentials in $VDIR_CONFIG and re-run this script."

info "Running initial sync..."
vdirsyncer sync || abort "Sync failed. Run 'vdirsyncer sync' manually to see the error."

ICS_COUNT=$(find "$CALENDAR_DIR" -name "*.ics" 2>/dev/null | wc -l)
ok "Initial sync complete — $ICS_COUNT .ics file(s) in $CALENDAR_DIR"

if [ "$ICS_COUNT" -eq 0 ]; then
  warn "No .ics files found. Make sure your iCloud account has at least one calendar with events."
  info "You can re-run the sync manually: vdirsyncer sync"
fi

# ─────────────────────────────────────────────────────────────
# 6. CRON JOB
# ─────────────────────────────────────────────────────────────
step "6/8  Setting up 5-minute sync cron job"
CRON_LINE="*/5 * * * * $HOME/.local/bin/vdirsyncer sync >> $LOG_DIR/sync.log 2>&1"

if crontab -l 2>/dev/null | grep -q "vdirsyncer sync"; then
  ok "Cron job already exists — skipping"
else
  (crontab -l 2>/dev/null || true; echo "$CRON_LINE") | crontab -
  ok "Cron job added (runs every 5 minutes)"
fi

# ─────────────────────────────────────────────────────────────
# 7. SWAP FILE  (Pi Zero 2 W only has 512MB RAM)
# ─────────────────────────────────────────────────────────────
# Without swap, Chromium + Node + Openbox + the OS will OOM-kill
# the browser within minutes. 1GB on the SD card is the smallest
# size we trust; raise to 2GB if you see lockups under heavy use.
step "7/8  Provisioning 1GB swap file"

SWAP_FILE="/swapfile-calendar"
SWAP_SIZE_MB=1024

if swapon --show=NAME --noheadings | grep -q "^${SWAP_FILE}$"; then
  ok "Swap file already active — skipping"
else
  if [ ! -f "$SWAP_FILE" ]; then
    info "Allocating ${SWAP_SIZE_MB}MB at $SWAP_FILE (this can take ~30s on a slow SD card)..."
    sudo fallocate -l "${SWAP_SIZE_MB}M" "$SWAP_FILE" 2>/dev/null \
      || sudo dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$SWAP_SIZE_MB" status=none
    sudo chmod 600 "$SWAP_FILE"
    sudo mkswap "$SWAP_FILE" >/dev/null
  fi
  sudo swapon "$SWAP_FILE"

  # Persist across reboots
  if ! grep -q "^${SWAP_FILE} " /etc/fstab; then
    echo "${SWAP_FILE} none swap sw 0 0" | sudo tee -a /etc/fstab >/dev/null
  fi
  ok "Swap file active and persisted in /etc/fstab"
fi

# Lower swappiness — prefer keeping pages in RAM until truly under pressure.
# 60 (default) trades performance for cache; 10 keeps Chromium snappier on Zero 2 W.
if ! grep -q "^vm.swappiness" /etc/sysctl.conf; then
  echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf >/dev/null
  sudo sysctl -q vm.swappiness=10
  ok "Swappiness set to 10 (was 60)"
fi

# ─────────────────────────────────────────────────────────────
# 8. CHROMIUM KIOSK
# ─────────────────────────────────────────────────────────────
step "8/8  Configuring Chromium kiosk"

# Openbox autostart: disable screensaver, hide cursor, launch Chromium
cat > "$OPENBOX_CONFIG/autostart" <<EOF
# Disable screen blanking and power management
xset s off
xset s noblank
xset -dpms

# Hide mouse cursor after 0.5 seconds of inactivity
unclutter -idle 0.5 -root &

# Launch Chromium in kiosk mode.
# Memory flags below are specific to the Pi Zero 2 W (512MB RAM):
#   --memory-pressure-off     — stop Chromium from auto-killing tabs at first sign
#                               of memory pressure (we only have one tab anyway)
#   --disable-dev-shm-usage   — write shm to /tmp instead of the tiny /dev/shm
#                               tmpfs that defaults to ~64MB on the Zero
#   --disable-gpu-vsync       — single-core GPU → vsync stalls compositing
#   --process-per-site        — collapse same-origin frames into one renderer
#                               process (one less ~80MB renderer)
chromium \\
  --kiosk \\
  --noerrdialogs \\
  --disable-infobars \\
  --disable-session-crashed-bubble \\
  --disable-restore-session-state \\
  --touch-events=enabled \\
  --check-for-update-interval=31536000 \\
  --memory-pressure-off \\
  --disable-dev-shm-usage \\
  --disable-gpu-vsync \\
  --process-per-site \\
  $KIOSK_URL &
EOF
ok "Openbox autostart written"

# Auto-start X on TTY1 login (only if not already in a graphical session)
BASH_PROFILE="$HOME/.bash_profile"
if ! grep -q "startx" "$BASH_PROFILE" 2>/dev/null; then
  cat >> "$BASH_PROFILE" <<'PROFILE'

# Auto-start Chromium kiosk on TTY1
if [ -z "$DISPLAY" ] && [ "$(tty)" = "/dev/tty1" ]; then
  exec startx /usr/bin/openbox-session -- -nocursor 2>/tmp/kiosk.log
fi
PROFILE
  ok ".bash_profile updated — X starts automatically on TTY1"
fi

# Enable CLI auto-login (so TTY1 logs in without a password prompt on boot)
if command -v raspi-config &>/dev/null; then
  sudo raspi-config nonint do_boot_behaviour B2 2>/dev/null
  ok "Auto-login to CLI enabled via raspi-config"
else
  warn "raspi-config not found."
  info "Enable auto-login manually: sudo systemctl edit getty@tty1"
  info "Add:  [Service]"
  info "      ExecStart="
  info "      ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM"
fi

# ── Summary ───────────────────────────────────────────────────
echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Phase 1 Complete ✓ (Pi Zero 2 W variant)${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
echo -e "  Calendars   →  $CALENDAR_DIR"
echo -e "  Sync log    →  $LOG_DIR/sync.log"
echo -e "  Kiosk URL   →  $KIOSK_URL"
echo ""
echo -e "${BOLD}Next steps:${NC}"
echo ""
echo "  Phase 2 — Build the calendar app:"
echo "    cd $APP_DIR && git clone https://github.com/whit3hat/calendar ."
echo ""
echo "  Once the app is running on :8080, test the kiosk:"
echo "    sudo reboot"
echo ""
echo "  Monitor sync activity:"
echo "    tail -f $LOG_DIR/sync.log"
echo ""
