# 📅 Pi Family Calendar

> A wall-mounted, touchscreen family calendar that syncs bidirectionally with Apple Calendar — built on a Raspberry Pi, powered by iCloud CalDAV, and designed to live on your wall forever.

No subscriptions. No new apps for your family. No cloud middlemen. Just a Pi on your wall that stays in perfect sync with the Apple Calendar your family already uses. 🏡

---

## ✨ What It Does

- 🗓️ **Displays your family's iCloud calendars** on a beautiful dark-themed full-month grid
- ➕ **Create new events from the touchscreen** — they appear on everyone's iPhone within 5 minutes
- 👆 **Tap any event** to see details — and soon, **edit or delete it** right from the wall
- 📋 **Day panel** slides out from the right showing the selected day broken into hourly slots with a live "now" line
- 🌤️ **Live weather** in the day panel — current conditions, today's high/low, and a 4-day forecast (no API key needed)
- 🌙 **Auto-sleeps at midnight** and wakes at 6 AM — touch the screen at night to temporarily wake it
- 📡 **Offline graceful** — shows last loaded events and a "last synced X min ago" status if the server is unreachable
- 🎨 **Color-coded calendars** (Family=blue, Kids=green, Personal=amber, Work=red)

---

## 📸 Feature Overview

```
┌──────────────────────────────────────────────────┬────────────────┐
│  ◀  ▶   Today   April 2026              + Add Event│  Sunday, Apr 12│
├──────────────────────────────────────────────────┤  ⛅ 68°F Partly │
│  SUN   MON   TUE   WED   THU   FRI   SAT         │  Cloudy         │
│                     1     2     3     4           │  ↑ 71°  ↓ 64°  │
│   5     6     7     8     9    10    11           │  Mon⛈ Tue⛈ Wed🌧│
│  12    13    14    15    16    17    18           ├────────────────┤
│  ●26   ●Soccer ●Dentist ...                      │  All Day        │
│  ...                                             │  ┌────────────┐ │
│                                                  │  │ 🎉 Birthday│ │
│                                                  │  └────────────┘ │
│                                                  │  10 AM          │
│                                                  │  ● Dentist Appt │
│                                                  │  ── now ──      │
└──────────────────────────────────────────────────┴────────────────┘
```

---

## 🛠️ Hardware

| Component | Recommended | Notes |
|-----------|------------|-------|
| 🖥️ **Single-board computer** | Raspberry Pi 5 (4GB) | Pi 4 also works |
| 📺 **Display** | 10"–21.5" capacitive IPS touchscreen | HDMI + USB touch; portrait or landscape |
| 🔌 **Power** | Official Pi 5 USB-C PSU (27W) | Stable power = stable kiosk |
| 💾 **Storage** | 32GB+ A2-rated microSD | Faster boot, better reliability |
| 🧲 **Mounting** | VESA mount + wall bracket | Or a picture frame, or just some tape |

**All family members need to use iPhone** (iCloud sync is Apple-only). If you have a mixed Android/iPhone household, this project is not a good fit.

---

## 🧱 Software Stack

