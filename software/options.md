# Software Options — Raspberry Pi Wall Calendar

All solutions listed here are **free and open source**. Prices listed are $0 unless noted.
The software stack has three layers — you'll need one choice from each section to build a complete solution.

> **Requirements confirmed:**
> 1. **Event creation from the Pi touchscreen** — rules out MagicMirror² as the primary display
> 2. **Event creation from mobile devices away from home** — the sync backend must be cloud-accessible, not local-network only
> 3. **Changes made anywhere (phone or Pi) propagate everywhere** — true bidirectional sync required
>
> See `software/architecture.md` for the recommended complete stack that satisfies all three.

---

## Understanding the Stack

```
┌─────────────────────────────────────────────────┐
│  LAYER 3: Display / UI Platform                 │
│  What the calendar looks like and how you       │
│  interact with it via touch                     │
├─────────────────────────────────────────────────┤
│  LAYER 2: Calendar Sync                         │
│  How events travel between your phone,          │
│  Google/iCloud, and the Pi                      │
├─────────────────────────────────────────────────┤
│  LAYER 1: Kiosk / Boot Layer                    │
│  How the Pi boots directly into the             │
│  calendar display without a desktop             │
└─────────────────────────────────────────────────┘
```

> **Important — Read-Only vs. Bidirectional:**
> Some display platforms can only *read* calendar data (display events from your phone).
> True bidirectional sync — where you can *add* an event on the Pi and have it appear on your phone — requires a sync layer that supports write-back. This distinction is called out per option below.

---

## Layer 1: Kiosk / Boot Layer

This is the foundation. It controls how the Pi boots directly into a fullscreen calendar display instead of a normal desktop.

