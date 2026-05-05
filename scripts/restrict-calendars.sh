#!/bin/bash
# ================================================================
# Pi Family Calendar — Restrict / Reconfigure Synced Calendars
# ================================================================
# Tested on: Raspberry Pi OS Lite (64-bit), Pi Zero 2 W
#
# Use this AFTER an initial setup.sh run, any time you want to
# change which iCloud calendars get pulled down. iCloud names its
# CalDAV collections with UUIDs, so the default "discover everything"
# config drags in every calendar you can see in iPhone Calendar.
#
# This script:
#   1. Reads your existing iCloud credentials from the config
#      (so you don't have to type your app password again).
#   2. Writes a temporary "discover-everything + fetch metadata"
#      config and runs `vdirsyncer discover` + `metasync` so every
#      collection lands locally with a `displayname` file.
#   3. Shows you the friendly names ("Family", "Kids", "Work") next
#      to their UUIDs and asks which ones to keep.
#   4. Rewrites the config using the explicit pair form
#      `[[pair_name, local_name, remote_uuid], ...]` — this gives
#      you friendly local directory names ("Family") that the
#      calendar app's color map already understands.
#   5. Resets sync state, re-discovers, syncs.
#   6. Offers to delete orphaned UUID-named local folders.
#   7. Restarts calendar.service so the wall display refreshes.
#
# Run as your normal Pi user (NOT root):
#   bash scripts/restrict-calendars.sh
# ================================================================

set -euo pipefail

# ── Colours / helpers ────────────────────────────────────────
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
VDIR_CONFIG="$HOME/.config/vdirsyncer/config"
CALENDAR_DIR="$HOME/.local/share/calendar"
STATUS_DIR="$HOME/.local/share/vdirsyncer/status"
PAIR_STATUS_DIR="$STATUS_DIR/family_calendar"

# ── Sanity checks ─────────────────────────────────────────────
[ "$EUID" -eq 0 ] && abort "Do not run as root. Run as your normal Pi user."
[ -f "$VDIR_CONFIG" ] || abort "No config at $VDIR_CONFIG. Run scripts/setup.sh first."
command -v vdirsyncer >/dev/null || abort "vdirsyncer not on PATH. Did setup.sh finish?"

# ── 1. Extract credentials from existing config ──────────────
# We rewrite the file from scratch later, so we have to recover
# the iCloud email and app-specific password first. Anchored regex
# avoids matching commented examples elsewhere in the file.
ICLOUD_EMAIL=$(grep -E '^username[[:space:]]*=' "$VDIR_CONFIG" | head -1 | sed -E 's/^username[[:space:]]*=[[:space:]]*"(.*)"[[:space:]]*$/\1/')
ICLOUD_PASS=$(grep -E '^password[[:space:]]*=' "$VDIR_CONFIG" | head -1 | sed -E 's/^password[[:space:]]*=[[:space:]]*"(.*)"[[:space:]]*$/\1/')

[ -z "${ICLOUD_EMAIL:-}" ] && abort "Could not parse 'username' from $VDIR_CONFIG"
[ -z "${ICLOUD_PASS:-}" ]  && abort "Could not parse 'password' from $VDIR_CONFIG"
ok "Loaded credentials for $ICLOUD_EMAIL"

# Backup the existing config in case anything goes wrong.
BACKUP="$VDIR_CONFIG.bak.$(date +%s)"
cp "$VDIR_CONFIG" "$BACKUP"
chmod 600 "$BACKUP"
ok "Backed up existing config to $BACKUP"

write_config() {
  # write_config <collections-array-contents>
  # The argument is the inside of `collections = [...]` — either
  # the wildcard form `"from a", "from b"` or an explicit triplet
  # list `["fam", "Family", "<uuid>"], ...`.
  local collections="$1"
  cat > "$VDIR_CONFIG" <<EOF
[general]
status_path = "$STATUS_DIR"

[pair family_calendar]
a = "family_local"
b = "family_icloud"
collections = [$collections]
conflict_resolution = "b wins"
metadata = ["displayname", "color"]

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
  chmod 600 "$VDIR_CONFIG"
}

# ── 2. Wildcard discover + metasync to populate displaynames ──
step "Discovering all iCloud calendars (read-only metadata fetch)"
write_config '"from a", "from b"'
rm -rf "$PAIR_STATUS_DIR"

# `yes yes` answers every "Create collection?" prompt with the literal
# string "yes" (vdirsyncer requires the full word, not just "y").
yes yes | vdirsyncer discover family_calendar || abort "discover failed — check credentials and network."
vdirsyncer metasync family_calendar || warn "metasync had issues — displaynames may be incomplete."

# ── 3. Build UUID → displayname map from local directories ───
step "Available calendars on this iCloud account"

