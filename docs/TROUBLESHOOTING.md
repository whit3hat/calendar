# 🩺 Troubleshooting Guide — Pi Zero 2 W v2

> So something broke. Welcome to the wonderful world of running a Wayland kiosk on a $15 single-board computer with 512MB of RAM. This document is the result of a *lot* of late nights, several existential crises about whether HTML5 browsers belong on this hardware at all, and one weekend-long pivot that ended in writing 3,500 words of architecture doc to justify rebuilding the entire display stack. We've been there. Let's get you unstuck. 💙

> 🧭 **Looking for the design rationale instead of a fix?** See [`V2-ARCHITECTURE.md`](./V2-ARCHITECTURE.md) for why v2 looks the way it looks (Wayland instead of X11, no swap instead of lots of swap, native GPU instead of SwiftShader, watchdog-as-first-class).

---

## 🚀 30-Second Cheatsheet

Try these in order. Most things get fixed by one of the first three.

```bash
# 1. Did you try turning it off and on again?
sudo reboot

# 2. Restart just the kiosk session (kills Chromium, greetd respawns labwc + autostart)
sudo systemctl restart greetd

# 3. Restart just the calendar app (Node/Express on :8080)
sudo systemctl restart calendar.service

# 4. Did the watchdog already give up and reboot the Pi?
journalctl -u kiosk-watchdog.service --since "1 hour ago"

# 5. Is the calendar server actually serving?
curl -sf http://localhost:8080/ && echo "✅ server responding" || echo "❌ server is dead"

# 6. Are events syncing from iCloud?
tail -20 ~/.local/share/vdirsyncer/sync.log
```

If those don't fix it, scroll down to the symptom that matches what you're seeing.

---

## 📍 Where the Logs Live

The Pi has logs scattered across systemd's journal, the vdirsyncer cron output, and `/dev/shm`. Here's the map.

| What broke | Where the logs are | How to read them |
|---|---|---|
| 📅 Calendar app (Node/Express) | systemd journal | `sudo journalctl -u calendar.service -f` |
| 🖥️ Kiosk session (labwc + Chromium) | systemd journal + `/tmp/kiosk.log` if older | `sudo journalctl -u greetd -f` |
| 🛡️ Watchdog (restart escalation) | systemd journal | `sudo journalctl -u kiosk-watchdog.service` |
| 💣 Watchdog (reboot escalation) | systemd journal | `sudo journalctl -u kiosk-reboot.service` |
| 📡 vdirsyncer (iCloud sync) | log file (cron output) | `tail -f ~/.local/share/vdirsyncer/sync.log` |
| 🔌 Wi-Fi / wpa_supplicant | systemd journal | `sudo journalctl -u wpa_supplicant@wlan0 -f` |
| 🌐 Networking (interface state) | journalctl | `journalctl -u networking -f` |
| 🧠 Kernel (OOM kills, hardware errors) | dmesg | `sudo dmesg --human --follow` |
| 🫀 Heartbeat file | `/dev/shm/kiosk-heartbeat` | `stat /dev/shm/kiosk-heartbeat` shows mtime |
| ⚙️ Boot params | `/boot/firmware/config.txt` + `/boot/firmware/cmdline.txt` | `cat` them |
| 🎛️ Runtime config | `/boot/firmware/calendar.env` | `cat /boot/firmware/calendar.env` |
| 🪧 Greetd config | `/etc/greetd/config.toml` | `cat /etc/greetd/config.toml` |
| 🧩 Labwc autostart | `~/.config/labwc/autostart` | `cat ~/.config/labwc/autostart` |
| ⏰ All systemd timers (incl. watchdogs) | `systemctl list-timers` | `systemctl list-timers --all` |

---

## 🔧 Common Operations

