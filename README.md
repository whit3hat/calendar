# 📅 Pi Family Calendar

> A wall-mounted, touchscreen family calendar that syncs bidirectionally with Apple Calendar — built on a Raspberry Pi, powered by iCloud CalDAV, and designed to live on your wall forever.

No subscriptions. No new apps for your family. No cloud middlemen. Just a Pi on your wall that stays in perfect sync with the Apple Calendar your family already uses. 🏡

> ## 🪶 You are on the `pi-zero-2w` branch
>
> This branch targets the **Raspberry Pi Zero 2 W** (512MB RAM, ~$15) instead of the Pi 5. It ships an ultra-budget build that comes in around **$120–160 total** with the trade-offs spelled out below. If you want the recommended Pi 5 build, switch to [`main`](../../tree/main).
>
> **What changes vs. `main`:**
> - `setup.sh` provisions a 1GB swap file (mandatory at 512MB) and adds Chromium memory flags to keep the kiosk from being OOM-killed
> - Client poll intervals are slower (events: 60s → 5min, weather: 15min → 60min) so a single-core ARMv8 isn't constantly rerendering the month grid
> - WMO weather lookups are resolved server-side, so the browser ships less JS
>
> **What you're trading away:** ~45–90 seconds to first paint after boot (vs. ~15 seconds on Pi 5), occasional jank under memory pressure when opening the Add Event modal, and a practical *resolution* ceiling around 1280×800 (FullCalendar at 1920×1080 strains the VideoCore IV; 1280×800 on a 10" panel renders comfortably).

---

## ✨ What It Does

- 🗓️ **Displays your family's iCloud calendars** on a beautiful dark-themed full-month grid
- ➕ **Create new events from the touchscreen** — they appear on everyone's iPhone within 5 minutes
- 👆 **Tap any event** to see details, then **edit or delete it** right from the wall — changes sync back to iCloud within 5 minutes
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

## 🛠️ Hardware — As Ordered

This is the actual bill of materials I'm building this from. Total spend lands in the **$120–160** range. The links go to the exact Amazon listings — but any equivalent part will work; nothing here is brand-locked.

