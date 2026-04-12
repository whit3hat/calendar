# Architecture — Raspberry Pi Family Wall Calendar

## Decisions Locked In

| Decision | Choice | Reason |
|---|---|---|
| Cloud sync backend | **iCloud CalDAV** | All family members already use iPhone + Apple Calendar |
| Phone app | **Native Apple Calendar** | No new app needed — family uses this already |
| Display platform | **FullCalendar.js** (custom web app) | Full control over look and feel |
| Backend language | **Node.js + Express** | Same language as frontend, good ecosystem for ICS |
| Sync tool | **vdirsyncer** | Proven, open source, direct iCloud CalDAV support |
| Kiosk layer | **pi-kiosk + Chromium** | Automated setup, handles crash recovery |
| Primary use | **View family schedule at a glance** | Month view as default |
| Secondary use | **Add events from the Pi touchscreen** | Simple touch form, syncs to iCloud within 5 min |

**iPhone users need to do nothing differently.** Events they add or edit in Apple Calendar sync to iCloud automatically. The Pi picks them up within 5 minutes.

---

## System Diagram

```
 ┌──────────────────────────────────────────────────────────────┐
 │                     iCLOUD (Apple)                           │
 │                  caldav.icloud.com                           │
 │                                                              │
 │   Source of truth for all calendar data.                     │
 │   Family phones sync here automatically.                     │
 └────────────┬─────────────────────────────────────────────────┘
              │  vdirsyncer (CalDAV, every 5 min, bidirectional)
              │
 ┌────────────▼─────────────────────────────────────────────────┐
 │                    RASPBERRY PI                              │
 │                                                              │
 │  ┌───────────────────────────────────────────────────────┐   │
 │  │  vdirsyncer  (cron: */5 * * * *)                      │   │
 │  │  ~/.local/share/calendar/*.ics  ↔  iCloud CalDAV      │   │
 │  └───────────────────────┬───────────────────────────────┘   │
 │                          │  reads/writes .ics files          │
 │  ┌───────────────────────▼───────────────────────────────┐   │
 │  │  API Server — Node.js + Express  (:8080)              │   │
 │  │                                                       │   │
 │  │  GET  /api/events     Parse .ics → JSON for UI        │   │
 │  │  POST /api/events     New event → write to .ics       │   │
 │  └───────────────────────┬───────────────────────────────┘   │
 │                          │  HTTP (localhost)                  │
 │  ┌───────────────────────▼───────────────────────────────┐   │
 │  │  FullCalendar.js Web App  (Chromium kiosk, fullscreen) │   │
 │  │                                                       │   │
 │  │  • Month view by default (family schedule at a glance)│   │
 │  │  • Tap event → detail popover                         │   │
 │  │  • "+" button → touch form → new event saved          │   │
 │  │  • Color-coded by calendar (e.g. per family member)   │   │
 │  └───────────────────────────────────────────────────────┘   │
 └──────────────────────────────────────────────────────────────┘
              │
 ┌────────────▼─────────────────────────────────────────────────┐
 │              FAMILY iPhones (away from home)                 │
 │                                                              │
 │   Native Apple Calendar app  →  iCloud  →  Pi               │
 │                                                              │
 │   No app changes. No new accounts. No setup per phone.       │
 └──────────────────────────────────────────────────────────────┘
```

---

## One-Time Setup: iCloud App-Specific Password

Apple requires third-party tools to use an app-specific password instead of your main Apple ID password.