```bash
# Show all v2-relevant logs together (the Big Picture™)
sudo journalctl -u calendar.service -u greetd -u kiosk-watchdog.service -u wpa_supplicant@wlan0 -f

# Check service status (✅ active, ❌ failed, 💤 inactive)
systemctl status calendar.service greetd kiosk-watchdog.timer kiosk-reboot.timer

# When did the heartbeat last update? (Tells you if Chromium is alive and pinging)
stat -c '%y mtime  (%Y epoch)' /dev/shm/kiosk-heartbeat

# What watchdog timer fires next?
systemctl list-timers --all kiosk-watchdog.timer kiosk-reboot.timer

# Free RAM and swap (swap should ALWAYS be 0 on v2 — see "Why no swap?" below)
free -h

# What's eating the memory?
ps aux --sort=-%mem | head -15

# Test the calendar API locally
curl -s http://localhost:8080/api/heartbeat
curl -s http://localhost:8080/api/events | head -c 500

# Manually trigger an iCloud sync
vdirsyncer sync

# Force the kiosk to reload (kills Chromium; labwc autostart relaunches it)
pkill -x chromium

# Test kiosk launch manually (replicates exactly what labwc autostart does)
chromium --kiosk --no-memcheck --process-per-site --enable-low-end-device-mode \
  --autoplay-policy=no-user-gesture-required --noerrdialogs \
  --disable-session-crashed-bubble --disable-features=Translate \
  --ozone-platform=wayland --start-fullscreen http://localhost:8080
```

---

## 🩺 Symptom Index

Click the one that matches what you're seeing:

