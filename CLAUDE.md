# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A physical wall-mounted family calendar with a touchscreen display, running on a Raspberry Pi. Syncs bidirectionally with Apple Calendar (iCloud) so family members can add and view events from their iPhones or directly on the wall display.

## Repository Structure

```
calendar/
├── CLAUDE.md                  ← this file
├── .gitignore
├── hardware/
│   └── options.md             ← hardware research (3 options per component)
├── software/
│   ├── options.md             ← open-source software options (all layers)
│   └── architecture.md       ← final decided architecture + data flow diagrams
├── config/
│   └── vdirsyncer.conf        ← iCloud CalDAV config TEMPLATE (no real credentials)
└── scripts/
    └── setup.sh               ← Phase 1 setup script (run on fresh Pi)
```

## Confirmed Decisions

| Area | Decision |
|---|---|
| Hardware | Raspberry Pi 5 (4GB) + 10"–21.5" capacitive IPS touchscreen |
| OS | Raspberry Pi OS Lite (64-bit) |
| Cloud sync | iCloud CalDAV — direct, no intermediary server |
| Phone app | Native Apple Calendar (no new app for family members) |
| Sync tool | vdirsyncer (polls iCloud every 5 minutes, bidirectional) |
| Display UI | FullCalendar.js (custom web app) |
| Backend API | Node.js + Express |
| ICS parsing | ical.js |
| Kiosk layer | Chromium kiosk mode (auto-start via .bash_profile + openbox) |

## Key Constraints

- **All family members use iPhone** — no Android support needed
- **No new phone apps** — users keep Apple Calendar unchanged
- **Event creation from the Pi** is required (not just display)
- **iCloud quirk** — create new calendar folders from iPhone or iCloud.com only; vdirsyncer cannot create iCloud collections but reads/writes events inside existing ones freely
- **Credential security** — real vdirsyncer config lives at `~/.config/vdirsyncer/config` on the Pi, never in this repo. `config/vdirsyncer.conf` is a template only.

## Build Phases

### Phase 1 — Pi Setup & iCloud Sync ✅ Scripted
**Script:** `scripts/setup.sh`
Run on a fresh Raspberry Pi OS Lite install. Automates:
- System update + dependency install (Node.js 22 LTS, vdirsyncer, Chromium, openbox)
- Interactive iCloud credential prompt → writes `~/.config/vdirsyncer/config`
- `vdirsyncer discover` + initial sync → `.ics` files land in `~/.local/share/calendar/`
- Cron job: `*/5 * * * *` keeps calendars in sync
- Chromium kiosk: auto-launches `http://localhost:8080` on every boot

**Outcome:** Pi has a live copy of the family's iCloud calendars refreshing every 5 min.

### Phase 2 — Calendar Display (read-only)
Build the Node.js + FullCalendar.js web app that reads `.ics` files and renders them.

- `GET /api/events` — parse `.ics` files in `~/.local/share/calendar/`, return JSON
- FullCalendar.js frontend — `dayGridMonth` (month view default)
- Chromium kiosk points at `http://localhost:8080`
- **Done when:** Add event on phone → appears on Pi within 5 minutes

### Phase 3 — Event Creation from Pi
Add the ability to create events directly on the touchscreen.

- `POST /api/events` — write new event to `.ics` file
- Touch-friendly modal: title, date, start/end time, all-day toggle, which calendar
- **Done when:** Tap "+" on Pi → event appears in Apple Calendar on phone within 5 min

### Phase 4 — Polish
- Color-code by calendar (per family member or category)
- Tap event → detail popover (title, time, notes)
- Scheduled display sleep (off at midnight, on at 6am)
- Swipe/arrow navigation between months
- Offline graceful state (show last synced data on network loss)

## Development Notes

### Running the app locally (Phase 2+)
```bash
cd ~/calendar-app
npm install
npm start          # starts Express server on :8080
```

### Manually trigger a sync
```bash
vdirsyncer sync
```

### Watch the sync log
```bash
tail -f ~/.local/share/vdirsyncer/sync.log
```

### Re-discover calendars (e.g. after a new shared calendar is added)
```bash
vdirsyncer discover family_calendar
```

### Test kiosk manually (without rebooting)
```bash
DISPLAY=:0 chromium-browser --kiosk http://localhost:8080
```

## Technology Stack

| Component | Technology | Version | Link |
|---|---|---|---|
| OS | Raspberry Pi OS Lite | latest | [raspberrypi.com/software](https://www.raspberrypi.com/software/) |
| Kiosk | Chromium + openbox | system | [geerlingguy/pi-kiosk](https://github.com/geerlingguy/pi-kiosk) |
| Calendar sync | vdirsyncer | latest | [vdirsyncer.pimutils.org](https://vdirsyncer.pimutils.org/) |
| Backend | Node.js + Express | 22.x LTS | [expressjs.com](https://expressjs.com/) |
| ICS parsing | ical.js | latest | [github.com/kewisch/ical.js](https://github.com/kewisch/ical.js) |
| Display UI | FullCalendar.js | latest | [fullcalendar.io](https://fullcalendar.io/) |
