# Pi Zero 2 W — V2 Architecture

**Status:** Draft for review · **Branch:** `pi-zero-2w-v2` · **Author:** rebuild planning notes, May 2026

---

## TL;DR

The original `pi-zero-2w` branch hit unresolvable swap-thrashing on real hardware (load avg 9.34 / CPU 6% — textbook I/O wait on SD card). After studying two production Pi-Zero-class kiosk projects ([TOLDOTECHNIK](https://github.com/TOLDOTECHNIK/Raspberry-Pi-Kiosk-Display-System) and [AnotterKiosk](https://github.com/Manawyrm/AnotterKiosk)), we're rebuilding the Pi Zero 2 W variant from scratch on top of a different display-server / GL / browser / supervision stack. The Node + Express backend, FullCalendar UI, vdirsyncer sync, weather widget, and edit/delete features all carry forward unchanged. **Everything below the application layer changes.**

The expected win: working set drops from ~250–470MB (v1) to ~310–380MB (v2) inside ~416MB usable RAM. Combined with **zero swap** (instead of v1's 1GB SD-card swap), the kernel either fits in RAM or OOM-kills with watchdog recovery — no thrashing path exists anymore.

---

## Why we're rebuilding (the v1 reckoning)

We made six architectural decisions in v1 that all turned out to be wrong on this hardware. Both reference projects independently chose the opposite on every one:

| v1 decision | What both reference projects do | Why v1 was wrong |
|---|---|---|
| 1GB SD-card swap + `vm.swappiness=10` | **No swap on SD card.** AnotterKiosk explicitly removes `rpi-swap` AND `systemd-zram-generator` | SD-card swap on a 512MB box doesn't expand effective memory — it creates a thrashing trap. Random SD reads at ~10MB/s become the bottleneck for *every* userspace process. The htop screenshot proved this. |
| X11 + openbox + `.bash_profile`→`startx` | **Display manager** (greetd or LightDM) → **Wayland/labwc** or X11+LightDM | Shell-rc auto-startx has zero crash recovery. A real DM auto-restarts the session. Wayland/labwc is also ~40MB lighter than X11/openbox. |
| Chromium with `--use-gl=swiftshader` (forced software rendering) | **Native VC4/V3D hardware GL** via Wayland/Ozone or vc4-kms-v3d dtoverlay | We forced software rendering to escape the Debian Chromium wrapper's `chromium.d` flag fights. The right answer was to switch the display server, not the GL backend. SwiftShader burns CPU instead of using the GPU, doubly costly on this hardware. |
| Firefox-ESR pivot after Chromium "failed" | **Vanilla Chromium** with `--no-memcheck --kiosk --process-per-site --enable-low-end-device-mode` | The Chromium network-service crashes were a *symptom* of memory pressure (swap thrashing destabilizes the IPC layer), not a Chromium bug. Switching browsers didn't address the root cause; it just used more memory. |
| Default Raspberry Pi OS install (NetworkManager, Bluetooth, avahi, ModemManager, all defaults) | **Selectively stripped** — Bluetooth, avahi, ModemManager, dphys-swapfile, triggerhappy, plymouth removed; NetworkManager kept after the first deploy taught us why ([commit 084d184](#)) | NetworkManager alone is ~30–40MB resident, but removing it mid-setup over SSH kills the user's connection before any replacement networking can come up. We accept the ~30MB cost for SSH safety. Bluetooth + avahi + ModemManager + plymouth still account for ~50MB resident saved. |
| No watchdog — if browser hangs, wall stays blank until manual reboot | **Heartbeat watchdog** that restarts session on stale heartbeat, reboots on persistent failure | Browsers occasionally hang on a single bad render, even with all other things right. We need a recovery path that doesn't require a human walking up to the wall with an SSH client. |

V2 reverses all six.

---

## Reference projects (the inputs to this design)

**[TOLDOTECHNIK Raspberry-Pi-Kiosk-Display-System](https://github.com/TOLDOTECHNIK/Raspberry-Pi-Kiosk-Display-System)** — One 400-line bash setup script. Stock Raspberry Pi OS Lite Bookworm. Wayland + labwc + greetd. Vanilla Chromium with minimal flags. No swap. Targets generic kiosks pointing at remote URLs. *Their key insight: the display server is the right place to optimize, not the browser.*

**[Manawyrm AnotterKiosk](https://github.com/Manawyrm/AnotterKiosk)** — Custom Debian image with read-only root + tmpfs overlays. X11 + LightDM + openbox + Chromium. PHP heartbeat watchdog. Aggressively stripped userspace. Pi Zero 2 W explicitly first-class. *Their key insight: don't trust the browser to stay alive — build recovery as a first-class feature.*

V2 takes the **display stack from TOLDOTECHNIK** (Wayland is the modern direction; native GL is non-negotiable on this hardware) and the **service-stripping + watchdog patterns from AnotterKiosk** (the recovery story is what turns "works in lab" into "works for a year on the wall"). We deliberately skip AnotterKiosk's RO-root custom image — it's a 5-10x engineering investment and only pays off if we ship multiple Pis. Defer to a hypothetical V3 hardening pass if needed.

---

## The V2 stack

```
┌─────────────────────────────────────────────────────────────────┐
│ Application layer (UNCHANGED from v1 — cherry-picked verbatim)  │
├─────────────────────────────────────────────────────────────────┤
│  Chromium (vanilla, --kiosk --no-memcheck                       │
│            --enable-low-end-device-mode --process-per-site)     │
│              ↓ renders                                          │
│  http://localhost:8080  ←  served by Node.js + Express          │
│              ↑ reads                                            │
│  ~/.local/share/calendar/*.ics  ←  written by vdirsyncer cron   │
│              ↑ syncs every 5 min                                │
│  iCloud CalDAV                                                  │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ Display + supervision (NEW in v2)                               │
├─────────────────────────────────────────────────────────────────┤
│  greetd (vt7, autologin)  →  labwc (Wayland compositor)         │
│              ↓ autostart                                        │
│  wait-for-localhost-8080  →  Chromium kiosk                     │
│                                                                 │
│  kiosk-watchdog.timer (every 60s)                               │
│     reads /dev/shm/kiosk-heartbeat mtime                        │
│     if stale > 5 min: pkill chromium && systemctl restart greetd│
│     if still stale after restart: reboot                        │
└─────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────┐
│ OS layer (heavily stripped from v1)                             │
├─────────────────────────────────────────────────────────────────┤
│  Raspberry Pi OS Lite Bookworm 64-bit                           │
│  Networking: NetworkManager (kept — see commit 084d184)         │
│  Removed: bluetooth, avahi-daemon, ModemManager, dphys-swapfile,│
│           triggerhappy, ModemManager, plymouth                  │
│  No swap file. No zram. vm.swappiness irrelevant (no swap).    │
│  GPU memory split: gpu_mem=64 (default — needed for VC4 KMS)   │
│  dtoverlay=vc4-kms-v3d  ← enables native hardware GL            │
└─────────────────────────────────────────────────────────────────┘
```

### Component-by-component decisions

**Display server: Wayland + labwc.** labwc is a tiny wlroots-based stacking compositor (~5MB resident). Chromium's Wayland/Ozone backend uses VC4 KMS DRM directly for GL acceleration — no `--use-gl=swiftshader`, no `--disable-gpu`, no wrapper bypass. Just `chromium --kiosk --ozone-platform=wayland $URL`. *This single change is probably worth more than every other v2 improvement combined.*

**Login manager: greetd.** Minimal (~3MB), purpose-built for autologin → compositor. Configured via `/etc/greetd/config.toml`:
```toml
[terminal]
vt = 7
[default_session]
command = "/usr/bin/labwc"
user = "pi"
```

**Browser: vanilla Chromium.** Same browser as v1 originally; we're un-pivoting from Firefox-ESR. Launch flags (in `~/.config/labwc/autostart`):
```bash
chromium \
  --kiosk \
  --no-memcheck \
  --process-per-site \
  --enable-low-end-device-mode \
  --autoplay-policy=no-user-gesture-required \
  --noerrdialogs \
  --disable-session-crashed-bubble \
  --disable-features=Translate \
  --ozone-platform=wayland \
  http://localhost:8080
```
Notably absent: `--use-gl=*`, `--disable-gpu`, `--memory-pressure-off`, `--disable-dev-shm-usage`, profile-wipe scripts, `chromium.d` overrides. We don't need any of that on Wayland.

**Networking: NetworkManager (kept).** Originally planned to swap NM for ifupdown + wpa_supplicant for ~30MB savings. The first v2 deploy proved why this was wrong: removing NM mid-script over SSH killed the user's connection before any replacement networking could be installed and configured. The architecture had a fundamental sequence-dependency bug. v2 keeps NetworkManager — manage Wi-Fi via the Imager's pre-flash settings, `nmtui`, or `raspi-config`. A future hardening pass could defer the network swap to a one-shot systemd unit that runs post-reboot when no SSH session is at risk, but that's V3 work.

**Process supervision: systemd, three units.**
- `calendar.service` — Node app (carried forward from v1, unchanged)
- `kiosk-watchdog.timer` + `.service` — runs every 60s, checks heartbeat mtime
- `greetd.service` — manages the kiosk session (auto-restarts labwc if compositor dies)

**Watchdog mechanism:**
- Frontend (`index.html`): `setInterval(() => fetch('/api/heartbeat'), 30_000)`
- Backend (`server.js`): `app.get('/api/heartbeat', (_, res) => { fs.utimesSync('/dev/shm/kiosk-heartbeat', new Date(), new Date()); res.send('ok') })`
- `kiosk-watchdog.service` (called by .timer every 60s):
  ```bash
  HEARTBEAT=/dev/shm/kiosk-heartbeat
  if [[ ! -f $HEARTBEAT ]] || [[ $(($(date +%s) - $(stat -c %Y $HEARTBEAT))) -gt 300 ]]; then
    echo "heartbeat stale — restarting kiosk"
    pkill -x chromium
    sleep 2
    systemctl restart greetd
  fi
  ```
- Reboot escalation: if a separate `kiosk-watchdog-reboot.service` finds heartbeat stale > 15 min, `systemctl reboot`. (Implemented as a second timer with longer interval to avoid reboot loops.)

**No swap.** No `/swapfile-calendar`. No `vm.swappiness=10`. The setup script removes `dphys-swapfile` (`apt remove dphys-swapfile`). If we OOM, we OOM — the watchdog handles it. This is exactly AnotterKiosk's posture and is non-negotiable: SD-card swap is the disease, not the cure.

**Runtime config: `/boot/firmware/calendar.ini`.** Per-deployment settings (calendar URL, weather lat/lon, sleep/wake hours, timezone) live in an INI on the FAT32 boot partition. Easy to edit from any computer by popping the SD card; doesn't require SSH. setup.sh writes the initial file from interactive prompts; calendar.service reads it on start.

---

## Memory budget

**Available:** 512MB physical − ~64MB GPU (vc4-kms-v3d default) − ~32MB kernel reserved = **~416MB usable for userspace**.

**v2 target footprint (resident):**
| Component | RAM (resident) |
|---|---|
| Linux kernel + base userspace + systemd | ~80MB |
| NetworkManager + sshd + dbus + journald | ~55MB |
| greetd + labwc + seatd | ~30MB |
| Chromium (low-end-device-mode, single content process) | ~120–180MB |
| Node.js + Express (calendar.service) | ~50–70MB |
| vdirsyncer (idle; ~25MB only during 5-min cron run) | ~0MB |
| kiosk-watchdog | ~5MB |
| **Total resident** | **~340–420MB** |
| **Headroom** | **~−4 to 76MB** |

**v1 footprint (resident, measured):** ~250MB + 379MB swap = ~629MB working set on a 416MB system. The ~213MB excess thrashed against SD card.

**Tight, not comfortable.** With NetworkManager kept (post-first-deploy lesson), headroom drops to a worst-case 4MB negative — meaning at the high end of every component's range, we're 4MB over budget. In practice Chromium with low-end-device-mode + low-end Wayland workload runs closer to 120–140MB, leaving genuine headroom of 30–60MB. If Chromium drifts upward over hours (which it will), the watchdog catches it via OOM before the system enters death spiral. If headroom proves consistently negative in soak testing, the V3 hardening pass should defer NM removal to a post-reboot systemd unit.

---

## Boot sequence (cold start to first paint)

| t (sec) | What happens |
|---|---|
| 0 | Power on |
| 0–15 | Bootloader, kernel, initramfs |
| 15–25 | systemd starts, mounts, journald, syslog |
| 25–35 | NetworkManager brings up Wi-Fi, dhcp lease (skipped if no network) |
| 30–40 | calendar.service starts (Node + Express on :8080) |
| 25–35 | greetd starts on vt7 (parallel with calendar.service) |
| 35–45 | greetd autologin → labwc compositor up |
| 40–50 | labwc autostart polls `until curl -s http://localhost:8080/` |
| 50–70 | Chromium launches, fetches page, parses + renders FullCalendar |
| **60–90** | **First calendar paint** |

Subsequent reboots: ~45–60s as Chromium's profile cache warms.

If the calendar.service is slow to start (rare — Node cold-start is ~5s), labwc autostart will spin in the curl loop without launching Chromium, so the user sees a black screen instead of an error page. Acceptable.

---

## Failure modes & recovery

| Failure | Detection | Recovery | Time to recovery |
|---|---|---|---|
| Node app crashes | systemd notices process exit | `Restart=always` on calendar.service | ~5s |
| Chromium tab hangs (no JS execution) | Heartbeat goes stale; watchdog timer fires | pkill chromium → restart greetd | ~60–120s |
| labwc compositor crashes | greetd notices session exit | greetd respawns labwc | ~10–30s |
| Wi-Fi disconnects | Calendar continues serving last `.ics` files | UI shows "showing last loaded data" banner; vdirsyncer reconnects on next 5-min cron run | resumes when network returns |
| OOM kills Chromium | systemd notices greetd's child died | greetd restarts session | ~30–60s |
| OOM kills Node | systemd notices calendar.service died | systemd restarts calendar.service; Chromium retries fetch | ~10–20s |
| Watchdog itself hangs | (Hardest case) | Hardware watchdog timer (`bcm2835_wdt` kernel module + `RuntimeWatchdogSec` in systemd) | ~30s |
| SD card corruption | None automatic; would need manual investigation | Reflash + restore vdirsyncer config from backup | manual |

The hardware watchdog (`bcm2835_wdt`) is enabled by adding `dtparam=watchdog=on` to `/boot/firmware/config.txt` and `RuntimeWatchdogSec=30s` to `/etc/systemd/system.conf`. If systemd itself wedges, the BCM SoC reboots automatically.

---

## File-by-file changes

### Cherry-pick verbatim from `pi-zero-2w` branch
- `app/src/server.js` — backend (events, weather, calendars, edit/delete) + add `/api/heartbeat` endpoint
- `app/public/index.html` — frontend + add 30s heartbeat ping in existing `setInterval` block
- `app/public/vendor/fullcalendar/` — vendored FullCalendar v6.1.15 (CDN-avoidance lesson stays correct)
- `app/data/` — sample .ics files for local Mac development
- `systemd/calendar.service` — template stays valid; setup.sh substitution unchanged
- `scripts/restrict-calendars.sh` — vdirsyncer logic is independent of display stack
- `config/vdirsyncer.conf` — template stays
- `hardware/options.md` — Pi Zero 2 W content from v1 still accurate
- `.gitignore` — bring across UUID-named .ics exclusion

### Throw out from v1 (do NOT carry forward)
- v1's `scripts/setup.sh` Chromium block (SwiftShader flags, wrapper bypass, profile wipe, openbox autostart, .bash_profile auto-startx)
- v1's `scripts/setup.sh` swap creation (`/swapfile-calendar`, `vm.swappiness=10`)
- v1's openbox/Chromium-on-X11 assumptions
- The Firefox-ESR pivot work (none of it is in `setup.sh` anyway — was done by hand on the Pi)

### Add new in v2
- `scripts/setup.sh` — full rewrite, ~250 lines, see "Setup script outline" below
- `systemd/kiosk-watchdog.service` — restart kiosk if heartbeat stale
- `systemd/kiosk-watchdog.timer` — fires every 60s
- `systemd/kiosk-reboot.service` + `.timer` — escalation: reboot if stale > 15 min
- `config/labwc/autostart` — polls localhost, launches Chromium
- `config/labwc/rc.xml` — minimal compositor config
- `config/greetd/config.toml` — autologin + labwc
- `config/calendar.ini.template` — runtime config copied to `/boot/firmware/calendar.ini`
- `docs/V2-ARCHITECTURE.md` — this document
- `docs/TROUBLESHOOTING.md` — major rewrite for the new stack (carry forward v1's structure but replace all browser/X11 sections with Wayland/labwc/Chromium equivalents)

### Modify
- `CLAUDE.md` — replace the v1 branch banner with a v2 banner explaining Wayland+labwc+watchdog architecture
- `README.md` — update tech stack table, roadmap status, troubleshooting link

---

## Setup script outline (`scripts/setup.sh` v2)

Pseudocode of the new flow:

```
Step  1: System update + remove unwanted packages (NOT NetworkManager)
         apt remove bluetooth bluez avahi-daemon
                    modemmanager dphys-swapfile triggerhappy plymouth
         apt autoremove

Step  2: Install required packages (--no-install-recommends)
         apt install --no-install-recommends \
           greetd labwc seatd wlr-randr \
           chromium \
           nodejs npm \
           vdirsyncer \
           curl ca-certificates

Step  3: Verify network connectivity (NetworkManager handles Wi-Fi)
         If no network: abort with instructions to use Imager pre-flash,
         nmtui, or raspi-config to configure Wi-Fi, then re-run.

Step  4: Configure boot params (config.txt / cmdline.txt)
         Add: dtoverlay=vc4-kms-v3d
         Add: gpu_mem=64
         Add: dtparam=watchdog=on
         Remove: any v1 cgroup_disable=memory if present

Step  5: Configure iCloud / vdirsyncer (interactive credentials)
         Prompt for Apple ID + app-specific password
         Write ~/.config/vdirsyncer/config
         vdirsyncer discover + initial sync
         Install cron job: */5 * * * * vdirsyncer sync

Step  6: Install calendar app
         git clone or rsync to /home/pi/calendar-app
         npm install --production
         Install systemd/calendar.service (substitute __USER__/__APP_DIR__)
         systemctl enable --now calendar.service

Step  7: Install kiosk display stack
         Write /etc/greetd/config.toml (autologin pi → labwc)
         Write /home/pi/.config/labwc/autostart (curl-poll → chromium)
         Write /home/pi/.config/labwc/rc.xml (minimal)
         systemctl enable greetd
         systemctl set-default graphical.target

Step  8: Install watchdog
         Install systemd/kiosk-watchdog.{service,timer}
         Install systemd/kiosk-reboot.{service,timer}
         systemctl enable --now kiosk-watchdog.timer
         systemctl enable --now kiosk-reboot.timer

Step  9: Configure runtime defaults
         Copy config/calendar.ini.template to /boot/firmware/calendar.ini
         (Leaves it editable from any computer by popping the SD card)

Step 10: Configure systemd hardware watchdog
         Edit /etc/systemd/system.conf:
           RuntimeWatchdogSec=30s
           ShutdownWatchdogSec=10min

Step 11: Print "Ready — reboot now" and exit
```

Total install time on fresh SD card: ~15-20 min (mostly apt + npm install).

---

## Testing & validation

Before declaring v2 a success:

1. **Cold-boot timing.** Power off → power on → first paint. Target: under 90s. Acceptable: under 2 min. Failure: >3 min means something's wrong.
2. **Touch latency.** Tap an event → popover appears. Target: under 500ms. Acceptable: under 1.5s. Failure: >3s means we're still hitting memory pressure somehow.
3. **24-hour soak.** Leave the wall running for a full day. Check `journalctl -u kiosk-watchdog.service -u greetd.service -u calendar.service`. Target: zero watchdog restarts. Acceptable: ≤2 watchdog restarts. Failure: ≥1 reboot escalation.
4. **Memory under sustained load.** After 24h, `free -h` should show >50MB available and no swap (since we removed it). If kernel killed anything, OOM killer logs in `journalctl --grep "killed process"`.
5. **vdirsyncer sync correctness.** Add an event from iPhone → wait 5 min → appears on wall. Edit on wall → wait 5 min → appears on iPhone. Same as v1, but verify the new stack hasn't broken anything.
6. **Network drop recovery.** Unplug Wi-Fi router for 5 min, plug back in. Wall should keep showing last data, then resume syncing without intervention.
7. **OOM recovery.** Force OOM by starting a memory-hog process (`stress-ng --vm 1 --vm-bytes 200M`), confirm watchdog catches and restarts cleanly.

---

## Open questions & risks

These are decisions we should discuss before or during implementation:

1. **Wayland touchscreen support.** labwc + wlroots have full multi-touch support, but specific Pi-compatible USB touch panels vary. We'll need to verify the user's actual panel model works. If not: fallback is X11 + LightDM (AnotterKiosk's path) — same v2 plan otherwise. Roughly 90% confidence this is fine; 10% chance we discover a driver gap.
2. **Chromium GPU memory accounting.** With native GL, Chromium will *use* GPU memory (allocated from the 64MB `gpu_mem` reserve). On a busy month grid with many event chips, could exceed 64MB. Mitigation: set `gpu_mem=128` if needed; comes from the 416MB usable budget. Worth measuring before declaring victory.
3. **The on-screen keyboard.** v1 has a custom in-page on-screen keyboard for the Add Event modal. Frontend stays unchanged in v2, so the keyboard carries forward unchanged. Expected to work fine on Wayland — touch events are touch events at the browser level.
4. **Watchdog false positives during sleep mode.** v1's sleep overlay (00:00-06:00) blanks the screen but the page continues running JS, so heartbeats keep firing. Watchdog should not trigger during sleep. Verified by reading v1 sleep code, but worth confirming after implementation.
5. **First-boot UX without Wi-Fi pre-config.** If the user runs setup.sh without internet, vdirsyncer fails and the wall shows an empty calendar. Same UX as v1 — acceptable. setup.sh prompts for credentials interactively.
6. **dotfiles for the `pi` user.** v1's `.bash_profile` is gone (no startx). Need to make sure we don't accidentally leave it behind on existing Pi installs that get re-provisioned. Setup script should clean up any v1 leftovers explicitly.

---

## Rollback plan

If v2 doesn't work after 24-hour soak testing:

1. **Quick revert (5 min):** Reflash the Pi from a v1 SD card image (assuming we image the v1 install before starting). Or `git checkout pi-zero-2w` and re-run v1 setup.sh.
2. **Slow revert (1 hr):** Manually undo each v2 change — restore X11, install openbox, recreate `.bash_profile` startx, re-add the swap file, etc. (NetworkManager stayed in v2 so no networking changes to revert.) Not recommended; reflash is faster.
3. **Hardware escape hatch:** Pi 4 (2GB) is ~$45 and runs the v1 stack without modification. If both v1 and v2 fail on the Pi Zero 2 W, this is the honest answer.

We should image the v1 SD card before flashing v2 — `dd if=/dev/mmcblk0 of=v1-backup.img bs=4M` on another machine. ~2GB image, quick to write back.

---

## Out of scope for v2

Explicitly NOT included in this rebuild (could be v3):

- **Read-only root filesystem with tmpfs overlays** (AnotterKiosk pattern). Genuinely good for SD-card longevity, but ~5-10x engineering investment. Defer until we ship multiple Pis.
- **Custom OS image build with CI** (AnotterKiosk pattern). Same reasoning.
- **Multi-Pi sync, push notifications, week/day view, Android support, user authentication** — all out of scope per main `CLAUDE.md`.
- **Migrating to Pi 5 + main branch.** That's `main`'s job. v2 is the Pi Zero 2 W variant only.

---

## Open for review

The implementation order I'd suggest (after you sign off on this doc):

1. Cherry-pick the unchanged app code + sample data + .gitignore from `pi-zero-2w` → commit as "v2: bring forward unchanged app layer"
2. Write `scripts/setup.sh` v2 + new systemd units + labwc/greetd configs → commit as "v2: new display stack and supervision"
3. Add `/api/heartbeat` endpoint to `server.js` + 30s ping in `index.html` → commit as "v2: watchdog heartbeat"
4. Update `CLAUDE.md` + `README.md` with v2 stack → commit as "v2: docs"
5. Rewrite `docs/TROUBLESHOOTING.md` for new stack → commit as "v2: troubleshooting rewrite"
6. Image v1 SD card backup
7. Reflash Pi with v2 setup → 24-hour soak

Estimated end-to-end: 4-6 hours of code + 24 hours of testing.