- [⬜ The wall went white and stayed white](#-the-wall-went-white-and-stayed-white)
- [⬛ The wall went black and stayed black](#-the-wall-went-black-and-stayed-black)
- [🐢 Touch is slow / SSH is slow / everything is slow](#-touch-is-slow--ssh-is-slow--everything-is-slow)
- [📡 Events aren't syncing from iCloud](#-events-arent-syncing-from-icloud)
- [🌧️ Weather widget is stuck, missing, or wrong](#️-weather-widget-is-stuck-missing-or-wrong)
- [😴 Display won't sleep / won't wake](#-display-wont-sleep--wont-wake)
- [📶 Wi-Fi won't connect / Pi has no network](#-wi-fi-wont-connect--pi-has-no-network)
- [🛡️ Watchdog keeps restarting Chromium](#️-watchdog-keeps-restarting-chromium)
- [💀 Pi keeps rebooting itself](#-pi-keeps-rebooting-itself)
- [⌨️ On-screen keyboard isn't appearing in the Add Event modal](#️-on-screen-keyboard-isnt-appearing-in-the-add-event-modal)
- [🔍 I want to inspect Chromium with DevTools from my laptop](#-i-want-to-inspect-chromium-with-devtools-from-my-laptop)
- [💣 Nothing works, I want to start over](#-nothing-works-i-want-to-start-over)

---

## ⬜ The Wall Went White and Stayed White

A white screen means **Chromium launched but the page didn't load (or loaded blank)**. Different from black, which means Chromium never came up.

```bash
# 1. Is the calendar server actually serving?
curl -sf http://localhost:8080/ && echo "✅ alive" || echo "❌ dead"

# 2. If dead, restart it and watch logs
sudo systemctl restart calendar.service
sudo journalctl -u calendar.service -f

# 3. If alive, the issue is in Chromium. Restart the kiosk session:
sudo systemctl restart greetd

# 4. If still white after restart, check if Chromium is actually running:
pgrep -af chromium

# 5. If Chromium is running but page is white, it might be on about:blank.
#    Inspect via DevTools (see "I want to inspect Chromium" section).
```

**Common causes:**
- 🐌 Calendar server hadn't started yet when labwc autostart tried to launch Chromium → labwc autostart's curl-poll should prevent this; check `journalctl -u greetd -t kiosk-autostart` to confirm it waited
- 🧠 Chromium ran out of memory mid-load and the renderer died silently → check `dmesg | grep -i killed` for OOM evidence; if found, the watchdog should restart greetd within 5 minutes
- 🌐 Vendored FullCalendar JS file wasn't loaded for some reason → check `ls ~/calendar-app/app/public/vendor/fullcalendar/` to confirm `index.global.min.js` exists; if missing, re-run `bash ~/calendar-app/scripts/setup.sh` to repair
- 🐛 An actual JS error in `index.html` after a recent edit → see DevTools section to inspect the console

---

## ⬛ The Wall Went Black and Stayed Black

A black screen means **labwc never launched, OR Chromium never launched on top of it, OR the display went into hardware sleep and won't wake**. (Or it's between midnight and 6 AM and the calendar's sleep schedule is doing its job.)

```bash
# 1. What time is it? Sleep schedule fires at midnight; wakes at 6 AM by default.
date
# If it's between SLEEP_HOUR and WAKE_HOUR, this is normal — touch the screen to wake.

# 2. Is greetd alive?
systemctl status greetd

# 3. Is labwc alive?
pgrep -af labwc

# 4. Is Chromium alive?
pgrep -af chromium

# 5. Did the watchdog reboot the Pi recently? (Look for a recent boot in journal)
journalctl --list-boots | head -5

# 6. Restart everything:
sudo systemctl restart greetd
```

**Common causes:**
- 😴 You're in the sleep window (default midnight–6 AM) — touch the screen, the overlay should clear
- 💀 greetd failed to start → `journalctl -u greetd` will show why; usually a config typo in `/etc/greetd/config.toml`
- 🔌 The display went into hardware DPMS sleep and the wake signal isn't reaching it — try unplugging/replugging the HDMI cable
- 🧨 Chromium crash-looped past the watchdog's restart threshold and the watchdog rebooted the Pi → check `journalctl --list-boots`

---

## 🐢 Touch is Slow / SSH is Slow / Everything is Slow

This is the symptom that *killed v1*. On v2 this should be **basically impossible** — there is no swap, so the system either fits in RAM or OOM-kills (recoverable). If you're seeing this on v2, something is wrong.

```bash
# 1. Confirm there is no swap (should show 0 / 0)
free -h | grep -i swap

# 2. If swap is non-zero, somebody enabled it — disable it immediately
sudo swapoff -a
# Then find and remove it:
sudo find / -name "swapfile*" 2>/dev/null
# Edit /etc/fstab to remove any swap entries:
sudo nano /etc/fstab

# 3. What's eating memory?
free -h
ps aux --sort=-%mem | head -10

# 4. Load average (4 = fully utilized 4 cores; 9+ = trouble even on v2)
uptime

# 5. Check for OOM kills
sudo dmesg | grep -i killed | tail -10
```

**If load average is high but CPU usage is low** (the v1 "9.34 with CPU at 6%" pattern), you have I/O wait. On v2 with no swap, this can only come from:
- 🐢 A process doing huge SD-card I/O (probably vdirsyncer doing initial sync of a giant calendar) — wait it out
- 🧱 A wedged kernel driver — `dmesg` will show errors
- 💾 A failing SD card — `dmesg` will show I/O errors; replace it

**If memory usage is genuinely high and OOM is killing things**, the watchdog should restart greetd within 5 min. If Chromium is the OOM victim, the watchdog catches that. If something else is the OOM victim (bash, sshd, etc.), the BCM2835 hardware watchdog will reboot the Pi within 30s if systemd itself wedges.

---

## 📡 Events Aren't Syncing from iCloud

```bash
# 1. Manually run a sync and see what happens
vdirsyncer sync

# 2. Watch the log
tail -50 ~/.local/share/vdirsyncer/sync.log

# 3. Confirm the cron job exists
crontab -l | grep vdirsyncer

# 4. Confirm vdirsyncer is even installed (it's in pipx, not apt)
which vdirsyncer
pipx list | grep vdirsyncer

# 5. Check if .ics files are actually being written
ls -la ~/.local/share/calendar/*/  | head -20
```

**Common causes:**
- 🔑 App-specific password expired or got revoked from Apple ID → regenerate at appleid.apple.com and re-run setup.sh
- 🌐 Wi-Fi dropped → check `ip route get 1.1.1.1` returns a route
- 🆕 Added a new shared calendar in Apple Calendar but vdirsyncer hasn't picked it up → run `vdirsyncer discover family_calendar`
- 📄 Calendar names contain weird characters that vdirsyncer can't handle → use `bash scripts/restrict-calendars.sh` to pick which ones to sync
- 🪪 PATH issue: the cron job uses `/home/pi/.local/bin/vdirsyncer` (full path) — if that doesn't exist, pipx install path may have changed

---

## 🌧️ Weather Widget Is Stuck, Missing, or Wrong

```bash
# 1. Test the API endpoint directly
curl -s http://localhost:8080/api/weather | head -c 500

# 2. Check the runtime config (lat/lon/units)
cat /boot/firmware/calendar.env

# 3. Force a fresh fetch by restarting the calendar service
sudo systemctl restart calendar.service

# 4. Check if Open-Meteo is reachable from the Pi
curl -sf "https://api.open-meteo.com/v1/forecast?latitude=39.2461&longitude=-94.4192&current=weathercode" \
  | head -c 200
```

**Common causes:**
- 🌍 Lat/lon defaults to Liberty, MO — change `WEATHER_LAT` and `WEATHER_LON` in `/boot/firmware/calendar.env`, then `sudo systemctl restart calendar.service`
- 🧊 Server cache is 60 minutes — after a network outage, weather can lag up to an hour
- 🌐 Open-Meteo unreachable → server keeps showing stale cache (this is correct behavior)
- 🐛 If `/api/weather` returns 503, the cache is cold and Open-Meteo is unreachable; will recover when network returns

---

## 😴 Display Won't Sleep / Won't Wake

The sleep overlay is a software-only mechanism in `index.html` — it just paints a black overlay over the calendar between `SLEEP_HOUR` and `WAKE_HOUR`. The display backlight stays on; only the rendered content goes dark.

```bash
# 1. Check the configured schedule (defaults: midnight to 6 AM)
grep -E "SLEEP_HOUR|WAKE_HOUR|WAKE_TIMEOUT_MS" ~/calendar-app/app/public/index.html

# 2. Check the Pi's current local time (if wrong, ntpsec will fix on next sync)
date
timedatectl
```

**Common causes:**
- 🕐 Pi's clock is wrong → `timedatectl` should show NTP synced; if not, `sudo systemctl restart systemd-timesyncd`
- 🌙 You changed the schedule but didn't restart Chromium → `sudo systemctl restart greetd` to reload the page
- 💡 Backlight stays on (intentional — software sleep is overlay-based) → if you want hardware backlight off, you'll need a `wlr-randr --output HDMI-A-1 --off` cron entry, but that's beyond stock v2

---

## 📶 Wi-Fi Won't Connect / Pi Has No Network

v2 uses **ifupdown + wpa_supplicant** (NetworkManager was removed because it ate ~30MB of RAM). This is a different flow than stock RPi OS, and `sudo raspi-config` won't manage it.

```bash
# 1. Is the Wi-Fi interface up?
ip addr show wlan0

# 2. Is wpa_supplicant alive?
systemctl status wpa_supplicant@wlan0

# 3. What does it see?
sudo iw dev wlan0 scan | grep SSID | head -10

# 4. What does it think it's configured to connect to?
sudo cat /etc/wpa_supplicant/wpa_supplicant-wlan0.conf

# 5. Force reconnect
sudo systemctl restart wpa_supplicant@wlan0
sudo ifdown wlan0; sudo ifup wlan0

# 6. Does Pi have an IP?
ip route get 1.1.1.1
```

**To change Wi-Fi network:** edit `/etc/wpa_supplicant/wpa_supplicant-wlan0.conf` (the `ssid="..."` and `psk="..."` lines), then `sudo systemctl restart wpa_supplicant@wlan0`. Or just re-run `bash scripts/setup.sh` — it'll re-prompt if you have no network.

**Don't run `sudo raspi-config` for Wi-Fi.** It tries to use NetworkManager, which we deliberately removed. Edit the wpa_supplicant config directly.

---

## 🛡️ Watchdog Keeps Restarting Chromium

If the watchdog is doing its job too often, that means Chromium is hanging too often. This is an indication of a real underlying problem, not a watchdog problem.

```bash
# 1. How often did the watchdog fire?
journalctl -u kiosk-watchdog.service --since "24 hours ago" | grep "restarting greetd"

# 2. Anything weird about the heartbeats? (mtime should update every 30s)
stat /dev/shm/kiosk-heartbeat

# 3. Watch heartbeat live (mtime should change every 30s)
watch -n1 'stat -c %Y /dev/shm/kiosk-heartbeat; date +%s'

# 4. Check if Chromium is consistently OOM-killed
sudo dmesg | grep -i "killed.*chrom"

# 5. Check if greetd is restarting cleanly
journalctl -u greetd --since "24 hours ago" | grep -i "start\|stop"
```

**Common causes:**
- 🧠 Persistent OOM kills → memory budget is tighter than expected; check `ps aux --sort=-%mem` for what's bigger than budget
- 🐛 A specific event in your calendar is breaking the renderer → look at the time of restart vs. event creation/edit times; try removing recently-added events
- 🌐 Frontend lost network briefly and `pingHeartbeat()` was failing for >5 min → unlikely with the 30s ping, but possible if Wi-Fi flaps badly

**If watchdog fires more than 2x in 24h, something is wrong.** Capture logs and grep through them; don't just let it keep cycling.

---

## 💀 Pi Keeps Rebooting Itself

Two reasons the Pi reboots: (1) `kiosk-reboot.service` escalated because the heartbeat was stale > 15 min, (2) BCM2835 hardware watchdog fired because systemd itself wedged.

```bash
# 1. List recent boots — frequency tells you if this is happening repeatedly
journalctl --list-boots | head -10

# 2. Check the last shutdown reason
journalctl -u kiosk-reboot.service --since "24 hours ago"

# 3. Check kernel ring buffer for the previous boot for hints about what wedged
journalctl -k -b -1 | tail -50

# 4. Disable the reboot escalation temporarily while you debug (DO NOT FORGET TO RE-ENABLE)
sudo systemctl stop kiosk-reboot.timer
# When done debugging:
sudo systemctl start kiosk-reboot.timer
```

**If the Pi reboots within minutes of every boot**, you're stuck in a loop. SSH in fast and:
- `sudo systemctl stop kiosk-reboot.timer` to halt the escalation
- Then debug calmly with the watchdog disabled
- Re-enable when fixed

---

## ⌨️ On-Screen Keyboard Isn't Appearing in the Add Event Modal

The OSK is implemented in JavaScript inside `index.html` — there's no system-level component, so OS-level changes don't affect it.

```bash
# 1. Check if there are JS errors in the page (use DevTools — see next section)

# 2. Hard-refresh the page to bust any cached state
sudo systemctl restart greetd

# 3. Check the OSK init code in index.html (look for "OSK init failed")
journalctl -u greetd | grep -i "OSK init"
```

If the OSK is failing init, the form still works for keyboard input — but on a touchscreen-only deployment, that means you can't type at all. Restart greetd; if that doesn't work, the `index.html` may be from an incomplete update.

---

## 🔍 I Want to Inspect Chromium With DevTools From My Laptop

The default Chromium kiosk launch in v2 doesn't enable remote debugging (one less attack surface). Add it temporarily for a debug session:

```bash
# 1. On the Pi, edit the labwc autostart
nano ~/.config/labwc/autostart
# Add this flag to the chromium command:
#   --remote-debugging-port=9222

# 2. Restart the kiosk
sudo systemctl restart greetd

# 3. From your laptop, SSH-tunnel the debug port
ssh -L 9222:localhost:9222 pi@<pi-ip>

# 4. In Chrome on your laptop, open chrome://inspect
#    Click "Configure..." and add localhost:9222
#    The Chromium tab on the Pi will appear under "Remote Target"
#    Click "inspect" to get DevTools
```

**Don't forget to remove the `--remote-debugging-port=9222` flag when you're done.** Leaving it on means anyone on your LAN can drive your Chromium remotely.

---

## 💣 Nothing Works, I Want to Start Over

The full reset sequence. Use when you've changed too many things and don't know what state you're in.

```bash
# 1. SSH in (don't try this from the wall display)

# 2. Backup your iCloud config (you DO NOT want to lose this — it has your app password)
cp ~/.config/vdirsyncer/config ~/vdirsyncer-config-backup-$(date +%Y%m%d)

# 3. Stop everything
sudo systemctl stop kiosk-watchdog.timer kiosk-reboot.timer
sudo systemctl stop greetd
sudo systemctl stop calendar.service

# 4. Re-run the setup script — it's idempotent and will repair anything broken
cd ~/calendar-app
bash scripts/setup.sh

# 5. Reboot
sudo reboot

# 6. If THAT doesn't fix it, you've earned a reflash:
#    - Pop the SD card into another computer
#    - Use Raspberry Pi Imager to flash a fresh Raspberry Pi OS Lite (64-bit)
#    - SSH in
#    - git clone -b pi-zero-2w-v2 https://github.com/whit3hat/calendar.git calendar-app
#    - bash calendar-app/scripts/setup.sh
#    - Restore your vdirsyncer config from backup if needed
```

---

## 📚 Why v2 Looks the Way It Looks

If you're confused about why v2 chose Wayland over X11, why there's no swap, why Chromium has so few flags, or why a heartbeat watchdog exists at all — read [`V2-ARCHITECTURE.md`](./V2-ARCHITECTURE.md). It walks through every decision, the v1 failure that motivated each change, the two reference projects we studied (TOLDOTECHNIK and AnotterKiosk), and the memory budget that justifies running this on a 512MB box without swap.

The TL;DR for the impatient:

- **Wayland + labwc** instead of X11 + openbox: lighter (~40MB saved), Chromium gets native VC4 GL "for free" without the `chromium.d` wrapper fight
- **No swap** instead of 1GB SD-card swap: SD-card swap on a 512MB box is a thrashing trap, not a safety net; without it, the kernel either fits in RAM or OOM-kills (recoverable)
- **Native VC4 KMS GL** instead of `--use-gl=swiftshader`: hardware does the rendering instead of CPU, doubly cheaper on this hardware
- **Vanilla Chromium** instead of Firefox-ESR: Chromium's earlier crashes were a *symptom* of memory pressure, not a Chromium bug; switching browsers used more memory and didn't help
- **NetworkManager removed**, replaced with ifupdown + wpa_supplicant: saves ~30MB; the only price is `raspi-config` Wi-Fi management doesn't work
- **Heartbeat watchdog** exists because browsers occasionally hang on a single bad render and we refuse to require a human walking up to the wall with an SSH client to fix it

---

## 🆘 Still Stuck?

Open an issue on GitHub with:

1. What you're seeing (white screen / black screen / slow / wrong data / etc.)
2. Output of `sudo journalctl -u calendar.service -u greetd -u kiosk-watchdog.service --since "1 hour ago"`
3. Output of `free -h && uptime && systemctl status calendar.service greetd`
4. Output of `cat /boot/firmware/calendar.env` (with any sensitive values redacted)
5. What you tried from this guide

We're here to help. The wall is supposed to *just work* — when it doesn't, that's a bug worth fixing. 💙
