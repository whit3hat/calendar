const express = require('express');
const path = require('path');
const fs = require('fs');
const os = require('os');
const crypto = require('crypto');
const ical = require('node-ical');

const app = express();
const PORT = process.env.PORT || 8080;

// Calendar data directory.
// On Pi:      ~/.local/share/calendar/   (populated by vdirsyncer)
// Local dev:  CALENDAR_DIR=./data npm start
const CALENDAR_DIR = process.env.CALENDAR_DIR
  ? path.resolve(process.env.CALENDAR_DIR)
  : path.join(os.homedir(), '.local', 'share', 'calendar');

// Weather config — lat/lon default to Liberty, MO; units default to fahrenheit.
// Override with WEATHER_LAT, WEATHER_LON, WEATHER_UNITS env vars.
const WEATHER_LAT   = process.env.WEATHER_LAT   ? parseFloat(process.env.WEATHER_LAT)   : 39.3392;
const WEATHER_LON   = process.env.WEATHER_LON   ? parseFloat(process.env.WEATHER_LON)   : -94.2261;
const WEATHER_UNITS = (process.env.WEATHER_UNITS || 'fahrenheit').toLowerCase();

const weatherCache = { data: null, fetchedAt: 0 };
const WEATHER_CACHE_MS = 15 * 60 * 1000; // 15 minutes

// Colors assigned to calendars by folder name (case-insensitive).
const CALENDAR_COLORS = {
  family:   '#3b82f6',  // blue
  kids:     '#22c55e',  // green
  personal: '#f59e0b',  // amber
  work:     '#ef4444',  // red
};
const DEFAULT_COLOR = '#8b5cf6'; // purple — used for any unlisted calendar

function calendarColor(name) {
  return CALENDAR_COLORS[name.toLowerCase()] ?? DEFAULT_COLOR;
}

