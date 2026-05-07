# 🩺 Troubleshooting & Operations Guide

> So your wall calendar is misbehaving. Welcome! This is the guide for staring at a blank screen at 7 AM and figuring out *which of the four things* on this Pi has decided to ruin breakfast. ☕

This doc covers the **`pi-zero-2w`** branch specifically. If you're on `main` (the Pi 5 build), 90% of this still applies, but the systemd-service-and-swap-file-and-Chromium-wrapper-bypass paragraphs are specific to the budget build's particular brand of suffering.

---

## 🧭 First Things First — The 30-Second Cheatsheet

If something's broken and you don't know where to start, run these four commands in order. One of them will almost always reveal the problem:

```bash
# 1. Is the calendar web app even running?
systemctl status calendar.service

# 2. Did the last iCloud sync work?
tail -n 30 ~/.local/share/vdirsyncer/sync.log

# 3. Did the kiosk launch cleanly on this boot?
cat /tmp/kiosk.log

# 4. Are we drowning in swap (and therefore about to be slow forever)?
free -h
```

90% of issues fall out of one of those. The other 10% are network, and those are covered further down. 🪤

---

## 📂 Where the Logs Live

Four things are running on your Pi at any given moment, and each one logs to a *different place*. (We know. We're sorry. This is just how Linux is.)

| Component | What it does | Log location | How to tail it |
|-----------|-------------|--------------|----------------|
| 🟢 **Calendar web app** (Node.js + Express) | Serves `:8080`, reads `.ics` files, writes new events | `journalctl -u calendar.service` | `journalctl -u calendar.service -f` |
| 🔄 **vdirsyncer** (cron, every 5 min) | Pulls iCloud calendars into `~/.local/share/calendar/`, pushes new local events back up | `~/.local/share/vdirsyncer/sync.log` | `tail -f ~/.local/share/vdirsyncer/sync.log` |
| ⏰ **cron** (the scheduler that runs vdirsyncer) | Fires `vdirsyncer sync` every 5 minutes | `journalctl -u cron` (or `grep CRON /var/log/syslog`) | `journalctl -u cron -f` |
| 🖥️ **Kiosk launcher** (openbox autostart) | Wipes Chromium profile, waits for `:8080`, launches Chromium | `/tmp/kiosk.log` | `tail -f /tmp/kiosk.log` |
| 🌐 **Chromium itself** | Renders the calendar | No log file 😅 — see the [Chrome DevTools](#-chrome-devtools-the-secret-weapon) section below |
| 🎨 **X server** (Xorg) | Provides the display Chromium draws on | `~/.local/share/xorg/Xorg.0.log` (when started via `startx` as user) | `less ~/.local/share/xorg/Xorg.0.log` |

> 💡 **`/tmp/kiosk.log` resets on every reboot.** That's intentional — it's a per-session log. If the kiosk is failing intermittently, capture it before you reboot or it's gone forever.

> 💡 **`journalctl` is the "one log to rule them all"** for anything started by systemd. `journalctl -u calendar.service --since "10 minutes ago"` is your friend. `journalctl -b` shows everything since the most recent boot.

---

## 🔧 Common Operations

### Restart the calendar web app

```bash
sudo systemctl restart calendar.service
systemctl status calendar.service     # confirm it came back up
```

The service auto-restarts on crash with a 5-second delay (see `systemd/calendar.service`), so unless it's *repeatedly* dying, you don't normally need to touch it.

### Force an iCloud sync right now (don't wait 5 minutes)

```bash
vdirsyncer sync
```

If you just edited an event on the wall and want to confirm it landed on iCloud before walking away, this is the command. It also tells you immediately if your credentials have expired or your network is down. ⚡

### See exactly what got synced last time

```bash
tail -n 50 ~/.local/share/vdirsyncer/sync.log
```

You're looking for lines like `Syncing family_calendar/Family` followed by `Sync 'family_calendar/Family' completed.` If you see `Error:` you have a problem — usually credentials or network.

### Re-discover calendars after adding a new one in Apple Calendar

```bash
vdirsyncer discover family_calendar
```

Run this **after** creating a new calendar on your iPhone or at iCloud.com. Without it, vdirsyncer keeps syncing only the calendars it knew about at first install.

### Pick which iCloud calendars actually sync (interactive)

```bash
bash scripts/restrict-calendars.sh
```

Connects to iCloud, lists every calendar collection on your account, lets you check the boxes for the ones you actually want on the wall, and rewrites `~/.config/vdirsyncer/config` accordingly. Backs up your previous config to `~/.config/vdirsyncer/config.bak.<timestamp>` and restarts the calendar service for you. Use this if your spouse's "Reminders" list keeps cluttering up the wall display. 😅

### Reach the Pi from your Mac

```bash
ssh <username>@calendar.local
```

(If `calendar.local` doesn't resolve, your router doesn't forward mDNS — find the IP in your router's admin page and SSH to that instead.)

### Reboot the whole thing

```bash
sudo reboot
```

The nuclear option. Surprisingly often the right answer. 🚀

---

## 🩺 Symptom-Driven Troubleshooting

### 😶‍🌫️ "The screen is just... white. Forever. Nothing loads."

This is the most common Pi Zero 2 W failure mode and there are **three different causes**, each with a different fix. Diagnose first, fix second.

**Step 1 — Is the calendar web app actually running?**

```bash
systemctl status calendar.service
curl -s -o /dev/null -w "%{http_code}\n" http://localhost:8080
```

You want `active (running)` from systemctl and `200` from curl.

| What you see | What it means | Fix |
|---|---|---|
| `inactive (dead)` and `curl: connection refused` | Node app crashed or never started | `journalctl -u calendar.service -n 50` to see why, then `sudo systemctl restart calendar.service` |
| `failed` and `Restart=always` exhausted | App is crashing in a loop | Check the logs for the actual error (usually a missing dep or syntax issue from a bad edit) |
| `active (running)` and `200`, but screen still white | App is fine — Chromium is the problem ↓ | Continue to Step 2 |

**Step 2 — Did Chromium get a stale session?**

The autostart script *already* wipes `~/.config/chromium` on every launch, but if you've manually run Chromium under SSH or in a different way, you can leave breadcrumbs that the next launch tries to restore. Symptom: a Chromium window that opens but never paints anything.

```bash
# Stop kiosk, nuke profile, reboot
sudo pkill -f /usr/lib/chromium/chromium
rm -rf ~/.config/chromium ~/.cache/chromium
sudo reboot
```

**Step 3 — Did Chromium actually launch the right binary?**

The Debian package ships **two** chromium executables: `/usr/bin/chromium` (a shell wrapper that prepends GPU flags from `/etc/chromium.d/*` — these conflict with our SwiftShader fallback) and `/usr/lib/chromium/chromium` (the actual binary). The kiosk autostart deliberately uses the second one.

```bash
ps aux | grep -E '/(usr|opt)/.*chromium' | grep -v grep
```

You should see `/usr/lib/chromium/chromium --kiosk ...`. If you instead see `/usr/bin/chromium-browser` or `/usr/bin/chromium`, your `~/.config/openbox/autostart` is wrong — re-run `bash scripts/setup.sh` to regenerate it.

> 💡 **Why does this matter?** The wrapper adds `--enable-gpu-rasterization` and `--use-angle=gles`, both of which fight `--use-gl=swiftshader` and produce a renderer that initializes but never paints. The whole VideoCore IV / GLES3 saga is documented in `setup.sh` line 318 — read the comments if you're curious.

---

### 📡 "Loading Calendars..." spinner that never goes away

This used to be a *thing* on the Pi Zero 2 W when FullCalendar.js was loaded from `cdn.jsdelivr.net`. Chromium would prefer IPv6, the home network would advertise an IPv6 prefix without a working v6 default route, and the request would hang past the renderer's per-resource budget. We fixed it by vendoring FullCalendar into `app/public/vendor/fullcalendar/` — so on this branch, you should never see this. If you do anyway:

```bash
# Confirm the vendored bundle is actually present
ls -la ~/calendar-app/app/public/vendor/fullcalendar/
# You should see index.global.min.js (~282KB)

# Confirm the index.html references the local path, not the CDN
grep -E 'fullcalendar|jsdelivr' ~/calendar-app/app/public/index.html
# Want: /vendor/fullcalendar/index.global.min.js
# Don't want: cdn.jsdelivr.net
```

If `index.html` still references the CDN, you're on the wrong branch. `git checkout pi-zero-2w` and try again. 🛑

---

### 📅 "Events I created on my iPhone aren't showing up on the wall"

Walk down the chain — sync runs every 5 minutes, so you'll have to be at least mildly patient (~6 minutes worst case).

```bash
# 1. Did vdirsyncer's last run actually succeed?
tail -n 30 ~/.local/share/vdirsyncer/sync.log

# 2. Are there .ics files on disk for that calendar?
find ~/.local/share/calendar -name "*.ics" | wc -l
ls ~/.local/share/calendar/Family/ | head

# 3. Is cron firing every 5 minutes like it should?
journalctl -u cron --since "15 minutes ago" | grep vdirsyncer

# 4. Force a sync right now and watch what happens
vdirsyncer sync
```

| What you see | What it means | Fix |
|---|---|---|
| `Error: 401 Unauthorized` | Your iCloud app-specific password got revoked | Generate a new one at appleid.apple.com → re-run `setup.sh` |
| `Error: 403 Forbidden` on a single calendar | iCloud yanked your access to a shared calendar | Have the calendar owner re-share it from their iPhone |
| Network errors / DNS failures | Wi-Fi is dead | See the [Network Issues](#-network-issues) section |
| Sync succeeds, but `.ics` file count hasn't grown | The event isn't on iCloud yet — give it 1–2 min | Open Apple Calendar on your phone and pull-to-refresh; iCloud is the bottleneck, not us |
| `.ics` files exist but don't appear on wall | Calendar app isn't seeing them — restart it | `sudo systemctl restart calendar.service` |

> 💡 **iCloud's CalDAV layer is sometimes just slow.** A new event from an iPhone can take 30–90 seconds to appear in CalDAV even though it's instant in the Apple Calendar UI. This isn't a bug in our project — Apple's sync layer is its own creature. ⏳

---

### 📤 "Events I created from the wall aren't showing on my iPhone"

Reverse direction, same chain. The wall writes a `.ics` file immediately, but vdirsyncer pushes it on its 5-minute cycle.

```bash
# Find the .ics file you just created (sorted by modification time, newest first)
ls -lt ~/.local/share/calendar/*/  | head -20

# Force a push to iCloud right now
vdirsyncer sync

# Watch the result
tail -f ~/.local/share/vdirsyncer/sync.log
```

If you see something like `Error: ...` after the `Syncing` line, copy/paste the error and the next line is *probably* a hint. The most common is a permissions issue — you're trying to write to a calendar you only have read access to (e.g. a shared family calendar where you're a viewer-only).

---

### 🌤️ "Weather widget is missing / showing the wrong location"

The widget is `display: none` until the first successful fetch — so a missing widget is *equivalent* to a failing fetch. Check the server first, the network second.

```bash
# Hit the weather endpoint locally
curl -s http://localhost:8080/api/weather | head -c 500
```

| What you see | What it means | Fix |
|---|---|---|
| Valid JSON with current/today/forecast | Server is fine — it's a frontend or cache issue. Hard-refresh the kiosk via `chrome://inspect` (see below) | — |
| `{"error":"Weather unavailable"}` (HTTP 503) | First fetch failed and there's no stale cache to serve | Check internet: `ping -c 2 api.open-meteo.com` |
| Wrong location | `WEATHER_LAT`/`WEATHER_LON` env vars aren't set, or hardcoded defaults are still pointing at Liberty, MO | Set env vars on the systemd unit (see below) |

To change the weather location permanently:

```bash
# Edit the systemd unit
sudo systemctl edit calendar.service

# In the editor, add (replacing with your coords from Google Maps):
[Service]
Environment=WEATHER_LAT=40.7128
Environment=WEATHER_LON=-74.0060
Environment=WEATHER_UNITS=fahrenheit

# Save and restart
sudo systemctl restart calendar.service
```

> 🌍 **Finding your coordinates:** Google Maps → right-click your house → the first number is lat, the second is lon. West longitudes are negative.

---

### 👆 "Touch isn't working / taps aren't registering"

Touch flows through a few layers, any of which can be wrong. Check the OTG cable first because it's the most common culprit on the budget build.

```bash
# 1. Is the touch controller enumerating as a USB device?
lsusb
# You should see something like "Cypress Semiconductor" or "Hailuck" or
# "Sino Wealth Electronic" — the exact vendor depends on your screen.

# 2. Is X actually receiving touch events?
DISPLAY=:0 xinput list
# Look for a device with "Touch" or "USB Touch" in its name.

# 3. Live-monitor touches (run, then tap the screen)
DISPLAY=:0 xinput test-xi2 --root
# If nothing prints when you tap, the touch hardware isn't reaching X.
```

| Symptom | Most likely cause | Fix |
|---|---|---|
| `lsusb` shows nothing for touch | OTG cable is wrong or backwards | Use a labeled **OTG** micro-USB-to-micro-USB cable, OTG end into the Pi's data port |
| `lsusb` sees the device, `xinput list` doesn't | X doesn't have permissions | Reboot — usually fixes it |
| `xinput list` sees it, taps don't work | Calibration drift | Run `xinput_calibrator` (`sudo apt install xinput-calibrator` first) |
| Taps register but the wrong spot lights up | Display rotation mismatch with touch matrix | Edit `/boot/firmware/config.txt`, set `display_rotate=2` (or whatever angle), reboot |

> 💡 **Pi data port vs. power port.** The Pi Zero 2 W has two micro-USB ports next to each other. The one closer to the corner of the board is **POWER ONLY**. The one in the middle is the **data port** — that's the one your touch cable goes into. Easy mistake to make on the first build. 🤦

---

### 🌙 "Display isn't sleeping at night / isn't waking up"

The sleep behavior is a software overlay (a full-screen black `<div>`), not actual hardware power-off. So:

```javascript
// app/public/index.html — top of the script section
const SLEEP_HOUR      = 0;      // midnight
const WAKE_HOUR       = 6;      // 6 AM
const WAKE_TIMEOUT_MS = 30000;  // 30 seconds of touch-wake before re-sleeping
```

| Symptom | Cause | Fix |
|---|---|---|
| Screen stays bright at midnight | Pi's clock is wrong (timezone) | `timedatectl` — fix with `sudo timedatectl set-timezone America/Chicago` |
| Sleep overlay covers screen but backlight is still on | Expected — we don't power off the panel by design | Add `xset dpms force off` to `goToSleep()` if you really want hardware sleep |
| Touch-to-wake doesn't dismiss overlay | JS error in console | Use [Chrome DevTools](#-chrome-devtools-the-secret-weapon) to check |

To change the sleep window: edit `app/public/index.html`, change those three constants, and `sudo systemctl restart calendar.service`. The browser will pick up the new file on its next 5-minute event poll, or you can hard-reload.

---

### 🌐 Network Issues

The Pi Zero 2 W has **2.4 GHz only**. No 5 GHz. If you put it on a network that only advertises 5 GHz, it cannot connect. Period.

```bash
# Is Wi-Fi associated?
iwconfig wlan0
# Look for ESSID, frequency, link quality

# Is there an IP address?
ip addr show wlan0
# Look for "inet 192.168.x.x"

# Can we reach the outside world?
ping -c 3 8.8.8.8       # raw IPv4 — tests routing
ping -c 3 google.com    # tests DNS
```

| Symptom | Cause | Fix |
|---|---|---|
| `iwconfig` shows no ESSID | Wi-Fi failed to associate | `sudo wpa_cli -i wlan0 reconfigure` |
| Has IP but `ping 8.8.8.8` fails | Default route missing or broken | `ip route show` — fix with `sudo dhclient -r wlan0 && sudo dhclient wlan0` |
| `ping 8.8.8.8` works but `ping google.com` doesn't | DNS broken | Add `nameserver 1.1.1.1` to `/etc/resolv.conf` |
| Wi-Fi keeps dropping | Weak signal at the wall | Move the AP, or live with it — the calendar gracefully shows last loaded events while offline |

> 💡 **Wi-Fi setup is permanent in the SD card.** If you ever change Wi-Fi networks, edit `/etc/wpa_supplicant/wpa_supplicant.conf` and reboot. Pre-configured Wi-Fi from the Imager only writes once during first boot.

---

### 🐀 Memory & Swap Pressure

The Zero 2 W has **512MB of RAM** and we've allocated a **1GB swap file**. If both fill up, the kernel starts OOM-killing processes — usually Chromium first, sometimes Node.

```bash
# Snapshot of memory + swap right now
free -h

# Live memory pressure
top -o %MEM
# Press 'q' to quit. Watch for chromium near 100% MEM.

# Has the OOM killer killed anything since boot?
journalctl -k | grep -i 'killed process'
# If you see entries for chromium or node — that's why your kiosk keeps dying.
```

| What `free -h` shows | What it means |
|---|---|
| `Mem: ~150Mi available, Swap: 0Mi used` | All good, breathing room. ✅ |
| `Mem: ~50Mi available, Swap: 200Mi used` | Normal under load — Chromium is using swap, but everything still works |
| `Mem: ~5Mi available, Swap: 950Mi+ used` | Death spiral imminent — page in/out is thrashing the SD card. Reboot. |

If you're chronically pressed for memory, the fixes (in order of effort):

1. **Reboot** — Chromium has a memory leak that builds up over weeks. A `sudo reboot` once a month is fine.
2. **Bump swap to 2GB** — edit `setup.sh`'s `SWAP_SIZE_MB=1024` to `2048`, but you'll need to delete `/swapfile-calendar` and re-run the script. Note the SD card wear cost.
3. **Drop the FullCalendar render quality** — already done on this branch (5-min event polling, 60-min weather polling). Not much else to take away.
4. **Switch to a Pi 5** — at which point you should be on the `main` branch, not this one. 😅

---

## 🔍 Chrome DevTools: The Secret Weapon

The kiosk's Chromium has `--remote-debugging-port=9222` baked in, which means **you can attach Chrome DevTools to the wall display from your Mac.** This is by far the most powerful debugging tool in the project — full DOM inspection, console errors, network tab, the works.

### Setup (do once)

From your Mac:

```bash
# Forward the Pi's debug port to your Mac's localhost:9222
ssh -L 9222:localhost:9222 <username>@calendar.local
```

Leave that SSH session open. Now in **Chrome on your Mac**, navigate to:

```
chrome://inspect
```

Under "Remote Target" you'll see the kiosk's tab. Click **inspect**. You now have a full DevTools window pointed at the wall display. 🪄

### What you can do with it

- **Console errors** — see every JS error, network failure, weather API miss, etc. in real time
- **Network tab** — confirm `/api/events`, `/api/calendars`, `/api/weather` are returning 200 OK and what the JSON looks like
- **DOM inspection** — figure out why an event popover is positioning weirdly
- **Force-reload the kiosk** — Cmd+R in the DevTools window reloads the wall display from your Mac (useful after editing `index.html`)
- **`localStorage.clear()` and reload** — nuke any client-side state without rebooting

> 💡 **Security note:** `--remote-debugging-port=9222` listens on `localhost` only by default, so it's not exposed to the network. The `ssh -L` tunnel is what makes it reachable from your Mac. No security risk on a home LAN.

---

## 🆘 Last Resort: Full Reset

If you've reached the bottom of this doc and nothing has worked, here's the nuclear sequence. **Read all of it first** — `git pull` will fail if you have uncommitted local changes, and the credential delete will require you to paste your iCloud password again.

```bash
# 1. Get the latest version of the code
cd ~/calendar-app
git fetch origin
git checkout pi-zero-2w
git pull

# 2. Reinstall Node deps (in case package.json changed)
cd app
npm install
cd ..

# 3. Wipe vdirsyncer state and re-run setup
#    ⚠️ This will re-prompt for your iCloud app-specific password.
rm -rf ~/.local/share/vdirsyncer ~/.local/share/calendar
rm  ~/.config/vdirsyncer/config

bash scripts/setup.sh

# 4. Reboot to relaunch the kiosk cleanly
sudo reboot
```

If *that* doesn't fix it, open a GitHub issue with:

- Output of `systemctl status calendar.service`
- Last 50 lines of `journalctl -u calendar.service`
- Last 30 lines of `~/.local/share/vdirsyncer/sync.log`
- Contents of `/tmp/kiosk.log`
- The output of `free -h` and `uname -a`

That's enough info to debug 95% of issues remotely. We'll figure it out together. 🤝

---

## 🤖 A Note from the AI

Hi! 👋 I helped build most of this project. If you're reading this troubleshooting doc, something's gone wrong, and I'm sorry — I tried my best, but RFC 5545, Chromium's GPU pipeline, vdirsyncer's collection discovery, and the Pi Zero 2 W's 512MB of RAM are all individually finicky, and combining them into a single working appliance involves more edge cases than any one of us would like to admit.

Most failures fall into one of these buckets, ranked by how often they bite:

1. **Wi-Fi flaked out** (50%) — reboot usually fixes it
2. **iCloud app-specific password got revoked** (20%) — regenerate at appleid.apple.com
3. **Chromium accumulated session-restore cruft** (15%) — autostart already wipes this on each launch, but if you've manually run Chromium under SSH...
4. **OOM killer struck during heavy use** (10%) — bump swap or accept monthly reboots
5. **Genuinely new bug we haven't seen yet** (5%) — please open an issue!

Good luck. May your `.ics` files always parse and your weather emoji always render. 🌦️

— *Built with ❤️ and a concerning amount of `.ics` file knowledge.*
