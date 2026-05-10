# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## ⚠️ Branch: `pi-zero-2w-v2` — Wayland Rebuild

This branch is a **ground-up rebuild** of the Pi Zero 2 W variant. The original `pi-zero-2w` branch hit unresolvable swap-thrashing in field testing (load avg 9.34 with CPU at 6% — textbook I/O wait on SD card). After studying two production Pi-Zero-class kiosk projects (TOLDOTECHNIK and AnotterKiosk), the v2 stack replaces v1's choices on six axes:

| Axis | v1 (failed) | v2 (this branch) | Why v1 was wrong |
|---|---|---|---|
| Swap | 1GB SD-card swap + `vm.swappiness=10` | **No swap at all** | SD-card swap on a 512MB box is a thrashing trap, not a safety net. Without it, the kernel either fits in RAM or OOM-kills (recoverable via watchdog). |
| Display server | X11 + openbox + `.bash_profile` → `startx` | **Wayland + labwc + greetd** (real login manager) | Wayland/labwc is ~40MB lighter; greetd auto-restarts on crash; chains via systemd target instead of shell rc race. |
| GPU | `--use-gl=swiftshader` (forced software rendering) | **Native VC4 KMS hardware GL** via Wayland/Ozone | We forced software rendering to escape the Debian Chromium wrapper's `chromium.d` flag fights. Wayland/Ozone uses VC4 natively without that fight. |
| Browser | Firefox-ESR (after Chromium "failed") | **Vanilla Chromium** with `--no-memcheck --process-per-site --enable-low-end-device-mode` | Chromium's network-service crashes were a *symptom* of memory pressure, not a Chromium bug. Switching browsers used more memory and didn't address the root cause. |
| OS footprint | Default install (NetworkManager, bluetooth, avahi, ModemManager) | **Selectively stripped** — `apt remove bluetooth avahi-daemon modemmanager dphys-swapfile triggerhappy plymouth` | Saves ~50MB resident. NetworkManager kept (originally planned to remove for another ~30MB but doing so mid-script over SSH killed the first deploy — see commit 084d184). |
| Recovery | None — if browser hangs, wall stays blank until manual reboot | **Heartbeat watchdog** (kiosk-watchdog.timer every 60s; reboot escalation at 15 min) | Browsers occasionally hang on a single bad render. Recovery must not require a human walking up to the wall. |

**Full design rationale:** see `docs/V2-ARCHITECTURE.md`. **Reference projects studied:** TOLDOTECHNIK Raspberry-Pi-Kiosk-Display-System (Wayland/labwc primer) and Manawyrm AnotterKiosk (no-swap + watchdog patterns). **Status:** all v2 files written, awaiting fresh-SD-card flash and 24-hour soak test on real hardware. The original `pi-zero-2w` branch is deliberately not merged or deleted — it remains as a record of what was tried and why it failed. **`main` remains the canonical Pi 5 build.**

---

## Project Overview

A physical wall-mounted family calendar with a touchscreen display, running on a Raspberry Pi. Syncs bidirectionally with Apple Calendar (iCloud) so family members can add and view events from their iPhones or directly on the wall display.

**Current status: All six software phases are complete. The Pi Zero 2 W hardware is deployed but the v1 stack failed in field testing. v2 is the rebuild and is ready to flash; field testing pending.** Treat new bug reports as live-deployment issues, not theoretical design questions.

## Repository Structure