// Format a Date for FullCalendar:
//   all-day events → "YYYY-MM-DD"
//   timed events   → ISO 8601 string
function formatDate(date, allDay) {
  if (!date) return null;
  const pad = n => String(n).padStart(2, '0');
  if (allDay) {
    return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}`;
  }
  // Return local time without a Z suffix so the client interprets it as local
  // (consistent with the floating local time used in the generated ICS files)
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
         `T${pad(date.getHours())}:${pad(date.getMinutes())}:${pad(date.getSeconds())}`;
}

// Read all .ics files from CALENDAR_DIR and return FullCalendar-compatible
// event objects. Each subdirectory is treated as a separate calendar.
function loadEvents() {
  const events = [];

  if (!fs.existsSync(CALENDAR_DIR)) {
    console.warn(`Calendar directory not found: ${CALENDAR_DIR}`);
    return events;
  }

  const entries = fs.readdirSync(CALENDAR_DIR, { withFileTypes: true });

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const calendarName = entry.name;
    const calendarPath = path.join(CALENDAR_DIR, calendarName);
    const color = calendarColor(calendarName);
    const files = fs.readdirSync(calendarPath).filter(f => f.endsWith('.ics'));

    for (const file of files) {
      const filePath = path.join(calendarPath, file);
      try {
        const parsed = ical.sync.parseFile(filePath);

        for (const component of Object.values(parsed)) {
          if (component.type !== 'VEVENT') continue;

          const allDay = !!(component.start && component.start.dateOnly);

          events.push({
            id: component.uid || file,
            title: component.summary || '(No title)',
            start: formatDate(component.start, allDay),
            end: formatDate(component.end, allDay),
            allDay,
            color,
            extendedProps: {
              calendarName,
              notes:       component.description || '',
              isRecurring: !!component.rrule,
            },
          });
        }
      } catch (err) {
        console.error(`Failed to parse ${filePath}:`, err.message);
      }
    }
  }

  return events;
}

// Scan all calendar subdirectories for a VEVENT whose UID matches.
// Returns { filePath, calendarName, component } or null.
function findEventFile(uid) {
  if (!fs.existsSync(CALENDAR_DIR)) return null;

  let entries;
  try { entries = fs.readdirSync(CALENDAR_DIR, { withFileTypes: true }); }
  catch { return null; }

  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const calendarPath = path.join(CALENDAR_DIR, entry.name);

    let files;
    try { files = fs.readdirSync(calendarPath).filter(f => f.endsWith('.ics')); }
    catch { continue; }

    for (const file of files) {
      const filePath = path.join(calendarPath, file);
      try {
        const parsed = ical.sync.parseFile(filePath);
        for (const component of Object.values(parsed)) {
          if (component.type === 'VEVENT' && component.uid === uid) {
            return { filePath, calendarName: entry.name, component };
          }
        }
      } catch { /* skip unparseable files */ }
    }
  }
  return null;
}

// Unfold RFC 5545 folded lines and return the VEVENT properties that
// this app does NOT manage — e.g. VALARM blocks, X-APPLE-* fields,
// ORGANIZER, attendees — so they survive an edit without being lost.
function extractPreservedVEventLines(rawContent) {
  const MANAGED = new Set([
    'UID', 'DTSTAMP', 'DTSTART', 'DTEND', 'SUMMARY', 'DESCRIPTION', 'SEQUENCE',
  ]);

  // Unfold: continuation lines start with SP or HT (RFC 5545 §3.1)
  const physLines = rawContent.replace(/\r\n/g, '\n').split('\n');
  const logical   = [];
  for (const line of physLines) {
    if ((line.startsWith(' ') || line.startsWith('\t')) && logical.length > 0) {
      logical[logical.length - 1] += line.slice(1);
    } else {
      logical.push(line);
    }
  }

  const preserved = [];
  let inVEvent = false;
  let depth    = 0; // nesting depth for sub-components like VALARM

  for (const line of logical) {
    if (!inVEvent) {
      if (line === 'BEGIN:VEVENT') inVEvent = true;
      continue;
    }

    if (line === 'END:VEVENT' && depth === 0) { inVEvent = false; continue; }

    // Inside a nested sub-component (VALARM etc.) — preserve everything
    if (depth > 0) {
      preserved.push(line);
      if (line.startsWith('END:')) depth--;
      continue;
    }

    // Start of a nested sub-component
    if (line.startsWith('BEGIN:')) {
      depth++;
      preserved.push(line);
      continue;
    }

    // Top-level VEVENT property — preserve if not managed
    const propName = line.split(/[:;]/)[0].toUpperCase();
    if (!MANAGED.has(propName)) preserved.push(line);
  }

  return preserved;
}

// ── ICS generation ─────────────────────────────────────────────

// Escape special characters in ICS text values per RFC 5545 §3.3.11
function escapeICS(str) {
  return String(str)
    .replace(/\\/g, '\\\\')
    .replace(/;/g, '\\;')
    .replace(/,/g, '\\,')
    .replace(/\r\n|\r|\n/g, '\\n'); // normalize all newline forms to the ICS \n escape
}

// Fold lines longer than 75 octets per RFC 5545 §3.1.
// Splits at a UTF-8-safe boundary so multi-byte chars are never split.
function foldLine(line) {
  const bytes = Buffer.from(line, 'utf8');
  if (bytes.length <= 75) return line;

  const parts = [];
  let offset = 0;
  let first = true;

  while (offset < bytes.length) {
    const limit = first ? 75 : 74; // continuation lines are prefixed with 1 space byte
    let end = Math.min(offset + limit, bytes.length);

    // Walk back if we'd split a multi-byte UTF-8 sequence
    // (continuation bytes are 0x80–0xBF)
    while (end < bytes.length && (bytes[end] & 0xC0) === 0x80) {
      end--;
    }

    parts.push(bytes.slice(offset, end).toString('utf8'));
    offset = end;
    first = false;
  }

  return parts.join('\r\n ');
}

// Returns the date string for the day after dateStr (YYYY-MM-DD → YYYY-MM-DD).
// Used for all-day DTEND which is exclusive (next day) per RFC 5545.
function nextDay(dateStr) {
  const d = new Date(dateStr + 'T00:00:00'); // parse as local midnight
  d.setDate(d.getDate() + 1);
  return [
    d.getFullYear(),
    String(d.getMonth() + 1).padStart(2, '0'),
    String(d.getDate()).padStart(2, '0'),
  ].join('-');
}

// Build a minimal but RFC 5545-compliant VCALENDAR string for a single event.
function generateICS({ uid, title, notes, allDay, date, startTime, endTime }) {
  // DTSTAMP must be UTC
  const dtstamp = new Date()
    .toISOString()
    .replace(/[-:]/g, '')
    .replace(/\.\d+Z$/, 'Z');

  let dtstart, dtend;

  if (allDay) {
    const dateCompact = date.replace(/-/g, '');           // YYYYMMDD
    const endCompact  = nextDay(date).replace(/-/g, '');  // YYYYMMDD (next day, exclusive)
    dtstart = `DTSTART;VALUE=DATE:${dateCompact}`;
    dtend   = `DTEND;VALUE=DATE:${endCompact}`;
  } else {
    // Floating (local) time — no timezone suffix, matches how iCloud stores local events
    const startCompact = date.replace(/-/g, '') + 'T' + startTime.replace(':', '') + '00';
    const endCompact   = date.replace(/-/g, '') + 'T' + endTime.replace(':', '') + '00';
    dtstart = `DTSTART:${startCompact}`;
    dtend   = `DTEND:${endCompact}`;
  }

  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Family Calendar//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${dtstamp}`,
    dtstart,
    dtend,
    foldLine(`SUMMARY:${escapeICS(title)}`),
  ];

  if (notes && notes.trim()) {
    lines.push(foldLine(`DESCRIPTION:${escapeICS(notes.trim())}`));
  }

  lines.push('END:VEVENT', 'END:VCALENDAR');

  // RFC 5545 requires CRLF line endings
  return lines.join('\r\n') + '\r\n';
}