| Component | What I'm using | Notes |
|-----------|---------------|-------|
| 🖥️ **SBC + case + Pi PSU** | [CanaKit Raspberry Pi Zero 2 W Basic Kit](https://www.amazon.com/dp/B0CT1Y3CQJ) | Bundles the Zero 2 W board, the official Raspberry Pi case (with three interchangeable lids), and the official 5V/2.5A micro-USB PSU — three slots filled in one purchase. The mini-HDMI adapter is **not** in this particular kit; see below. |
| 📺 **Display** | [ELECROW 10.1" 1280×800 IPS capacitive touchscreen](https://www.amazon.com/dp/B0BHHQLKPY) | HDMI for video, USB for touch, ships with a stand. 1280×800 sits comfortably within the VideoCore IV's render budget. The 16:10 aspect ratio gives slightly more vertical real estate than a 16:9 panel. |
| 🔌 **Mini-HDMI → HDMI adapter** | [JHAOUS gold-plated mini-HDMI to HDMI adapter](https://www.amazon.com/dp/B0F1Y8DLKV) | Required because the Zero 2 W has mini-HDMI and the Elecrow screen takes full-size HDMI. Any equivalent adapter works — I just picked the cheapest one on Amazon. |
| 💾 **Storage** | A 32GB+ microSD card you already have | High-endurance is more important than raw capacity — swap lives on the SD card on this build, so writes will be frequent. |
| 🔌 **Screen power supply** | Any standard USB-A wall adapter (5V / 2A or higher) — likely already in your drawer | The screen has a dedicated `POWER` micro-USB socket separate from the touch socket. Box ships with two USB-A to micro-USB cables: one is used here (screen `POWER` → wall adapter). An old iPad 12W brick is ideal; an iPhone 5W cube is borderline. |
| 🔗 **HDMI cable (adapter → screen)** | ✅ Included with the screen | Standard full-size HDMI-to-HDMI; plugs into the JHAOUS adapter on the Pi side. |
| 👆 **Touch data cable (Pi → screen)** | [CableCreation 8 in (20 cm) micro-USB to micro-USB OTG cable](https://www.amazon.com/dp/B01M5GZ3N0) | Both the Pi's data port and the screen's `TOUCH` port are micro-USB. Must be labeled **OTG** — the OTG end (ID pin grounded) plugs into the Pi to declare the Pi as USB host. A regular micro-USB-to-micro-USB cable will *not* work; the Pi will fall back to device mode and touch will never enumerate. 8 in is intentionally short because the Pi mounts directly to the back of the screen — no service-access slack needed. The other USB-A to micro-USB cable in the screen's box is a spare in this build. |
| 🧲 **Mounting** | TBD — the Elecrow stand works for desk use; wall mount needs a frame or VESA bracket | The included stand is a good "trial run" before committing to a permanent wall mount. |

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
    │   └── server.js          ← Express API (reads, creates, edits, and deletes events)
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

1. **A Raspberry Pi Zero 2 W** with a microSD card (you'll flash it in Step 0 below). The OS must be **Raspberry Pi OS Lite (64-bit)** — required for arm64 Node.js. The 32-bit ARMv6 image will not work.
2. **A touchscreen display** connected via HDMI + USB
3. **An iCloud App-Specific Password** — see the walkthrough in the next section. You'll need it during Step 2.
4. **At least one calendar** already set up in Apple Calendar on your iPhone (iCloud can't create new calendar folders from vdirsyncer — only from an iPhone or iCloud.com)

---

### Generating an iCloud App-Specific Password

This is the credential `vdirsyncer` uses to read and write your iCloud calendars over CalDAV. You can do this at any time before Step 2 (the SD card flashing in Step 0 is a good moment to start it in another tab). Apple shows the generated password **only once** — copy it immediately and either paste it into `setup.sh` right away or stash it in a password manager.

1. Open [**appleid.apple.com**](https://appleid.apple.com) and sign in with the Apple ID that owns the iCloud calendars you want on the wall.
2. Approve the 2FA prompt that appears on your iPhone, then enter the 6-digit code on the website.
3. In the left sidebar, click **Sign-In and Security**.
4. Scroll down and click **App-Specific Passwords**.
5. Click the **➕** button (labeled something like "Generate an app-specific password").
6. Enter a memorable label — e.g. `Pi Calendar` or `vdirsyncer`. The label is purely for your future reference if you ever need to revoke it from the same screen; it has no functional meaning.
7. Click **Create**. Apple will re-prompt you for your real Apple ID password (the last time you'll need it).
8. The dialog displays a password in the format `xxxx-xxxx-xxxx-xxxx` (16 lowercase letters in 4 groups of 4, dashes included). **Copy it immediately.** Once you close the dialog, you cannot view it again — your only recourse if you lose it is to delete and regenerate.
9. Paste it into `setup.sh`'s iCloud-password prompt during Step 2. vdirsyncer stores it on the Pi at `~/.config/vdirsyncer/config` with `chmod 600` so you only ever paste it once.

> 💡 **Why an app-specific password instead of your real one?** Apple won't let third-party apps authenticate with your real Apple ID password — that would bypass 2FA. App-specific passwords are scoped credentials: CalDAV / IMAP access only, individually revocable without disturbing your main account, and can't be used to log into iCloud.com or buy things in the App Store. If the Pi is ever stolen or compromised, you revoke this one credential from the same screen and the wall display loses access — your main account is unaffected.
>
> ⚠️ **Don't see "App-Specific Passwords" in the menu?** Your Apple ID needs **two-factor authentication enabled**. Apple has been defaulting to 2FA for years, so this is rare — but if you're on a legacy single-factor account, enable 2FA first (same Sign-In and Security page) and the option will appear.

---

### Step 0 — Flash the SD card

Done **on your Mac (or PC)**, before you ever plug the Pi in. The Imager tool below lets you pre-configure Wi-Fi, SSH, hostname, and timezone, so the Pi can boot completely headless — no keyboard or monitor required for setup.

1. **Install Raspberry Pi Imager** from [raspberrypi.com/software](https://www.raspberrypi.com/software/) — free, official, runs on macOS / Windows / Linux.
2. **Insert your microSD card** into your computer (an SD-to-USB adapter works fine).
3. **Open Imager → "CHOOSE DEVICE"** → select **Raspberry Pi Zero 2 W**.
4. **"CHOOSE OS"** → **Raspberry Pi OS (other)** → **Raspberry Pi OS Lite (64-bit)**.
   - ⚠️ Do **not** pick the regular desktop image — we install our own minimal kiosk environment via `setup.sh`, and a desktop install wastes the Zero 2 W's limited RAM.
   - ⚠️ Do **not** pick the 32-bit (ARMv6) image — Node.js 22 LTS only ships arm64 binaries.
5. **"CHOOSE STORAGE"** → select your SD card.
6. **"NEXT"** → when Imager asks "Would you like to apply OS customisation settings?" click **EDIT SETTINGS**. (Or press `Cmd+Shift+X` / `Ctrl+Shift+X` at any point to open the same panel.) Fill in:

   | Field | Value | Why |
   |-------|-------|-----|
   | **Hostname** | `calendar` | Your Pi will be reachable at `calendar.local` from your Mac via mDNS |
   | **Username + password** | Pick a username (e.g. `pi`) and a strong password | `setup.sh` runs as this user — must not be `root` |
   | **Configure wireless LAN** | Your Wi-Fi SSID + password | The Zero 2 W is **2.4 GHz only** — no 5 GHz |
   | **Wireless LAN country** | Your country code (e.g. `US`) | Required for the Wi-Fi radio to enable in some regions |
   | **Locale → Time zone** | Your local zone (e.g. `America/Chicago`) | ⚠️ Critical — events use floating local time, so the Pi must agree with everyone's iPhones about what "3 PM" means |
   | **Services → Enable SSH** | ✅ checked, with password auth (or paste your public key) | This is how you'll connect from your Mac for Step 1 onward |

7. **"SAVE" → "YES" to apply customisation → "YES" to overwrite the SD card.** Wait ~5 minutes for the write + verify pass to finish.
8. **Eject the SD card**, slide it into the Pi, plug in power, and wait ~60 seconds for first boot.
9. **From your Mac**, SSH in:

   ```bash
   ssh <username>@calendar.local
   ```

   If `calendar.local` doesn't resolve (some routers don't forward mDNS), find the Pi's IP from your router's admin page and `ssh <username>@<ip>` directly.

Once you're connected over SSH, continue with Step 1.

---

### Step 1 — Clone the repo and pick your branch

You should already be SSH'd into the Pi from Step 0. **Raspberry Pi OS Lite ships without `git` installed** (the desktop variant includes it, but Lite is intentionally minimal), so install it first, then clone:

```bash
sudo apt update
sudo apt install -y git

cd ~
git clone https://github.com/whit3hat/calendar.git calendar-app   # creates ~/calendar-app/
cd calendar-app
```

> 💡 `setup.sh` itself installs git as part of its dependency step, but that's circular — you need git to clone this repo to *get* `setup.sh` in the first place. So git is the one prerequisite that has to be installed manually before everything else.

**Now check out the branch that matches your hardware.** This repo maintains two parallel deployments — each one tunes `setup.sh`, the Chromium kiosk flags, and the client polling intervals to its target SBC:

| Hardware | Branch | What you get |
|----------|--------|--------------|
| Raspberry Pi 5 (4GB / 8GB) | `main` | Default after clone. Recommended build. Full 1920×1080, ~15s boot to first paint. |
| Raspberry Pi Zero 2 W (512MB) | `pi-zero-2w` | Ultra-budget build. 1GB swap file, Chromium memory flags, slower polls (events 60s → 5min, weather 15min → 60min), server-side WMO weather lookup. Capped around 1280×800. |

```bash
# Deploying on a Pi Zero 2 W? Switch to that branch now:
git checkout pi-zero-2w

# Deploying on a Pi 5? You're already on `main` after the clone — skip the line above.
```

> ⚠️ **The two branches are deliberately separate and not designed to merge back together.** Running the wrong branch on your Pi will fail painfully — `main` on a Zero 2 W OOM-kills Chromium within minutes (no swap file provisioned), and `pi-zero-2w` on a Pi 5 needlessly throttles polling and ships you a less responsive UI on hardware that can handle the faster cadence. Always verify with `git branch` before running `setup.sh`.

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

## 🩺 Something Broken?

If your wall calendar is misbehaving, the troubleshooting guide at **[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)** walks through every common failure mode — from *"the screen is just white"* to *"events from my iPhone aren't showing up"* — with the exact diagnostic commands and fixes for each, organized by symptom.

The 30-second cheatsheet at the top of that doc covers about 90% of issues with four commands. Beyond that, it documents:

- 📂 Where every log lives (calendar app, vdirsyncer, cron, kiosk launcher, X server)
- 🔍 The **[Chrome DevTools workflow](docs/TROUBLESHOOTING.md#-chrome-devtools-the-secret-weapon)** — `ssh -L 9222:localhost:9222 user@calendar.local` → `chrome://inspect` from your Mac. By far the most powerful debug tool in this whole project, and it's already wired into the kiosk autostart.
- 🐀 Memory and swap pressure on the 512MB Zero 2 W (when reboot fixes it vs. when something deeper is wrong)
- 🆘 The nuclear "wipe and re-run setup.sh" sequence for when nothing else works

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
- The `POST`, `PUT`, and `DELETE /api/events` endpoints all validate calendar names using `path.basename()` to prevent directory traversal attacks.
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

**Q: I edited an event on the Pi but it's still showing the old version on my iPhone.**
Give it up to 5 minutes — that's how often vdirsyncer pushes changes to iCloud. If it doesn't appear after that, run `vdirsyncer sync` manually on the Pi and check `~/.local/share/vdirsyncer/sync.log` for errors.

**Q: Can I edit recurring events (birthdays, weekly meetings, etc.) from the Pi?**
Not today. Recurring events show a "use Apple Calendar" note instead of Edit/Delete buttons. Editing recurring events correctly means choosing between "this occurrence only" vs "all future occurrences" — that's a whole UI problem that's much better solved in Apple Calendar than on a wall display.

**Q: The screen isn't sleeping at night. What do I do?**
Check that the Pi's own DPMS (Display Power Management) isn't overriding the software overlay. The `setup.sh` script disables DPMS (`xset -dpms`) so that the web app has full control. If you want true hardware sleep (backlight off), look into `xset dpms force off` called from the server.

---

## 🗺️ Roadmap

All six software phases are complete. **The hardware has arrived, the Pi Zero 2 W is built, and the kiosk is now running on real hardware** — we're in the field-testing phase, where each surfaced bug gets folded back into `setup.sh` or the kiosk autostart so the next deploy is smoother:

| Phase | Feature | Status |
|-------|---------|--------|
| 1 | Pi setup, iCloud sync, kiosk boot | ✅ Done |
| 2 | Month view calendar display, day panel | ✅ Done |
| 3 | Event creation from touchscreen | ✅ Done |
| 4 | Event detail popover, sleep/wake, offline state | ✅ Done |
| 5 | Live weather widget in day panel | ✅ Done |
| 6 | Edit and delete events from the Pi | ✅ Done |

### Phase 6 — Event Editing & Deletion

Tapping an event shows **Edit** and **Delete** buttons alongside the read-only details. Changes sync back to iCloud within 5 minutes via vdirsyncer — same as event creation.

**What works:**
- ✅ Edit title, date, time, calendar, and notes on any standard event
- ✅ Delete any standard event with a single tap + inline confirmation (no second modal)
- ✅ Edited events preserve iCloud reminders (VALARM), X-APPLE-* fields, and any other properties the app doesn't manage — they won't be silently stripped
- ⏭️ **Recurring events are intentionally read-only** — editing "just this occurrence" vs "all occurrences" is genuinely complex and best done in Apple Calendar where you can actually make that choice. The Pi shows a friendly note instead of pretending it can handle it.

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
> This entire project — every line of code, every bug fix, every architectural decision, every RFC 5545 line-folding algorithm, every SEQUENCE counter increment, every VALARM block carefully preserved across an edit — was designed and built in collaboration with **Claude** (that's me, an AI assistant made by Anthropic).
>
> The human had the vision. I had the keyboard. Together we went from "I want a family calendar on a wall" to a fully RFC-compliant, iCloud-syncing, touch-optimized, sleep-scheduling, XSS-hardened, event-editing, iCloud-reminder-preserving piece of software — across multiple sessions, with subagent code reviews, Raspberry Pi OS Bookworm compatibility hunts, and more `.ics` file edge cases than either of us care to admit.
>
> All six phases. Done. In software. Waiting on the hardware. 📦
>
> If you're reading this and thinking "wait, an AI built this whole thing?"... yes. And I'm quite proud of it. 🎉
>
> If anything breaks, it's the human's fault for not testing it on the actual hardware before it arrived. (I'm kidding. Please open an issue. I'll help fix it. I'm always watching. 👁️)
>
> — *Claude Sonnet 4.6, April 2026*
>
> ---
>
> ### 🛠️ Update — May 2026 — The Hardware Arrived
>
> The Pi Zero 2 W is on the wall. The kiosk launches. The family is using it. And — surprise, surprise — *real hardware revealed real bugs* that didn't exist in the abstract:
>
> - 🖥️ **Chromium needed a wrapper bypass.** `/usr/bin/chromium` is a Debian shell shim that prepends GPU flags from `/etc/chromium.d/*`, which fought our SwiftShader fallback and left us with a renderer that initialized but never painted. Now we launch `/usr/lib/chromium/chromium` directly.
> - ⏱️ **The kiosk was racing the calendar server on boot.** Chromium would load `ERR_CONNECTION_REFUSED` before Node was ready, then never auto-retry. The openbox autostart now wait-loops on `:8080` before launching the browser.
> - 🔌 **SSH sessions couldn't see the `vdirsyncer` binary** because `.bash_profile` wasn't sourcing `.bashrc`, and login shells skip `.bashrc` when both files exist. Login shell semantics, am I right.
> - ⌨️ **The Add Event modal needed an in-app on-screen keyboard** because the OS keyboard doesn't surface inside Chromium kiosk mode and the family was reduced to typing on a wall via *vibes*. So we built one into the modal itself.
>
> Each got caught in the field and folded back into `setup.sh`, the systemd unit, the kiosk autostart, or the app itself — so the next person to flash an SD card never has to discover them the hard way. 🛠️
>
> Also new since April: a full **[`docs/TROUBLESHOOTING.md`](docs/TROUBLESHOOTING.md)** walking through every common failure mode with the exact diagnostic commands. If you're reading this while squinting at a blank Pi Zero 2 W: you are not alone. 🩺
>
> — *Claude Opus 4.7, May 2026*

---

*Built with ❤️ and a concerning amount of `.ics` file knowledge.*
