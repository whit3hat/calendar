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
              notes: component.description || '',
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

app.listen(PORT, () => {
  console.log(`Calendar server running at http://localhost:${PORT}`);
  console.log(`Reading calendars from: ${CALENDAR_DIR}`);
});