### Option A — Chromium Browser in Kiosk Mode
**License:** Open source (Chromium)
**Complexity:** Low
**Learn more:** [Raspberry Pi documentation](https://www.raspberrypi.com/documentation/) · [Pi My Life Up kiosk guide](https://pimylifeup.com/raspberry-pi-home-assistant-kiosk/)

**How it works:** Raspberry Pi OS includes Chromium. A startup script launches it full-screen, pointed at a local web URL (your calendar app running locally) or a web-hosted dashboard. Touch input works natively. One line in autostart does the job:
```
chromium-browser --kiosk --noerrdialogs --disable-infobars --touch-events=enabled http://localhost:8080
```

**Pros:**
- Already installed on Raspberry Pi OS — nothing extra to download
- Touch events fully supported out of the box
- Works with any web-based calendar UI (MagicMirror, Home Assistant, custom app)
- Easy to update — just change the URL it points to
- Most tutorials for Pi kiosk use this exact approach

**Cons:**
- Chromium uses more RAM than a native app (~200–400MB)
- Chromium updates can occasionally break kiosk behavior (rare)
- No offline fallback if the web app fails to load

---

### Option B — pi-kiosk (Jeff Geerling)
**License:** MIT
**Complexity:** Low (automated setup)
**GitHub:** [geerlingguy/pi-kiosk](https://github.com/geerlingguy/pi-kiosk)

**How it works:** A shell script + systemd service that automates the full kiosk setup — Chromium, auto-login, screen blanking disabled, restart on crash. Run the script once and the Pi boots directly into kiosk mode on every restart.

**Pros:**
- One-command setup — dramatically reduces manual configuration
- Systemd service restarts Chromium automatically if it crashes
- Disables screen saver/blanking by default (good for always-on calendar)
- Battle-tested on Pi 4 and Pi 5 by a widely-followed Raspberry Pi developer
- Actively maintained as of 2024

**Cons:**
- Still uses Chromium under the hood (same RAM usage)
- Opinionated setup — harder to customize if you need non-standard behavior
- Requires internet access during initial setup

---

### Option C — Electron App (Packaged Desktop App)
**License:** MIT (Electron)
**Complexity:** Medium
**Learn more:** [Electron docs](https://www.electronjs.org/docs/latest)

**How it works:** Electron packages a web app (HTML/JS/CSS) as a standalone Linux desktop application. Instead of running a browser pointing at localhost, the calendar IS the app. Used by MagicMirror² under the hood.

**Pros:**
- Better touch event handling than a browser — designed for tablet-style interaction
- Self-contained — no separate web server needed
- Can run without internet once set up
- App-level control over window management, kiosk behavior, crash recovery
- Used by MagicMirror² — proven on Pi hardware

**Cons:**
- Larger install footprint than a plain browser (~150MB+ for Electron runtime)
- Requires Node.js/npm knowledge to build or modify
- Updates require rebuilding the app package
- Slower cold-boot startup than Chromium pointing at localhost

---

## Layer 2: Calendar Sync

This layer handles the data — getting events from Google Calendar or iCloud onto the Pi, and optionally pushing new events back.

### Option A — vdirsyncer
**License:** BSD 3-Clause
**Complexity:** Medium (config file, OAuth setup for Google)
**GitHub:** [pimutils/vdirsyncer](https://github.com/pimutils/vdirsyncer)
**Docs:** [vdirsyncer.pimutils.org](https://vdirsyncer.pimutils.org/en/stable/tutorial.html)

**How it works:** A Python command-line tool that syncs CalDAV calendars (Google Calendar, iCloud, Nextcloud, any CalDAV server) to local `.ics` files on the Pi. Run it on a cron job (e.g., every 5 minutes). Your calendar UI reads those local files.

**Supported providers:** Google Calendar, iCloud, Nextcloud, any CalDAV server

**Bidirectional:** Yes — vdirsyncer reads AND writes. Events added locally sync back to Google/iCloud on next sync run.

**Install:**
```bash
pip3 install vdirsyncer
```

**Pros:**
- True bidirectional sync — add events on the Pi, they appear on your phone
- Supports both Google Calendar and iCloud in the same config
- Lightweight — runs as a background cron job, minimal CPU/RAM
- Local `.ics` files mean the calendar works offline (shows last synced data)
- Active open source project with regular updates

**Cons:**
- Google Calendar requires OAuth app registration (one-time setup, moderately fiddly)
- iCloud requires an app-specific password (simpler than OAuth)
- Not a live push sync — events appear after the next cron interval (5 min typical)
- Config file is text-based — no GUI for setup
- Broken by Google API changes occasionally (check GitHub issues before relying on it)

---

### Option B — Nextcloud (Self-Hosted Calendar Server)
**License:** AGPL-3.0
**Complexity:** High (self-hosted server required)
**GitHub:** [nextcloud/server](https://github.com/nextcloud/server) · [nextcloud/calendar](https://github.com/nextcloud/calendar)
**Docs:** [nextcloud.com/install](https://nextcloud.com/install/)

**How it works:** Nextcloud is a full self-hosted cloud platform. Its Calendar app is a beautiful web calendar that speaks CalDAV natively — your phone, Pi, and any other device all sync to Nextcloud as the central source of truth. Can subscribe to Google Calendar or iCloud feeds.

**Hosting options:**
- Run on the Pi itself (requires Pi 4/5 with 4GB RAM, use SSD not SD card)
- Run on a cheap VPS (~$5/mo at Hetzner, DigitalOcean, etc.)
- Use a free/cheap Nextcloud hosting provider

**Bidirectional:** Yes — Nextcloud is the calendar server, all devices write to it.

**Pros:**
- Most polished self-hosted calendar — web UI is excellent
- Phone apps (iOS/Android) sync natively via CalDAV — feels seamless
- Can bridge Google Calendar and iCloud by subscribing to their iCal feeds
- Full offline capable on the Pi (Pi reads from local Nextcloud)
- Also gives you file sync, contacts, and more if you want it
- Active community, frequent updates

**Cons:**
- Heaviest option — Nextcloud itself needs a server running 24/7
- Running it on the Pi itself competes for RAM with the calendar UI
- Setup is significantly more involved than vdirsyncer
- Google → Nextcloud bidirectional sync requires a third-party bridge (CalDAVconnect or similar) — native subscription is read-only from Google
- Overkill if you only want a calendar

---

### Option C — Radicale (Lightweight Self-Hosted CalDAV)
**License:** GPL-3.0
**Complexity:** Low–Medium
**GitHub:** [Kozea/Radicale](https://github.com/Kozea/Radicale)
**Docs:** [radicale.org](https://radicale.org/)

**How it works:** Radicale is an extremely lightweight CalDAV and CardDAV server that runs directly on the Pi with minimal resources. Your phone and the Pi both sync to it. Unlike Nextcloud it has no web UI — it's purely a sync protocol server.

**Bidirectional:** Yes — Radicale is the server, all clients (phone + Pi) write to it. However, it does NOT bridge to Google Calendar or iCloud on its own — you would need vdirsyncer alongside it to pull from those services.

**Install:**
```bash
pip3 install radicale
```

**Pros:**
- Extremely lightweight — runs on Pi with almost no resource overhead
- Simple Python install, minimal configuration
- Fully open standard CalDAV — any CalDAV app on your phone syncs to it
- No third-party service dependency — your data stays local
- Can run alongside the calendar display on the same Pi

**Cons:**
- No web interface for browsing/editing calendars — server only
- Does NOT bridge to Google Calendar or iCloud natively (use vdirsyncer alongside it for that)
- Less community documentation than Nextcloud
- Setting up phone sync requires manually entering the Pi's local IP in your phone's calendar app

---

## Layer 3: Display / UI Platform

This is the visible calendar — what you see and touch on the screen.

### Option A — MagicMirror²
**License:** MIT
**Complexity:** Low–Medium
**GitHub:** [MagicMirrorOrg/MagicMirror](https://github.com/MagicMirrorOrg/MagicMirror)
**Website:** [magicmirror.builders](https://magicmirror.builders/)

**How it works:** An open-source, Electron-based modular smart display platform originally designed for smart mirrors. Runs on Raspberry Pi. Has a built-in calendar module that reads iCal URLs directly (no separate sync layer needed for read-only). A large library of third-party modules extends it.

**Key calendar modules:**
| Module | Views | Touch | GitHub |
|---|---|---|---|
| **MMM-CalendarExt3** | Month, week | Interactive popovers | [MMRIZE/MMM-CalendarExt3](https://github.com/MMRIZE/MMM-CalendarExt3) |
| **MMM-CalendarExt3Agenda** | Daily agenda | Yes | [MMRIZE/MMM-CalendarExt3Agenda](https://github.com/MMRIZE/MMM-CalendarExt3Agenda) |
| **MMM-SmartTouch** | N/A (touch layer) | Yes — adds standby, menu | [EbenKouao/MMM-SmartTouch](https://github.com/EbenKouao/MMM-SmartTouch) |
| **MMM-Touch** | N/A (gesture layer) | Yes — gesture commands | [gfischershaw/MMM-Touch](https://github.com/gfischershaw/MMM-Touch) |

**Bidirectional:** No — MagicMirror reads iCal feeds. It is **display-only**. To add events from the Pi, you'd need a separate solution (a paired app on phone, or a custom module).

**Install:**
```bash
bash -c "$(curl -sL https://raw.githubusercontent.com/MagicMirrorOrg/MagicMirror/master/tools/install_mm.sh)"
```

**Pros:**
- Fastest path to a working wall display — install takes ~30 minutes
- Reads Google Calendar or iCloud iCal URLs directly without complex OAuth
- Huge module ecosystem (~200+ community modules) for weather, news, etc.
- No coding required for a basic setup
- Actively maintained, large community and forum
- Runs as an Electron app — good touch support with the touch modules added

**Cons:**
- Display-only by default — cannot create or edit events from the screen
- Dark-themed by default (built for mirrors) — requires CSS customization for a clean white calendar look
- Module config is in JSON — not a GUI
- Touch interaction is layered on via modules, not native to the platform
- Built on older Electron — updating can sometimes break modules

---

### Option B — Home Assistant (Lovelace Dashboard)
**License:** Apache 2.0
**Complexity:** Medium–High
**GitHub:** [home-assistant/core](https://github.com/home-assistant/core)
**Website:** [home-assistant.io](https://www.home-assistant.io/)

**How it works:** Home Assistant is a powerful open-source home automation platform with a highly customizable web dashboard (Lovelace). Its calendar integration supports Google Calendar and iCloud (via CalDAV). The dashboard runs in a browser and works well in kiosk mode on Pi touchscreens. Calendar cards from the community extend the built-in calendar view.

**Key calendar cards:**
| Card | Description | GitHub |
|---|---|---|
| **atomic-calendar-revive** | Advanced agenda + month view, highly configurable | [totaldebug/atomic-calendar-revive](https://github.com/totaldebug/atomic-calendar-revive) |
| **calendar-card-pro** | Sleek, modern design with smart caching | [alexpfau/calendar-card-pro](https://github.com/alexpfau/calendar-card-pro) |
| **Native calendar card** | Built-in, day/month/list views | [home-assistant.io/dashboards/calendar](https://www.home-assistant.io/dashboards/calendar/) |

**TouchKio** — a dedicated kiosk wrapper for Home Assistant on Pi touchscreens: [leukipp/touchkio](https://github.com/leukipp/touchkio)

**Bidirectional:** Yes — the Google Calendar integration in Home Assistant supports creating events. The CalDAV integration supports full read/write. Events added via the HA dashboard sync back to Google/iCloud.

**Install:** [Home Assistant OS](https://www.home-assistant.io/installation/raspberrypi/) or as a Docker container on Raspberry Pi OS.

**Pros:**
- True bidirectional sync — create events from the Pi touchscreen
- Google Calendar and iCloud both natively supported as integrations
- Beautiful, fully touch-friendly dashboard — designed for tablets and wall panels
- Can also display weather, family photos, smart home controls alongside the calendar
- HACS (Home Assistant Community Store) gives access to hundreds of community cards
- Active development by a huge community; very reliable

**Cons:**
- Heaviest option — requires significant setup and 2–4GB RAM recommended
- HA is a full home automation platform — significant learning curve if all you want is a calendar
- Running HA + Chromium kiosk on a Pi 4 4GB is tight on RAM; Pi 5 4GB is more comfortable
- Calendar UI customization requires YAML config, not a drag-and-drop UI
- Updates occasionally break community cards (manageable but requires attention)

---

### Option C — Custom Web App (FullCalendar.js + Chromium Kiosk)
**License:** MIT (FullCalendar)
**Complexity:** High (requires web development)
**GitHub:** [fullcalendar/fullcalendar](https://github.com/fullcalendar/fullcalendar)
**Website:** [fullcalendar.io](https://fullcalendar.io/)

**How it works:** FullCalendar is an open-source JavaScript library that renders beautiful interactive calendar UIs — month, week, day, agenda, timeline views. You build a small local web app (HTML + JavaScript) that reads from `.ics` files synced by vdirsyncer and renders them with FullCalendar. The app runs as a local server on the Pi, Chromium opens it in kiosk mode.

**Bidirectional:** Possible — reading is straightforward (parse local .ics files). Writing back requires adding a backend (a small Node.js or Python server that appends events to the local .ics files and lets vdirsyncer push them upstream).

**Pros:**
- Maximum control — looks and behaves exactly how you want
- FullCalendar has the richest view options of any library (month, week, day, list, timeline, resource views)
- Touch and drag-and-drop are built into FullCalendar natively
- Lightweight — a static local web app uses minimal Pi resources
- No cloud dependency whatsoever once initial sync is set up
- Can be styled to match any aesthetic (fonts, colors, layout)

**Cons:**
- Requires HTML/JavaScript development — not a turnkey solution
- Need to build or find a backend for event creation (write-back)
- More total pieces to maintain (web app + vdirsyncer + Chromium kiosk)
- No built-in error handling — you design the offline/error states
- Time investment to build vs. using an existing platform

---

## Recommended Combinations

> Since **creating events from the Pi is required**, only stacks that include a write-capable UI are viable. The two options below both meet this requirement. MagicMirror²-only stacks are noted as read-only and excluded from viable recommendations.

---

### ✅ Recommended — Home Assistant (~1–2 days setup)

The best balance of capability and available documentation for this exact use case. Home Assistant has a native event-creation flow that works on a touchscreen and syncs directly back to Google Calendar or iCloud.

| Layer | Choice |
|---|---|
| Kiosk | [TouchKio](https://github.com/leukipp/touchkio) — purpose-built HA kiosk for Pi touchscreens |
| Sync | Home Assistant's built-in Google Calendar + CalDAV integrations (no vdirsyncer needed) |
| Display | Home Assistant Lovelace + [atomic-calendar-revive](https://github.com/totaldebug/atomic-calendar-revive) or [calendar-card-pro](https://github.com/alexpfau/calendar-card-pro) |

**How event creation works:** HA's native calendar card has a "+" button for adding events. Tapping it opens a touch-friendly form (title, date, time, calendar to save to). The event is written directly to Google Calendar or iCloud via the integration — no separate sync step.

**What syncs:**
- Google Calendar: native HA integration, bidirectional
- iCloud: via CalDAV integration in HA, bidirectional

**Pros for this use case:**
- Event creation is built-in and touch-friendly — no custom code
- Both Google Calendar and iCloud supported natively
- Dashboard can show weather, family photos, or other widgets alongside calendar
- Strong community; lots of Pi touchscreen kiosk examples to follow

**Cons:**
- Home Assistant itself takes ~30–60 minutes to install and configure
- Needs Pi 5 (4GB) for comfortable performance running HA + Chromium
- Calendar card appearance requires YAML config (not difficult, but not a GUI)

---

### ✅ Alternative — Custom Web App + FullCalendar.js (~1–2 weeks build)

The right choice if you want the calendar to look exactly a certain way, or want to build something from scratch as a project. More development work upfront, full control forever after.

| Layer | Choice |
|---|---|
| Kiosk | Chromium kiosk mode (or pi-kiosk for automated setup) |
| Sync | [vdirsyncer](https://github.com/pimutils/vdirsyncer) — pulls Google/iCloud to local `.ics` files, pushes new events back |
| Display | Custom web app using [FullCalendar.js](https://github.com/fullcalendar/fullcalendar) + a small local backend (Node.js or Python/Flask) for event write-back |

**How event creation works:** You build a form in your web app. When submitted, a small backend server writes the new event to the local `.ics` file. vdirsyncer's next sync run (cron, every 5 min) pushes it to Google Calendar or iCloud.

**What syncs:**
- Google Calendar: vdirsyncer with OAuth
- iCloud: vdirsyncer with app-specific password

**Pros for this use case:**
- Calendar UI is exactly what you design — any font, color, layout
- FullCalendar has the richest view options (month, week, day, agenda, timeline)
- Touch and drag-and-drop are built into FullCalendar natively
- Lightweight — no Home Assistant overhead

**Cons:**
- Requires writing JavaScript + a small backend API
- vdirsyncer write-back has a delay (events appear on phone at next sync, up to 5 min)
- More pieces to maintain independently

---

### ❌ Not Viable for This Use Case — MagicMirror² Alone

MagicMirror² is **display-only** — there is no built-in mechanism to create, edit, or delete calendar events from the screen. It is excluded from viable stacks given the event-creation requirement.

It remains useful as a starting point to validate your hardware setup (screen, touch, Pi) before building the full stack.

---

### ✅ Self-Contained / No Cloud Dependency (~2–3 days setup)

For users who want all data to stay local and not depend on Google or Apple servers long-term.

| Layer | Choice |
|---|---|
| Kiosk | pi-kiosk |
| Sync | [Radicale](https://github.com/Kozea/Radicale) (CalDAV server on Pi) + vdirsyncer (initial import from Google/iCloud, then Radicale is the source of truth) |
| Display | Home Assistant (pointed at local Radicale) or Custom FullCalendar.js app |

**Trade-off:** Phone and Pi both sync to Radicale running on the Pi. No cloud dependency after initial setup. Requires your Pi to always be reachable on your home network for phone sync to work.

---

## Summary Table

| Solution | Creates Events? | Sync Direction | Setup Difficulty | Touch | Google Cal | iCloud |
|---|---|---|---|---|---|---|
| MagicMirror² + iCal URL | ❌ No | Read-only | Easy | Via modules | ✅ | ✅ public only |
| **Home Assistant** | ✅ **Yes** | Bidirectional | Medium | Native | ✅ | ✅ |
| **Custom app + FullCalendar** | ✅ **Yes** | Bidirectional | Hard | Native | ✅ | ✅ |
| **Radicale + HA/Custom app** | ✅ **Yes** | Bidirectional (local) | Medium–Hard | Native | ✅ import | ✅ import |