// ── Middleware ──────────────────────────────────────────────────
app.use(express.json());
app.use(express.static(path.join(__dirname, '../public')));

// ── Routes ─────────────────────────────────────────────────────

// GET /api/events
// Returns all calendar events as FullCalendar-compatible JSON.
app.get('/api/events', (req, res) => {
  try {
    res.json(loadEvents());
  } catch (err) {
    console.error('Error loading events:', err);
    res.status(500).json({ error: 'Failed to load events' });
  }
});

// GET /api/calendars
// Returns the list of available calendars (subdirectory names + colors).
app.get('/api/calendars', (req, res) => {
  if (!fs.existsSync(CALENDAR_DIR)) return res.json([]);

  try {
    const calendars = fs.readdirSync(CALENDAR_DIR, { withFileTypes: true })
      .filter(e => e.isDirectory())
      .map(e => ({ name: e.name, color: calendarColor(e.name) }));
    res.json(calendars);
  } catch (err) {
    console.error('Error reading calendar list:', err);
    res.status(500).json({ error: 'Failed to read calendars' });
  }
});

// GET /api/weather
// Proxies Open-Meteo with a 15-minute server-side cache so the Pi never hammers
// the external API and the client never leaks the lat/lon to the browser.
app.get('/api/weather', async (req, res) => {
  if (weatherCache.data && Date.now() - weatherCache.fetchedAt < WEATHER_CACHE_MS) {
    return res.json(weatherCache.data);
  }

  try {
    const unit = WEATHER_UNITS === 'celsius' ? 'celsius' : 'fahrenheit';
    const url = `https://api.open-meteo.com/v1/forecast` +
      `?latitude=${WEATHER_LAT}&longitude=${WEATHER_LON}` +
      `&current=temperature_2m,weathercode` +
      `&daily=weathercode,temperature_2m_max,temperature_2m_min` +
      `&temperature_unit=${unit}` +
      `&timezone=auto` +
      `&forecast_days=5`;

    const response = await fetch(url);
    if (!response.ok) throw new Error(`Open-Meteo HTTP ${response.status}`);
    const json = await response.json();

    const daily = json.daily;
    const result = {
      enabled: true,
      current: {
        temp: Math.round(json.current.temperature_2m),
        code: json.current.weathercode,
      },
      today: {
        high: Math.round(daily.temperature_2m_max[0]),
        low:  Math.round(daily.temperature_2m_min[0]),
      },
      // index 0 = today; slice 1–4 = next 4 days
      forecast: daily.time.slice(1, 5).map((date, i) => ({
        date,
        code: daily.weathercode[i + 1],
        high: Math.round(daily.temperature_2m_max[i + 1]),
      })),
      units: unit === 'celsius' ? 'C' : 'F',
    };

    weatherCache.data      = result;
    weatherCache.fetchedAt = Date.now();
    res.json(result);
  } catch (err) {
    console.error('Weather fetch failed:', err.message);
    if (weatherCache.data) return res.json(weatherCache.data); // serve stale on error
    res.status(503).json({ error: 'Weather unavailable' });
  }
});

