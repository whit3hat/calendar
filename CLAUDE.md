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
├── scripts/
│   └── setup.sh               ← Phase 1 setup script (run on fresh Pi)
└── app/                       ← Phase 2+ Node.js calendar app (built here)
    ├── package.json
    ├── src/
    │   └── server.js          ← Express API server
    └── public/
        └── index.html         ← FullCalendar.js frontend
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

**Backend (`GET /api/events`)**
- Parse all `.ics` files in `~/.local/share/calendar/` using ical.js
- Return a JSON array of event objects (id, title, start, end, allDay, calendarName, color)

**Frontend (FullCalendar.js)**
- Default view: `dayGridMonth` — full month grid
- Current day highlighted
- Events color-coded by calendar source
- Left/right navigation arrows to move between months
- Long event titles truncate; days with overflow show "+N more"
- Auto-polls `GET /api/events` every 60 seconds — new phone events appear without page reload

**Done when:** Add event in Apple Calendar on phone → appears on Pi within 5 minutes

### Phase 3 — Event Creation from Pi
Add the ability to create events directly on the touchscreen.

**Backend (`POST /api/events`)**
- Accept event JSON, write a valid `.ics` entry to the local calendar directory
- vdirsyncer cron picks it up within 5 min and pushes to iCloud

**Frontend (touch modal)**
- Persistent "+" button always visible
- Large-touch-target form fields:
  - Title (required)
  - All-day toggle (default: on)
  - Date (pre-filled to today or tapped day; date picker)
  - Start time / End time (shown when all-day is off)
  - Which calendar (dropdown populated from discovered iCloud calendars)
  - Notes (optional)
- Save / Cancel buttons
- On save: calendar refreshes immediately; event visible on Pi right away

**Done when:** Tap "+" on Pi → event appears in Apple Calendar on phone within 5 min

### Phase 4 — Polish
- Tap an existing event → read-only detail popover (title, calendar, date/time, notes)
- Scheduled display sleep (off at midnight, on at 6am — configurable)
- Touch screen at night to wake temporarily
- Offline graceful state: show last loaded events on API failure, show "Last synced X min ago"
- No week/day view — month only for wall display use case

## What We Are NOT Building
- User login / authentication
- Editing or deleting existing events from the Pi (create only, not edit/delete)
- Push notifications
- Week or day view
- Multi-Pi sync

## Development Notes

### Running the app locally (Phase 2+)

**On the Pi** (reads real iCloud .ics files):
```bash
cd ~/calendar-app
npm install
npm start
```

**On Mac for development** (uses sample data in app/data/):
```bash
cd app
npm install
CALENDAR_DIR=./data npm start
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
