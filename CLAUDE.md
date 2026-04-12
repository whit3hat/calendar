# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a physical digital wall calendar with touchscreen capabilities designed to run on a Raspberry Pi-class single-board computer. The calendar syncs bidirectionally with the user's phone calendar (Google Calendar or iCloud) and displays a touch-navigable calendar UI.

## Goals

- Physical wall-mounted touchscreen calendar (10"+ display)
- Bidirectional calendar sync with phone (receive invites, push new events)
- Seamless touch UX — feels like a dedicated appliance, not a computer
- High quality materials and reliable hardware

## Planned Architecture

### Hardware
- **SBC**: Raspberry Pi 4 (4GB) or Pi 5
- **Display**: 10.1"–13.3" HDMI touchscreen (Waveshare or similar)
- **Storage**: 32GB+ high-endurance microSD or USB SSD
- **Power**: Official RPi USB-C PSU, optional UPS HAT for power-loss protection
- **Enclosure**: Wall-mount case or picture frame mount

### Software Stack (Decided)
- **OS**: Raspberry Pi OS Lite + pi-kiosk (Chromium fullscreen on boot)
- **Display UI**: FullCalendar.js (custom web app — HTML/JS frontend)
- **Backend API**: Node.js + Express (or Python/Flask) — serves events to UI, accepts new event writes
- **ICS parsing**: ical.js (JavaScript)
- **Calendar Sync**: vdirsyncer → CalDAV/Google API → local `.ics` files on Pi
- **Kiosk**: pi-kiosk (geerlingguy) — auto-start, crash recovery, screen blanking disabled

### Cloud Sync Backend — iCloud CalDAV (decided)
All family members use iPhone + Apple Calendar. vdirsyncer connects directly to iCloud CalDAV.
No new apps required on any phone. A single app-specific password (from appleid.apple.com) is
the only one-time setup step on the Pi side.

### Key Architecture Decisions
- vdirsyncer runs as a cron job every 5 minutes — syncs cloud ↔ local `.ics` files
- Pi-created events write to local `.ics` → vdirsyncer pushes to cloud within 5 min
- Phone uses native calendar apps (Google Calendar / Apple Calendar) for away-from-home access
- No Raspberry Pi port forwarding needed — Pi only ever calls out to cloud, never accepts inbound

See `software/architecture.md` for full system diagram and data flow.

## Build Phases

1. Hardware assembly — Pi + screen in wall-mount, verify touch input works
2. Calendar sync — vdirsyncer pulling calendar data to local `.ics` files
3. Display UI — MagicMirror² or custom web app rendering the calendar
4. Two-way sync — write-back so Pi-created events push to phone
5. Polish — kiosk mode auto-start, always-on display, fonts/colors

## Key Files (to be created)

- `hardware/options.md` — Hardware research with 3 options per component
- `software/` — Application code (display UI, sync scripts)
- `config/` — vdirsyncer, MagicMirror, or app configuration
- `scripts/setup.sh` — Pi setup/provisioning script