// POST /api/events
// Creates a new event by writing a .ics file to the chosen calendar directory.
// vdirsyncer picks up the file on its next run (within 5 minutes) and pushes to iCloud.
app.post('/api/events', (req, res) => {
  const { title, allDay, date, startTime, endTime, calendarName, notes } = req.body;

  // ── Input validation ──────────────────────────────────────────
  if (!title || !title.trim()) {
    return res.status(400).json({ error: 'Title is required' });
  }
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date)) {
    return res.status(400).json({ error: 'A valid date (YYYY-MM-DD) is required' });
  }
  if (!calendarName) {
    return res.status(400).json({ error: 'Calendar is required' });
  }

  if (!allDay) {
    if (!startTime || !/^\d{2}:\d{2}$/.test(startTime)) {
      return res.status(400).json({ error: 'A valid start time (HH:MM) is required' });
    }
    if (!endTime || !/^\d{2}:\d{2}$/.test(endTime)) {
      return res.status(400).json({ error: 'A valid end time (HH:MM) is required' });
    }
    const [sh, sm] = startTime.split(':').map(Number);
    const [eh, em] = endTime.split(':').map(Number);
    if (sh * 60 + sm >= eh * 60 + em) {
      return res.status(400).json({ error: 'End time must be after start time' });
    }
  }

  // Prevent directory traversal — calendarName must be an existing subdirectory
  const calendarPath = path.join(CALENDAR_DIR, path.basename(calendarName));
  if (!fs.existsSync(calendarPath) || !fs.statSync(calendarPath).isDirectory()) {
    return res.status(400).json({ error: `Calendar "${calendarName}" not found` });
  }

  // ── Generate UID and ICS content ──────────────────────────────
  const uuid = crypto.randomUUID();
  const uid  = `${uuid}@family-calendar`;

  const icsContent = generateICS({
    uid,
    title:     title.trim(),
    notes:     notes || '',
    allDay:    !!allDay,
    date,
    startTime,
    endTime,
  });

  // Filename uses the UUID (without domain) — matches vdirsyncer convention
  const filePath = path.join(calendarPath, `${uuid}.ics`);

  try {
    fs.writeFileSync(filePath, icsContent, 'utf8');
  } catch (err) {
    console.error('Failed to write ICS file:', err);
    return res.status(500).json({ error: 'Failed to save event' });
  }

  // ── Build and return the new event in FullCalendar format ─────
  const color = calendarColor(calendarName);
  const endDate = allDay ? nextDay(date) : null;

  res.status(201).json({
    id:    uid,
    title: title.trim(),
    start: allDay ? date : `${date}T${startTime}:00`,
    end:   allDay ? endDate : `${date}T${endTime}:00`,
    allDay: !!allDay,
    color,
    extendedProps: {
      calendarName,
      notes: (notes || '').trim(),
    },
  });
});