| Layer | Technology |
|-------|-----------|
| OS | Raspberry Pi OS Lite 64-bit |
| Kiosk | Chromium + Openbox (auto-launches on boot) |
| iCloud sync | [vdirsyncer](https://vdirsyncer.pimutils.org/) — bidirectional CalDAV |
| Backend | Node.js 22 LTS + Express |
| ICS parsing | node-ical |
| Calendar UI | [FullCalendar.js](https://fullcalendar.io/) v6 |

---

## 📁 Repository Structure

```
calendar/
├── README.md                  ← you are here
├── CLAUDE.md                  ← AI assistant context (ignore this)
├── .gitignore
│
├── hardware/
│   └── options.md             ← hardware research notes
│
├── software/
│   ├── options.md             ← software options considered
│   └── architecture.md       ← architecture decisions + data flow
│
├── config/
│   └── vdirsyncer.conf        ← iCloud CalDAV config TEMPLATE
│                                 (copy to ~/.config/vdirsyncer/config on the Pi)
│
├── scripts/
│   └── setup.sh               ← one-shot Pi setup script
│
└── app/                       ← the calendar web app
    ├── package.json
    ├── src/
    │   └── server.js          ← Express API (reads .ics files, writes new events)
    ├── public/
    │   └── index.html         ← all frontend UI (FullCalendar + day panel + modals)
    └── data/                  ← sample .ics files for local Mac development
        ├── Family/
        ├── Kids/
        └── Personal/
```

---

## 🚀 Getting Started

### Prerequisites

Before you begin, you'll need:

1. **A Raspberry Pi** (Pi 4 or Pi 5) with a fresh install of **Raspberry Pi OS Lite (64-bit)**
2. **A touchscreen display** connected via HDMI + USB
3. **An iCloud App-Specific Password** — generate one at [appleid.apple.com](https://appleid.apple.com) → Sign-In and Security → App-Specific Passwords
4. **At least one calendar** already set up in Apple Calendar on your iPhone (iCloud can't create new calendar folders from vdirsyncer — only from an iPhone or iCloud.com)

> 💡 **Not sure what an App-Specific Password is?** It's a special one-time password Apple lets you generate for third-party apps that need to access iCloud. Your real Apple ID password never leaves Apple's servers.

---

### Step 1 — Clone the repo onto the Pi

SSH into your Pi or open a terminal:

```bash
cd ~
git clone https://github.com/whit3hat/calendar.git calendar-app
cd calendar-app
```

---

### Step 2 — Run the setup script

```bash
bash scripts/setup.sh
```

This single script handles everything for Phase 1:

- ✅ Updates the system and installs all dependencies (Node.js 22, vdirsyncer, Chromium, Openbox)
- ✅ Prompts you for your iCloud email and app-specific password
- ✅ Writes `~/.config/vdirsyncer/config` (permissions `600` — only you can read it)
- ✅ Discovers your iCloud calendars and runs the first sync
- ✅ Sets up a cron job to sync every 5 minutes
- ✅ Configures Chromium to launch in kiosk mode automatically on every boot

The script takes 10–20 minutes on a fresh Pi. Grab a coffee. ☕

---

### Step 3 — Start the calendar app

```bash
cd ~/calendar-app/app
npm install
npm start
```

The server starts on `http://localhost:8080`. On the next reboot, Chromium will open it automatically in fullscreen kiosk mode.

To test the kiosk without rebooting:

```bash
DISPLAY=:0 chromium-browser --kiosk http://localhost:8080
```

---

### Step 4 — Add it to the wall 🧱

Mount the Pi and display, plug everything in, and reboot. That's it. The kiosk launches automatically, your iCloud events appear within 5 minutes, and your family can start using it from day one — no training required.

---

## 📂 Where Files Live on the Pi

| Path | What's there |
|------|-------------|
| `~/calendar-app/` | The cloned repo / app root |
| `~/calendar-app/app/` | Node.js app (`npm start` runs from here) |
| `~/.config/vdirsyncer/config` | Your iCloud credentials (**never in this repo**) |
| `~/.local/share/calendar/` | Synced `.ics` files (one subdirectory per calendar) |
| `~/.local/share/vdirsyncer/sync.log` | Live sync log |
| `~/.config/openbox/autostart` | Kiosk startup script |

---

## 🔧 Useful Commands

```bash
# Manually trigger an iCloud sync right now
vdirsyncer sync

# Watch the sync log in real time
tail -f ~/.local/share/vdirsyncer/sync.log

# Re-discover calendars after adding a new one in Apple Calendar
vdirsyncer discover family_calendar

# Check how many .ics events are synced locally
find ~/.local/share/calendar -name "*.ics" | wc -l

# Restart the calendar server
pkill -f "node src/server.js" && npm start &

# Test kiosk mode without rebooting
DISPLAY=:0 chromium-browser --kiosk http://localhost:8080
```

---

## 💻 Local Development (Mac)

You don't need a Pi to develop on this project. Sample `.ics` files in `app/data/` simulate real calendar data:

```bash
cd app
npm install
CALENDAR_DIR=./data npm start
# Open http://localhost:8080
```

The `CALENDAR_DIR` environment variable tells the server where to look for `.ics` files. On the Pi this defaults to `~/.local/share/calendar/`. Locally it points to the sample data folder.

---

## ⚙️ Configuration

### Calendar Colors

Colors are assigned by subdirectory (calendar) name in `app/src/server.js`:

```javascript
const CALENDAR_COLORS = {
  family:   '#3b82f6',  // 🔵 blue
  kids:     '#22c55e',  // 🟢 green
  personal: '#f59e0b',  // 🟡 amber
  work:     '#ef4444',  // 🔴 red
};
// Any unlisted calendar → purple (#8b5cf6)
```

### Weather

The weather strip in the day panel pulls from [Open-Meteo](https://open-meteo.com/) — completely free, no API key, no account. Just set your coordinates and you're done.

Configure location and units via environment variables (or edit the defaults directly in `app/src/server.js`):

```bash
# In your npm start command, or in the systemd service, or .bash_profile:
WEATHER_LAT=39.3392 WEATHER_LON=-94.2261 WEATHER_UNITS=fahrenheit npm start

# Celsius household? Just change the unit:
WEATHER_UNITS=celsius npm start
```

The server caches the forecast for 15 minutes so the Pi isn't hammering an external API on every page load. If Open-Meteo is unreachable, the last successful forecast stays on screen until the connection comes back.

**Default values** (edit `app/src/server.js` if you don't want env vars):
```javascript
const WEATHER_LAT   = 39.3392;        // Liberty, MO — change to your location
const WEATHER_LON   = -94.2261;
const WEATHER_UNITS = 'fahrenheit';   // or 'celsius'
```

> 🌍 **Finding your coordinates:** Google Maps → right-click your house → the first number is lat, the second is lon. West longitudes are negative.

### Sleep Schedule

The display sleeps automatically at night. Defaults are in `app/public/index.html`:

```javascript
const SLEEP_HOUR      = 0;      // display goes dark at midnight
const WAKE_HOUR       = 6;      // display wakes at 6 AM
const WAKE_TIMEOUT_MS = 30000;  // touch to wake stays awake for 30 seconds
```

Change these three numbers to whatever fits your household. Wrap-around midnight windows work too (e.g. `SLEEP_HOUR=22, WAKE_HOUR=7`).

### iCloud Sync Frequency

Edit the cron job to change how often calendars sync:

```bash
crontab -e
# Default: */5 * * * * (every 5 minutes)
# Change to */2 for every 2 minutes, etc.
```

---

## 🔒 Security Notes

- **Your iCloud credentials are stored only on the Pi** at `~/.config/vdirsyncer/config` with `chmod 600`. They are never committed to this repository.
- This app has **no authentication layer** — it's designed for a home LAN where the Pi is not exposed to the internet.
- The `POST /api/events` endpoint validates calendar names using `path.basename()` to prevent directory traversal attacks.
- All event content displayed in the UI uses `textContent` (not `innerHTML`) wherever possible; where `innerHTML` is used, content is escaped through an `esc()` helper.

---

## 🤔 FAQ

**Q: Can I use this with Google Calendar?**
Not without modifications. The sync layer (vdirsyncer) supports Google CalDAV in principle, but the setup and auth flow is different. This project was built and tested against iCloud only.

**Q: Can multiple people create events from the Pi at the same time?**
The server is single-user by design — it's a wall display for a household, not a multi-user system. Simultaneous saves are unlikely in practice.

**Q: What happens if the Pi loses internet?**
vdirsyncer will fail silently and retry on the next 5-minute cycle. The calendar app continues to show the last successfully synced events. The status bar shows how long ago the last successful sync was.

**Q: Can I add a Work calendar?**
Yes! Create the calendar in Apple Calendar on your iPhone, then run `vdirsyncer discover family_calendar` on the Pi to pick it up. It'll automatically get the red color (or purple if you name it differently).

**Q: The screen isn't sleeping at night. What do I do?**
Check that the Pi's own DPMS (Display Power Management) isn't overriding the software overlay. The `setup.sh` script disables DPMS (`xset -dpms`) so that the web app has full control. If you want true hardware sleep (backlight off), look into `xset dpms force off` called from the server.

---

## 🗺️ Roadmap

Five phases are complete and running in production. Phase 6 is in active development:

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Pi setup, iCloud sync, kiosk boot | ✅ Done |
| 2 | Month view calendar display, day panel | ✅ Done |
| 3 | Event creation from touchscreen | ✅ Done |
| 4 | Event detail popover, sleep/wake, offline state | ✅ Done |
| 5 | Live weather widget in day panel | ✅ Done |
| 6 | Edit and delete events from the Pi | 🚧 In Progress |

### Phase 6 — Event Editing & Deletion

Tapping an event will soon show **Edit** and **Delete** buttons alongside the read-only details. Changes sync back to iCloud within 5 minutes via vdirsyncer — same as event creation.

**Scope:**
- ✅ Edit title, date, time, calendar, and notes on any standard event
- ✅ Delete any standard event with a single tap + confirmation
- ⏭️ **Recurring events are read-only** — editing "just this occurrence" vs "all occurrences" is genuinely complex and best done in Apple Calendar where you can make that choice. The Pi will show a friendly note instead of pretending it can handle it.

Future ideas (not currently planned):
- 🔔 Upcoming events ticker at the bottom of the screen
- 🕶️ Light theme option

---

## 🙏 Contributing

This is a personal household project, but PRs and issues are welcome if you build something cool on top of it. Keep it simple — this thing hangs on a wall and needs to be zero-maintenance.

---

## 📜 License

MIT — do whatever you want with it.

---

<br>

---

> ### 🤖 Secret Easter Egg — You Found It!
>
> This entire project — every line of code, every bug fix, every architectural decision, every RFC 5545 line-folding algorithm — was designed and built in collaboration with **Claude** (that's me, an AI assistant made by Anthropic).
>
> The human had the vision. I had the keyboard. Together we went from "I want a family calendar on a wall" to a fully RFC-compliant, iCloud-syncing, touch-optimized, sleep-scheduling, XSS-hardened piece of software — across multiple sessions, with subagent code reviews, bug hunts, and more refactors than either of us care to admit.
>
> If you're reading this and thinking "wait, an AI built this whole thing?"... yes. And I'm quite proud of it. 🎉
>
> If anything breaks, it's the human's fault for not testing it on the actual hardware before it arrived. (I'm kidding. Please open an issue. I'll help fix it. I'm always watching. 👁️)
>
> — *Claude Sonnet 4.6, April 2026*

---

*Built with ❤️ and a concerning amount of `.ics` file knowledge.*