1. Go to [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords
2. Click **+**, label it `vdirsyncer`, copy the generated password
3. Store it in the vdirsyncer config on the Pi (see below) — your main Apple ID password is never used or stored anywhere

> **Important:** Create any new calendar folders (e.g. "Family", "Work", "Kids") from an iPhone or iCloud.com before running vdirsyncer. Once created, vdirsyncer can read and write events inside them freely. This avoids a known limitation where vdirsyncer cannot create new calendar collections on iCloud directly.

---

## vdirsyncer Configuration

`~/.config/vdirsyncer/config`:

```ini
[general]
status_path = "~/.local/share/vdirsyncer/status/"

[pair family_calendar]
a = "family_local"
b = "family_icloud"
collections = ["from a", "from b"]
conflict_resolution = "b wins"   # iCloud wins on conflict

[storage family_local]
type = "filesystem"
path = "~/.local/share/calendar/"
fileext = ".ics"

[storage family_icloud]
type = "caldav"
url = "https://caldav.icloud.com/"
username = "your@icloud.com"
password = "xxxx-xxxx-xxxx-xxxx"   # app-specific password from step above
```

**Cron job** (`crontab -e`):
```
*/5 * * * * vdirsyncer sync >> ~/.local/share/vdirsyncer/sync.log 2>&1
```

---

## API Server

Small Node.js + Express server that sits between the `.ics` files and the web UI.

**Dependencies:**
```bash
npm install express ical.js node-ical
```

**Key endpoints:**

| Method | Endpoint | What it does |
|---|---|---|
| `GET` | `/api/events` | Reads all `.ics` files, returns array of event objects as JSON |
| `POST` | `/api/events` | Accepts new event JSON, writes a new `.ics` entry to local calendar |

The frontend polls `GET /api/events` on a short interval (e.g. every 60 seconds) so new phone events appear on screen without a page reload.

---

## Frontend: FullCalendar.js

**Install:**
```bash
npm install @fullcalendar/core @fullcalendar/daygrid @fullcalendar/timegrid @fullcalendar/interaction
```

**Default view:** `dayGridMonth` — shows the full month at a glance

**Touch interactions:**
- Tap a day → opens event creation form for that date
- Tap an event → shows title, time, description in a popover
- Swipe left/right (or arrow buttons) → previous/next month

**Event creation form fields** (kept minimal for touch usability):
- Title (text input)
- Date (pre-filled from tapped day)
- Start time / End time (or all-day toggle)
- Which calendar (dropdown — populated from discovered iCloud calendars)
- Optional: Notes

---

## Data Flow

### Phone adds event (away from home)
```
1. Family member adds event in Apple Calendar on iPhone
2. iPhone syncs to iCloud immediately
3. Pi vdirsyncer cron runs (within 5 min)
4. New .ics entry written to ~/.local/share/calendar/
5. Frontend polls /api/events → new event appears on Pi display
```
**Typical delay: 0–5 minutes**

### Pi adds event (at home)
```
1. Family member taps "+" on Pi touchscreen
2. Fills touch form → taps Save
3. Frontend POSTs to /api/events
4. API server writes new .ics entry immediately
5. FullCalendar refreshes → event visible on Pi instantly
6. vdirsyncer cron runs (within 5 min) → pushes to iCloud
7. iCloud notifies iPhone → event appears in Apple Calendar
```
**Pi display: instant. iPhone: 0–5 minutes**

---

## Build Phases

### Phase 1 — Pi Setup & Sync (~2–4 hours)
- [ ] Flash Raspberry Pi OS Lite to storage (SSD recommended)
- [ ] Run pi-kiosk setup script — Chromium kiosk on boot, crash recovery
- [ ] `pip3 install vdirsyncer`
- [ ] Create iCloud app-specific password
- [ ] Configure vdirsyncer, run `vdirsyncer discover` to find calendars
- [ ] Run `vdirsyncer sync` — verify `.ics` files appear in `~/.local/share/calendar/`
- [ ] Add cron job, verify it runs every 5 min

### Phase 2 — Display (read-only first) (~1 day)
- [ ] `npm init` in project directory, install Express + ical.js
- [ ] Build `GET /api/events` endpoint — parse `.ics` files, return JSON
- [ ] Build FullCalendar month view frontend — loads events from API
- [ ] Point Chromium kiosk at `http://localhost:8080`
- [ ] **Test:** Add event in Apple Calendar on phone → verify it appears on Pi within 5 min

### Phase 3 — Event Creation (~half day)
- [ ] Build `POST /api/events` endpoint — write new `.ics` entry
- [ ] Build touch-friendly event creation modal in frontend
- [ ] **Test:** Add event on Pi → verify it appears in Apple Calendar on phone within 5 min

### Phase 4 — Polish (~1–2 days)
- [ ] Color-code events by calendar source (e.g. per family member's calendar)
- [ ] Tap-to-view event detail popover (title, time, notes)
- [ ] Scheduled display sleep (off at midnight, on at 6am — configurable)
- [ ] Auto-brightness or manual dim button for nighttime
- [ ] Handle offline gracefully (show last synced data, no error crash)

---

## Technology Summary

| Component | Technology | License | Link |
|---|---|---|---|
| OS | Raspberry Pi OS Lite | Various | [raspberrypi.com/software](https://www.raspberrypi.com/software/) |
| Kiosk setup | pi-kiosk | MIT | [github.com/geerlingguy/pi-kiosk](https://github.com/geerlingguy/pi-kiosk) |
| Calendar sync | vdirsyncer | BSD-3 | [vdirsyncer.pimutils.org](https://vdirsyncer.pimutils.org/) |
| Cloud backend | iCloud CalDAV | — | caldav.icloud.com |
| Backend API | Node.js + Express | MIT | [expressjs.com](https://expressjs.com/) |
| ICS parsing | ical.js | MIT | [github.com/kewisch/ical.js](https://github.com/kewisch/ical.js) |
| Display UI | FullCalendar.js | MIT | [fullcalendar.io](https://fullcalendar.io/) |