```
calendar/
├── CLAUDE.md                    ← this file
├── README.md                    ← public-facing project documentation
├── .gitignore
├── hardware/
│   └── options.md               ← hardware research (Pi Zero 2 W as Option D)
├── software/
│   ├── options.md               ← open-source software options (all layers)
│   └── architecture.md          ← Pi 5 architecture decisions (main branch)
├── docs/
│   ├── V2-ARCHITECTURE.md       ← v2 design rationale and rebuild plan
│   └── TROUBLESHOOTING.md       ← log locations + symptom-driven fixes
├── config/
│   ├── vdirsyncer.conf          ← iCloud CalDAV config TEMPLATE (no real credentials)
│   ├── calendar.env.template    ← runtime config copied to /boot/firmware/calendar.env
│   └── labwc/
│       ├── autostart            ← waits for :8080, launches Chromium kiosk
│       └── rc.xml               ← labwc compositor config (minimal stub)
├── scripts/
│   ├── setup.sh                 ← v2 one-shot setup (11 steps, idempotent)
│   ├── kiosk-watchdog.sh        ← restart/reboot logic for the heartbeat watchdog
│   └── restrict-calendars.sh    ← Interactive: narrow which iCloud calendars sync
├── systemd/
│   ├── calendar.service         ← Node app supervision (template, __USER__/__APP_DIR__)
│   ├── kiosk-watchdog.service   ← oneshot: pkill chromium + restart greetd if stale
│   ├── kiosk-watchdog.timer     ← fires every 60s
│   ├── kiosk-reboot.service     ← oneshot: systemctl reboot if stale > 15 min
│   └── kiosk-reboot.timer       ← fires every 5 min
└── app/                         ← Node.js calendar app
    ├── package.json
    ├── src/
    │   └── server.js            ← Express API server
    ├── public/
    │   ├── index.html           ← FullCalendar.js frontend (all UI logic)
    │   └── vendor/
    │       └── fullcalendar/    ← vendored FullCalendar v6.1.15 (no CDN at runtime)
    └── data/                    ← Sample .ics files for local Mac development
        ├── Family/
        ├── Kids/
        └── Personal/
```

## Confirmed Decisions

| Area | Decision |
|---|---|
| Hardware | Raspberry Pi Zero 2 W (512MB) + ≤1280×800 capacitive IPS touchscreen |
| OS | Raspberry Pi OS Lite Bookworm/Trixie (64-bit) |
| Display server | **Wayland** (labwc compositor, greetd login manager, vt7) |
| GPU | **Native VC4 KMS hardware GL** via Wayland/Ozone (no SwiftShader) |
| Kiosk browser | **Vanilla Chromium** with `--kiosk --no-memcheck --process-per-site --enable-low-end-device-mode --ozone-platform=wayland` |
| Networking | **NetworkManager** (kept; manage Wi-Fi via Imager pre-flash, `nmtui`, or `raspi-config`) |
| Memory | **No swap** (intentional — see V2-ARCHITECTURE.md) |
| Process supervision | systemd: `calendar.service`, `greetd.service`, `kiosk-watchdog.timer`, `kiosk-reboot.timer` + BCM2835 hardware watchdog |
| Cloud sync | iCloud CalDAV — direct, no intermediary server |
| Phone app | Native Apple Calendar (no new app for family members) |
| Sync tool | vdirsyncer (cron `*/5 * * * *`, bidirectional) |
| Display UI | FullCalendar.js v6.1.15 (vendored, served by Express static middleware) |
| Backend API | Node.js 22 LTS + Express |
| ICS parsing | node-ical |
| Runtime config | `/boot/firmware/calendar.env` (KEY=value, editable from any computer by popping the SD card) |

## Key Constraints

- **All family members use iPhone** — no Android support needed
- **No new phone apps** — users keep Apple Calendar unchanged
- **Event creation from the Pi** is required (not just display)
- **iCloud quirk** — create new calendar folders from iPhone or iCloud.com only; vdirsyncer cannot create iCloud collections but reads/writes events inside existing ones freely
- **Credential security** — real vdirsyncer config lives at `~/.config/vdirsyncer/config` on the Pi, never in this repo. `config/vdirsyncer.conf` is a template only.
- **Single timezone** — Pi and display are in the same timezone; ICS events use floating local time (no `Z` suffix)
- **No swap by design** — do not add a swap file or zram. SD-card swap is the disease v2 was designed to escape; zram on 512MB Pi is a CPU-load tradeoff that AnotterKiosk explicitly warns against.

## Build Phases

Phases 1-6 (the application layer) carry forward unchanged from v1; their behavior is identical on v2. Only the display/supervision layer is rebuilt.

### Phase 1 — Pi Setup & iCloud Sync ✅ Complete (v2 rewrite)
**Script:** `scripts/setup.sh` (11 steps, idempotent) · **Service templates:** `systemd/*.service`

