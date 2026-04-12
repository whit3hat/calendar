# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A physical wall-mounted family calendar with a touchscreen display, running on a Raspberry Pi. Syncs bidirectionally with Apple Calendar (iCloud) so family members can add and view events from their iPhones or directly on the wall display.

**Current status: All six phases are complete.** Hardware is on order. Next step is deploying to the Pi when it arrives.

## Repository Structure

```
calendar/
├── CLAUDE.md                  ← this file
├── README.md                  ← public-facing project documentation
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
└── app/                       ← Node.js calendar app
    ├── package.json
    ├── src/
    │   └── server.js          ← Express API server
    ├── public/
    │   └── index.html         ← FullCalendar.js frontend (all UI logic)
    └── data/                  ← Sample .ics files for local Mac development
        ├── Family/
        ├── Kids/
        └── Personal/
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
| ICS parsing | node-ical |
| Kiosk layer | Chromium kiosk mode (auto-start via .bash_profile + openbox) |

## Key Constraints

- **All family members use iPhone** — no Android support needed
- **No new phone apps** — users keep Apple Calendar unchanged
- **Event creation from the Pi** is required (not just display)
- **iCloud quirk** — create new calendar folders from iPhone or iCloud.com only; vdirsyncer cannot create iCloud collections but reads/writes events inside existing ones freely
- **Credential security** — real vdirsyncer config lives at `~/.config/vdirsyncer/config` on the Pi, never in this repo. `config/vdirsyncer.conf` is a template only.
- **Single timezone** — Pi and display are in the same timezone; ICS events use floating local time (no `Z` suffix)

## Build Phases

### Phase 1 — Pi Setup & iCloud Sync ✅ Complete
**Script:** `scripts/setup.sh`
Run on a fresh Raspberry Pi OS Lite install. Automates:
- System update + dependency install (Node.js 22 LTS, vdirsyncer, Chromium, openbox)
- Interactive iCloud credential prompt → writes `~/.config/vdirsyncer/config`
- `vdirsyncer discover` + initial sync → `.ics` files land in `~/.local/share/calendar/`
- Cron job: `*/5 * * * *` keeps calendars in sync
- Chromium kiosk: auto-launches `http://localhost:8080` on every boot

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
- Auto-polls `GET /api/events` every 60 seconds

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

### Phase 4 — Polish ✅ Complete
**Event detail popover**
- Tapping any event opens a read-only popover near the tap position
- Shows: calendar color dot, title, calendar name, formatted date/time, notes (if any)
- Smart positioning: flips left or above if it would overflow the viewport
- Dismissed via X, tap outside, or Escape key

**Display sleep**
- Full-screen black overlay activates at `SLEEP_HOUR` (default 0 = midnight) and lifts at `WAKE_HOUR` (default 6 = 6 AM)
- Constants at top of script are easy to change
- `isSleepTime()` supports wrap-around-midnight windows (e.g. SLEEP_HOUR=23, WAKE_HOUR=7)

**Touch to wake**
- Tapping the sleep overlay dismisses it for `WAKE_TIMEOUT_MS` (30 seconds) then re-sleeps
- `goToSleep()` clears/nulls `wakeTimer` unconditionally before the guard to prevent stale timer IDs from breaking future sleep cycles

**Offline graceful state**
- On `GET /api/events` failure, `allEvents` is not cleared — the last loaded events remain visible
- Status bar turns red: "Could not reach server — showing last loaded data"
- On success, status bar shows "Last updated: just now" / "Last updated: N minutes ago" (refreshes every 30 seconds)

### Phase 5 — Weather Widget ✅ Complete
**Backend (`GET /api/weather`)**
- Fetches current conditions and 5-day forecast from Open-Meteo (free, no API key)
- Location and units configurable via `WEATHER_LAT`, `WEATHER_LON`, `WEATHER_UNITS` env vars; defaults to Liberty, MO in Fahrenheit
- 15-minute server-side in-memory cache — the Pi makes at most 4 outbound fetches per hour
- On fetch failure, serves stale cache indefinitely; returns 503 only if cache is cold

**Frontend**
- Weather strip rendered in day panel between the date header and all-day section
- Strip is hidden (`display: none`) until first successful fetch — graceful if no network
- Shows: WMO emoji icon + current temp + condition label + today high/low + 4-day forecast cards (day abbr + icon + high)
- `loadWeather()` called on DOMContentLoaded and then every 15 minutes via `setInterval`
- WMO code → emoji/label lookup via `WMO_CODES` map (covers all 30 standard WMO interpretation codes); unmapped codes fall back to `🌡️ Unknown`
- Forecast date strings parsed as `'T12:00:00'` (local noon) to prevent UTC-midnight timezone shifts on day-of-week label

### Phase 6 — Event Editing & Deletion ✅ Complete
The event popover now shows **Edit** and **Delete** buttons for non-recurring events. Recurring events show a "use Apple Calendar" note instead. Changes sync to iCloud within 5 minutes via vdirsyncer.