declare -a UUIDS=()
declare -a NAMES=()
i=1
for d in "$CALENDAR_DIR"/*/; do
  [ -d "$d" ] || continue
  uuid=$(basename "$d")
  if [ -f "$d/displayname" ]; then
    name=$(tr -d '\n\r' < "$d/displayname")
  else
    name="(no displayname)"
  fi
  UUIDS+=("$uuid")
  NAMES+=("$name")
  printf "  %2d. %-30s  %s\n" "$i" "$name" "$uuid"
  i=$((i+1))
done

[ "${#UUIDS[@]}" -eq 0 ] && abort "No calendars discovered. Run 'vdirsyncer sync' manually to debug."

# ── 4. Prompt the user for selection ─────────────────────────
echo ""
echo "Enter the numbers of calendars to KEEP, separated by spaces (e.g. 1 3):"
read -rp "  > " -a SELECTIONS

[ "${#SELECTIONS[@]}" -eq 0 ] && abort "No selection — aborting (your old config is restored from backup)."

# Validate selections, build pair triplets, and track which local
# names we will end up using (for the cleanup step).
declare -a PAIR_LITERALS=()
declare -A KEEP_LOCAL_NAMES=()

for n in "${SELECTIONS[@]}"; do
  if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ] || [ "$n" -gt "${#UUIDS[@]}" ]; then
    abort "Invalid selection: $n"
  fi
  idx=$((n-1))
  uuid="${UUIDS[$idx]}"
  raw_name="${NAMES[$idx]}"

  # Sanitize the displayname into a safe filesystem name.
  # Strip everything except alphanumerics / dash / underscore / space,
  # then collapse spaces to underscores. Fall back to the UUID if
  # the displayname has nothing usable in it.
  safe=$(printf '%s' "$raw_name" | tr -cd 'A-Za-z0-9 _-' | tr -s ' ' | sed 's/^ //; s/ $//' | tr ' ' '_')
  [ -z "$safe" ] && safe="$uuid"

  # Detect collisions (two calendars sharing a displayname). Append
  # a short UUID suffix to keep them distinct.
  if [ -n "${KEEP_LOCAL_NAMES[$safe]:-}" ]; then
    safe="${safe}_${uuid:0:8}"
  fi
  KEEP_LOCAL_NAMES["$safe"]=1

  # vdirsyncer's explicit pair form: [pair_collection_name, name_on_a, name_on_b]
  PAIR_LITERALS+=("[\"$safe\", \"$safe\", \"$uuid\"]")
  info "Will sync: \"$raw_name\"  →  ~/.local/share/calendar/$safe/"
done

# ── 5. Rewrite config with explicit pair list ────────────────
step "Writing final config with explicit pair list"
COLLECTIONS_VALUE=$(IFS=, ; echo "${PAIR_LITERALS[*]}")
write_config "$COLLECTIONS_VALUE"
ok "Config updated"

# ── 6. Reset status and re-sync against the new config ───────
# Clearing the pair status directory prevents vdirsyncer from
# carrying over state about calendars that are no longer in the
# config — without this, sync can complain about "unknown collection".
step "Re-discovering and syncing the chosen calendars"
rm -rf "$PAIR_STATUS_DIR"
yes yes | vdirsyncer discover family_calendar || abort "discover failed against new config."
vdirsyncer sync || abort "sync failed — check ~/.local/share/vdirsyncer/sync.log"
vdirsyncer metasync family_calendar || warn "metasync warnings (non-fatal)."
ok "Sync complete"

# ── 7. Offer to remove orphaned UUID-named directories ───────
step "Checking for orphaned local calendar folders"
declare -a ORPHANS=()
for d in "$CALENDAR_DIR"/*/; do
  [ -d "$d" ] || continue
  base=$(basename "$d")
  if [ -z "${KEEP_LOCAL_NAMES[$base]:-}" ]; then
    ORPHANS+=("$base")
  fi
done

if [ "${#ORPHANS[@]}" -eq 0 ]; then
  ok "Nothing to clean up."
else
  echo ""
  echo "These local folders are no longer in your sync list:"
  for o in "${ORPHANS[@]}"; do echo "    $o"; done
  echo ""
  warn "Deleting them only removes the local cache — your iCloud copies are untouched."
  read -rp "  Delete? (y/N) " yn
  if [[ "$yn" =~ ^[Yy]$ ]]; then
    for o in "${ORPHANS[@]}"; do rm -rf "${CALENDAR_DIR:?}/$o"; done
    ok "Removed ${#ORPHANS[@]} orphaned folder(s)."
  else
    info "Skipped — delete later with: rm -rf ~/.local/share/calendar/<folder>"
  fi
fi

# ── 8. Restart calendar.service so the wall display picks up ─
# the new directory layout immediately (instead of waiting up to
# 5 minutes for the next event poll cycle).
if systemctl is-active --quiet calendar.service 2>/dev/null; then
  step "Restarting calendar.service"
  sudo systemctl restart calendar.service
  ok "calendar.service is now $(systemctl is-active calendar.service)"
fi

echo ""
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo -e "${GREEN}${BOLD}  Done ✓${NC}"
echo -e "${GREEN}${BOLD}════════════════════════════════════════${NC}"
echo ""
echo "Refresh http://localhost:8080 to see the change."
echo "Backup of previous config:  $BACKUP"
echo "Live sync log:              tail -f ~/.local/share/vdirsyncer/sync.log"