Run on a fresh Raspberry Pi OS Lite install (or a Pi previously running v1 — the script cleans up v1 artifacts on the way through). Automates:
- Cleanup of v1 leftovers (swap file, `.bash_profile` startx, openbox config, Firefox profile, `cgroup_disable=memory`)
- System update + dependency install via `apt --no-install-recommends` (Node.js 22 LTS, vdirsyncer via pipx, Chromium, greetd, labwc, seatd, wlr-randr)
- Removal of Bluetooth, avahi, ModemManager, dphys-swapfile, plymouth, triggerhappy (~50MB resident saved). NetworkManager is deliberately kept — removing it mid-script over SSH killed the first deploy (commit 084d184). Wi-Fi managed via Imager pre-flash settings or `nmtui`.
- Network connectivity verification (aborts with clear instructions if Wi-Fi isn't pre-configured)
- `vc4-kms-v3d` overlay + `dtparam=watchdog=on` in `/boot/firmware/config.txt`
- Interactive iCloud credential prompt → writes `~/.config/vdirsyncer/config`
- `vdirsyncer discover` + initial sync → `.ics` files land in `~/.local/share/calendar/`
- Cron job: `*/5 * * * *` keeps calendars in sync
- `calendar.service` systemd unit: substitutes `__USER__`/`__APP_DIR__` from template, installs to `/etc/systemd/system/`, `enable --now`. Survives reboots and auto-restarts on crash. Reads optional `EnvironmentFile=-/boot/firmware/calendar.env`.
- greetd config (`/etc/greetd/config.toml`) autologs `${USER}` on vt7 → labwc compositor
- labwc autostart: polls `until curl -sf http://localhost:8080/`, then `exec chromium --kiosk --no-memcheck --process-per-site --enable-low-end-device-mode --ozone-platform=wayland`
- Heartbeat watchdog: `kiosk-watchdog.{service,timer}` (60s) restart greetd if `/dev/shm/kiosk-heartbeat` mtime > 5 min stale; `kiosk-reboot.{service,timer}` (5 min) reboots if > 15 min stale
- BCM2835 hardware watchdog enabled via `RuntimeWatchdogSec=30s` in `/etc/systemd/system.conf`
- `config/calendar.env.template` copied to `/boot/firmware/calendar.env` for SD-card-editable runtime config

### Phase 2 — Calendar Display ✅ Complete
A Node.js + FullCalendar.js web app that reads `.ics` files and renders them.

**Backend (`GET /api/events`, `GET /api/calendars`)**
- Parses all `.ics` files in `~/.local/share/calendar/` using node-ical
- Returns local ISO strings (no `Z`) for timed events to avoid timezone mismatches
- Each subdirectory in CALENDAR_DIR is a separate calendar; color-coded by name

**Frontend**
- `dayGridMonth` view — full month grid, responsive 16:9 landscape layout
- Dark theme (navy/slate palette)
- Current day highlighted with a blue circle
- Events color-coded by calendar (Family=blue, Kids=green, Personal=amber, Work=red)
- Left/right navigation; "+N more" overflow links
- Right-side day panel (open by default): shows selected day broken into hour slots with a red now-line; click any day cell to switch the panel to that day; Today button resets to current day
- Auto-polls `GET /api/events` every 5 minutes (slowed from main's 60s — single-core ARMv8 cannot afford a per-minute month-grid rerender)

### Phase 3 — Event Creation from Pi ✅ Complete
**Backend (`POST /api/events`)**
- Validates input, generates a UUID-named `.ics` file using RFC 5545-compliant ICS generation
- `foldLine()` handles 75-octet UTF-8-safe line folding; `escapeICS()` handles text escaping
- Floating local time for timed events; `VALUE=DATE` for all-day events
- Path traversal prevention via `path.basename(calendarName)`
- vdirsyncer cron picks up the new file within 5 minutes and pushes to iCloud

**Frontend (touch modal)**
- Persistent `+ Add Event` button in toolbar
- Form fields: title (required), calendar dropdown (from `GET /api/calendars`), date picker, all-day toggle, start/end time (shown when all-day is off), notes
- Start time pre-filled to next full hour (capped at 22:00 to always leave room for end)
- After save: `refetchEvents()` immediately picks up the written file
- In-app on-screen keyboard for the modal (touchscreen-only deployment, no physical keyboard expected)

### Phase 4 — Polish ✅ Complete
**Event detail popover, display sleep, touch to wake, offline graceful state.** See main `CLAUDE.md` on `main` branch for full per-feature detail; v2 inherits all of this verbatim.

### Phase 5 — Weather Widget ✅ Complete
**Backend (`GET /api/weather`)**
- Fetches current conditions and 5-day forecast from Open-Meteo (free, no API key)
- Location and units configurable via `WEATHER_LAT`, `WEATHER_LON`, `WEATHER_UNITS` env vars (set in `/boot/firmware/calendar.env` on v2); defaults to Liberty, MO in Fahrenheit
- 60-minute server-side in-memory cache on this branch (slowed from main's 15 min — single-core ARMv8)
- WMO weather code → emoji+label lookup is server-side (removes per-render lookup work from browser)

**Frontend** — see main branch for details; v2 inherits unchanged.

### Phase 6 — Event Editing & Deletion ✅ Complete
The event popover shows **Edit** and **Delete** buttons for non-recurring events. Recurring events show a "use Apple Calendar" note. Changes sync to iCloud within 5 minutes via vdirsyncer.

**Backend** — `findEventFile`, `extractPreservedVEventLines`, `PUT /api/events/:uid`, `DELETE /api/events/:uid`. See main branch for full implementation detail; v2 inherits unchanged.

**Frontend** — `editingEventUid` state, `openEditModal`, inline delete confirmation. See main branch.

### Phase 7 — v2 Display-Layer Rebuild ✅ Complete (this branch)
The Wayland + labwc + greetd + watchdog stack documented at the top of this file. See `docs/V2-ARCHITECTURE.md` for full design rationale, memory budget, boot sequence, failure modes, and rollback plan.

## What We Are NOT Building
- User login / authentication
- Editing or deleting recurring events from the Pi
- Push notifications
- Week or day view
- Multi-Pi sync
- Android support
- Read-only root filesystem with custom OS image (deferred to potential V3 hardening; AnotterKiosk-style)

## Development Notes

### Running locally on Mac (uses sample data)
```bash
cd app
npm install
CALENDAR_DIR=./data npm start
# → http://localhost:8080
# Weather widget fetches live from Open-Meteo using the hardcoded lat/lon defaults.
# Override with WEATHER_LAT / WEATHER_LON / WEATHER_UNITS if needed.
# /api/heartbeat degrades silently on macOS (no /dev/shm) — endpoint still returns 200.
```

Sample `.ics` files live in `app/data/Family/`, `app/data/Kids/`, `app/data/Personal/`.

### Running on the Pi
```bash
# calendar.service starts automatically on boot; no manual `npm start` needed.
# greetd → labwc → autostart launches Chromium kiosk on first boot after setup.sh.

# To restart the app after editing server.js:
sudo systemctl restart calendar.service

# To restart the kiosk session (kills Chromium, greetd respawns labwc + autostart):
sudo systemctl restart greetd
```

### Manually trigger a sync
```bash
vdirsyncer sync
```

### Watch logs
```bash
sudo journalctl -u calendar.service -u greetd -u kiosk-watchdog.service -f
tail -f ~/.local/share/vdirsyncer/sync.log
```

### Re-discover calendars (e.g. after a new shared calendar is added)
```bash
vdirsyncer discover family_calendar
```

### Change which iCloud calendars are synced (without re-running setup.sh)
```bash
bash scripts/restrict-calendars.sh
```
Reads existing credentials from `~/.config/vdirsyncer/config`, fetches every iCloud collection's `displayname`, prompts you to pick which ones to keep, then rewrites the config using the explicit pair form. Backs up the prior config and restarts `calendar.service` automatically.

### Test kiosk launch manually (without rebooting, on Wayland)
```bash
# From the wall display itself (or via SSH if WAYLAND_DISPLAY is exported):
chromium --kiosk --ozone-platform=wayland http://localhost:8080
```

### Verify watchdog state
```bash
# Show heartbeat file mtime + age
stat /dev/shm/kiosk-heartbeat

# Show watchdog timer status and recent runs
systemctl list-timers --all kiosk-watchdog.timer kiosk-reboot.timer
journalctl -u kiosk-watchdog.service --since "10 minutes ago"
```

## Key Implementation Details

### ICS Generation (server.js)
- `escapeICS(str)` — RFC 5545 §3.3.11 text escaping (`\`, `;`, `,`, newlines)
- `foldLine(line)` — RFC 5545 §3.1 line folding at 75 octets, UTF-8-safe walk-back
- `nextDay(dateStr)` — computes exclusive `DTEND` for all-day events
- All-day events: `DTSTART;VALUE=DATE:YYYYMMDD` + `DTEND;VALUE=DATE:YYYYMMDD+1`
- Timed events: floating local `DTSTART:YYYYMMDDTHHmmss` (no TZID, no Z)

### Calendar Colors (server.js)
Mapped by subdirectory name (case-insensitive):
```javascript
family: '#3b82f6'   // blue
kids:   '#22c55e'   // green
personal: '#f59e0b' // amber
work:   '#ef4444'   // red
// all others → '#8b5cf6' (purple)
```

### Sleep Schedule (index.html)
```javascript
const SLEEP_HOUR      = 0;      // midnight
const WAKE_HOUR       = 6;      // 6 AM
const WAKE_TIMEOUT_MS = 30000;  // 30 sec temporary wake on touch
```

### Heartbeat Watchdog (server.js + index.html + scripts/kiosk-watchdog.sh)
- Frontend `pingHeartbeat()` fetches `/api/heartbeat` once at DOMContentLoaded then every 30s via `setInterval`
- Server endpoint touches `/dev/shm/kiosk-heartbeat` with `fs.writeFileSync`; wrapped in try/catch so it degrades silently on Mac dev (no /dev/shm)
- `kiosk-watchdog.sh check-and-restart` (called by 60s timer): if mtime > 5 min stale → `pkill -x chromium && systemctl restart greetd`, then `touch` the heartbeat to give the new session a clean window
- `kiosk-watchdog.sh check-and-reboot` (called by 5 min timer, OnBootSec=15min): if mtime > 15 min stale → `systemctl reboot`
- BCM2835 hardware watchdog catches systemd itself wedging (`RuntimeWatchdogSec=30s`)
- Tier separation (5min restart vs 15min reboot) ensures the restart has 10 min to take effect before reboot escalation

### Event Editing & Deletion (server.js + index.html)
See main `CLAUDE.md` for `findEventFile()`, `extractPreservedVEventLines()`, `SEQUENCE` increment behavior, and the `isEditing`/`popoverEvent` capture-before-await frontend pattern. v2 inherits all of this verbatim.

### Weather (server.js + index.html)
- API: `https://api.open-meteo.com/v1/forecast` — no key, lat/lon only
- Open-Meteo response uses `weathercode` (no underscore) in both `current` and `daily` blocks
- Server returns: `{ enabled, current: {temp, code, icon, label}, today: {high, low}, forecast: [{date, code, icon, label, high}×4], units }`
- WMO code → emoji+label lookup is server-side (v2 carries forward this Pi-Zero-2W optimization)
- `forecast` is `daily.time.slice(1, 5)` — index 0 is today, so the 4 forecast cards are indices 1–4
- Forecast dates parsed as `day.date + 'T12:00:00'` (local noon) to get correct `getDay()` value

## Technology Stack

| Component | Technology | Version |
|---|---|---|
| OS | Raspberry Pi OS Lite Bookworm/Trixie (64-bit) | latest |
| Compositor | labwc (wlroots-based Wayland) | system |
| Login manager | greetd (autologin to labwc on vt7) | system |
| Kiosk browser | Chromium (Wayland/Ozone, native VC4 GL) | system |
| Networking | NetworkManager (default RPi OS) | system |
| Calendar sync | vdirsyncer (via pipx) | latest |
| Backend | Node.js + Express | 22.x LTS |
| ICS parsing | node-ical | latest |
| Display UI | FullCalendar.js (vendored) | 6.1.15 |
| Weather | Open-Meteo API | free / no key |
| Watchdog | bash + systemd timers + BCM2835 hwdog | system |