**Backend**
- `findEventFile(uid)` — scans all CALENDAR_DIR subdirectories, parsing each `.ics` until it finds the matching `component.uid`. Returns `{ filePath, calendarName, component }` or null.
- `extractPreservedVEventLines(rawContent)` — unfolds RFC 5545 continuation lines, then extracts every VEVENT property that the app does NOT manage (`VALARM` blocks, `X-APPLE-*`, `ORGANIZER`, attendees, etc.) so they survive an edit without being stripped.
- `PUT /api/events/:uid` — validates input; returns 422 if `component.rrule` is present; reads and preserves unknown ICS fields; increments `SEQUENCE`; re-folds preserved lines via `foldLine()`; handles calendar moves atomically (write new file first, then unlink old — prefer duplicate over data loss).
- `DELETE /api/events/:uid` — returns 422 if recurring; deletes the `.ics` file; vdirsyncer propagates the deletion to iCloud.
- `loadEvents()` sets `isRecurring: !!component.rrule` on each event's `extendedProps`.

**Frontend**
- `editingEventUid` state (`null` = add mode, UID string = edit mode) and `popoverEvent` state (the FC event object while the popover is open).
- `openEditModal(fcEvent)` — sets `editingEventUid`, updates modal title/button text, pre-fills all form fields. Date uses `localDateString()` (not `toISOString()`) to avoid UTC-midnight timezone shift on the Pi.
- `populateCalendarSelect(selectedCalendar)` — optional parameter pre-selects the event's current calendar.
- `handleFormSubmit()` — branches on `editingEventUid`: POSTs to `/api/events` when null, PUTs to `/api/events/:uid` when set. Captures `isEditing` before the `await` so the `finally` button text is correct even after `closeModal()` nulls `editingEventUid`.
- Edit button listener captures `popoverEvent` into a local variable *before* calling `closeEventPopover()` (which nulls it), then passes it to `openEditModal()`.
- Delete confirmation is inline within the popover (not a second modal) — better for touchscreen UX. Error on delete is shown in the confirm-text area with a Retry button.

## What We Are NOT Building
- User login / authentication
- Editing or deleting recurring events from the Pi
- Push notifications
- Week or day view
- Multi-Pi sync
- Android support

## Development Notes

### Running locally on Mac (uses sample data)
```bash
cd app
npm install
CALENDAR_DIR=./data npm start
# → http://localhost:8080
# Weather widget fetches live from Open-Meteo using the hardcoded lat/lon defaults
# Override with WEATHER_LAT / WEATHER_LON / WEATHER_UNITS if needed
```

Sample `.ics` files live in `app/data/Family/`, `app/data/Kids/`, `app/data/Personal/`.

### Running on the Pi (reads real iCloud .ics files)
```bash
cd ~/calendar-app
npm install
npm start
# Chromium kiosk opens automatically on boot via .bash_profile → openbox → autostart
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

### Event Editing & Deletion (server.js + index.html)
- `findEventFile(uid)` — O(n) scan of all .ics files; fine for household calendar sizes
- `extractPreservedVEventLines()` — unfolds physical lines → logical lines first (RFC 5545 §3.1 continuation = leading SP/HT); then depth-tracks `BEGIN:`/`END:` pairs so entire `VALARM` sub-components are preserved as a block
- Managed set: `UID`, `DTSTAMP`, `DTSTART`, `DTEND`, `SUMMARY`, `DESCRIPTION`, `SEQUENCE` — these are rewritten from the form; everything else is preserved verbatim
- Preserved lines are re-folded through `foldLine()` before writing — they were unfolded during extraction, so this round-trip is required
- `SEQUENCE` incremented: `(parseInt(component.sequence || '0', 10) || 0) + 1`
- Calendar move is atomic: `writeFileSync(newPath)` then `unlinkSync(oldPath)` — never the reverse
- Frontend: `isEditing` captured before the `await` in `handleFormSubmit()` because `closeModal()` on success sets `editingEventUid = null` before the `finally` block runs
- The edit button listener must capture `popoverEvent` into a local `const ev` before `closeEventPopover()` (which sets `popoverEvent = null`) then pass `ev` to `openEditModal(ev)`

### Weather (server.js + index.html)
- API: `https://api.open-meteo.com/v1/forecast` — no key, lat/lon only
- Open-Meteo response uses `weathercode` (no underscore) in both `current` and `daily` blocks
- Server returns: `{ enabled, current: {temp, code}, today: {high, low}, forecast: [{date, code, high}×4], units }`
- `forecast` is `daily.time.slice(1, 5)` — index 0 is today, so the 4 forecast cards are indices 1–4
- Client `WMO_CODES` map is keyed by integer WMO code; `wmoInfo(code)` returns `{ icon, label }`
- Forecast dates parsed as `day.date + 'T12:00:00'` (local noon) to get correct `getDay()` value

## Technology Stack

| Component | Technology | Version |
|---|---|---|
| OS | Raspberry Pi OS Lite (64-bit) | latest |
| Kiosk | Chromium + openbox | system |
| Calendar sync | vdirsyncer | latest |
| Backend | Node.js + Express | 22.x LTS |
| ICS parsing | node-ical | latest |
| Display UI | FullCalendar.js | 6.1.15 |
| Weather | Open-Meteo API | free / no key |