// PUT /api/events/:uid
// Updates an existing event in place (or moves it to a new calendar).
// Preserves any ICS properties the app does not manage (VALARM, X-APPLE-*, etc.).
// Increments SEQUENCE so iCloud accepts the update as a newer version.
app.put('/api/events/:uid', (req, res) => {
  const uid = req.params.uid;
  const { title, allDay, date, startTime, endTime, calendarName, notes } = req.body;

  // ── Input validation ──────────────────────────────────────────
  if (!title || !title.trim())
    return res.status(400).json({ error: 'Title is required' });
  if (!date || !/^\d{4}-\d{2}-\d{2}$/.test(date))
    return res.status(400).json({ error: 'A valid date (YYYY-MM-DD) is required' });
  if (!calendarName)
    return res.status(400).json({ error: 'Calendar is required' });

  if (!allDay) {
    if (!startTime || !/^\d{2}:\d{2}$/.test(startTime))
      return res.status(400).json({ error: 'A valid start time (HH:MM) is required' });
    if (!endTime || !/^\d{2}:\d{2}$/.test(endTime))
      return res.status(400).json({ error: 'A valid end time (HH:MM) is required' });
    const [sh, sm] = startTime.split(':').map(Number);
    const [eh, em] = endTime.split(':').map(Number);
    if (sh * 60 + sm >= eh * 60 + em)
      return res.status(400).json({ error: 'End time must be after start time' });
  }

  // ── Locate the existing event ─────────────────────────────────
  const found = findEventFile(uid);
  if (!found) return res.status(404).json({ error: 'Event not found' });
  if (found.component.rrule) {
    return res.status(422).json({
      error: 'Recurring events cannot be edited here — use Apple Calendar',
    });
  }

  // ── Validate target calendar (directory traversal guard) ──────
  const targetCalPath = path.join(CALENDAR_DIR, path.basename(calendarName));
  if (!fs.existsSync(targetCalPath) || !fs.statSync(targetCalPath).isDirectory()) {
    return res.status(400).json({ error: `Calendar "${calendarName}" not found` });
  }

  // ── Build updated ICS ─────────────────────────────────────────
  const rawContent  = fs.readFileSync(found.filePath, 'utf8');
  const preserved   = extractPreservedVEventLines(rawContent);
  const sequence    = (parseInt(found.component.sequence || '0', 10) || 0) + 1;
  const dtstamp     = new Date().toISOString().replace(/[-:]/g, '').replace(/\.\d+Z$/, 'Z');

  let dtstart, dtend;
  if (allDay) {
    dtstart = `DTSTART;VALUE=DATE:${date.replace(/-/g, '')}`;
    dtend   = `DTEND;VALUE=DATE:${nextDay(date).replace(/-/g, '')}`;
  } else {
    dtstart = `DTSTART:${date.replace(/-/g, '')}T${startTime.replace(':', '')}00`;
    dtend   = `DTEND:${date.replace(/-/g, '')}T${endTime.replace(':', '')}00`;
  }

  const lines = [
    'BEGIN:VCALENDAR',
    'VERSION:2.0',
    'PRODID:-//Family Calendar//EN',
    'CALSCALE:GREGORIAN',
    'BEGIN:VEVENT',
    `UID:${uid}`,
    `DTSTAMP:${dtstamp}`,
    `SEQUENCE:${sequence}`,
    dtstart,
    dtend,
    foldLine(`SUMMARY:${escapeICS(title.trim())}`),
  ];
  if (notes && notes.trim()) {
    lines.push(foldLine(`DESCRIPTION:${escapeICS(notes.trim())}`));
  }
  // Re-fold preserved lines (they were unfolded during extraction)
  for (const line of preserved) {
    lines.push(foldLine(line));
  }
  lines.push('END:VEVENT', 'END:VCALENDAR');
  const icsContent = lines.join('\r\n') + '\r\n';

  // ── Write (move to new calendar directory if needed) ──────────
  // Keep the same filename; only the directory changes on a calendar move.
  const newFilePath = path.join(targetCalPath, path.basename(found.filePath));
  try {
    if (found.filePath !== newFilePath) {
      // Write first so we never lose the event if unlink fails
      fs.writeFileSync(newFilePath, icsContent, 'utf8');
      fs.unlinkSync(found.filePath);
    } else {
      fs.writeFileSync(found.filePath, icsContent, 'utf8');
    }
  } catch (err) {
    console.error('Failed to update event:', err);
    return res.status(500).json({ error: 'Failed to update event' });
  }

  // ── Return updated event in FullCalendar format ───────────────
  const color   = calendarColor(calendarName);
  const endDate = allDay ? nextDay(date) : null;
  res.json({
    id:     uid,
    title:  title.trim(),
    start:  allDay ? date : `${date}T${startTime}:00`,
    end:    allDay ? endDate : `${date}T${endTime}:00`,
    allDay: !!allDay,
    color,
    extendedProps: {
      calendarName,
      notes:       (notes || '').trim(),
      isRecurring: false,
    },
  });
});

// DELETE /api/events/:uid
// Deletes the .ics file for a non-recurring event.
// vdirsyncer detects the deletion and removes it from iCloud on its next run.
app.delete('/api/events/:uid', (req, res) => {
  const uid = req.params.uid;

  const found = findEventFile(uid);
  if (!found) return res.status(404).json({ error: 'Event not found' });
  if (found.component.rrule) {
    return res.status(422).json({
      error: 'Recurring events cannot be deleted here — use Apple Calendar',
    });
  }

  try {
    fs.unlinkSync(found.filePath);
  } catch (err) {
    console.error('Failed to delete event:', err);
    return res.status(500).json({ error: 'Failed to delete event' });
  }

  res.status(204).send();
});

app.listen(PORT, () => {
  console.log(`Calendar server running at http://localhost:${PORT}`);
  console.log(`Reading calendars from: ${CALENDAR_DIR}`);
});
