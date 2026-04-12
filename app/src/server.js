const express = require('express');
const path = require('path');
const fs = require('fs');
const os = require('os');
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
// Folder names come from iCloud calendar names discovered by vdirsyncer.
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
  if (allDay) {
    const y = date.getFullYear();
    const m = String(date.getMonth() + 1).padStart(2, '0');
    const d = String(date.getDate()).padStart(2, '0');
    return `${y}-${m}-${d}`;
  }
  return date.toISOString();
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

// Serve static files (HTML, CSS, JS) from public/
app.use(express.static(path.join(__dirname, '../public')));

// GET /api/events
// Returns all calendar events as FullCalendar-compatible JSON.
app.get('/api/events', (req, res) => {
  try {
    const events = loadEvents();
    res.json(events);
  } catch (err) {
    console.error('Error loading events:', err);
    res.status(500).json({ error: 'Failed to load events' });
  }
});

app.listen(PORT, () => {
  console.log(`Calendar server running at http://localhost:${PORT}`);
  console.log(`Reading calendars from: ${CALENDAR_DIR}`);
});
