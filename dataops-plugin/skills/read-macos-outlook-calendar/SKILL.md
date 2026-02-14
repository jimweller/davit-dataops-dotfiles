---
description: "Search and read Outlook calendar events via AppleScript (macOS only). Requires Outlook to be running. Returns max ~1000 token summary."
allowed-tools: ["Bash"]
model: sonnet
context: fork
status-check: scripts/status.sh
---


# Read macOS Outlook Calendar

You help users search and read calendar events from Microsoft Outlook on macOS using AppleScript.

## Requirements

- **macOS only** - Uses AppleScript
- **Legacy Outlook required** - New Outlook does NOT support AppleScript
  - Switch to Legacy Outlook: Outlook menu > Legacy Outlook
  - Script will detect and error if New Outlook is active

## CRITICAL: Smart Calendar Selection

**DO NOT search all calendars blindly.** Some calendars have 9000+ events.

### Step 1: Always List Calendars First

```bash
~/.dataops-assistant/bin/outlook-calendar.sh calendars
```

This returns calendar names, IDs, and event counts. Use this to make smart decisions.

### Step 2: Pick Calendars Based on Query Type

| Query Type | Calendars to Search |
|------------|---------------------|
| "my meetings" / "my calendar" | `Calendar` (primary calendar) |
| "meetings with [person]" | Their shared calendar (by name) OR primary `Calendar` |
| "1-on-1s" / "one-on-ones" | `1-1s` if exists, else `Calendar` |
| "team PTO" / "vacations" | PTO/vacation calendars if exist |
| "holidays" | `United States holidays` or similar |
| "conference rooms" | Room calendars (often named "Conf Room...") |

### Step 3: Use Calendar IDs for Ambiguous Names

Multiple accounts may have calendars with the same name (e.g., two "Calendar" entries).

When `calendars` shows duplicates, use the **calendar ID** instead of the name:
```bash
# Use ID to target specific calendar
~/.dataops-assistant/bin/outlook-calendar.sh search --calendar 156 --after "2025-01-01" --limit 20
```

Pick the calendar with more events (likely the active account).

## Workflow

1. **List calendars** - Always start here to understand available calendars
2. **Analyze query** - What events is the user looking for?
3. **Select calendars** - Pick 1-2 relevant calendars based on query type
4. **Search with filters** - Use date, subject, location, organizer filters
5. **Read details** - Get full content of high-relevance events
6. **Summarize** - Present findings focused on the user's context

## Commands

```bash
# ALWAYS START HERE - List all calendars
~/.dataops-assistant/bin/outlook-calendar.sh calendars

# Search specific calendar(s)
~/.dataops-assistant/bin/outlook-calendar.sh search \
  --calendar "Calendar" \
  --subject "standup" \
  --location "room" \
  --organizer "email@example.com" \
  --after "2025-01-01" \
  --before "2025-01-31" \
  --limit 20

# Search by calendar ID (use when names are ambiguous)
~/.dataops-assistant/bin/outlook-calendar.sh search \
  --calendar 156 \
  --after "2025-01-01" \
  --limit 10

# Search multiple calendars (comma-separated)
~/.dataops-assistant/bin/outlook-calendar.sh search \
  --calendar "Calendar,1-1s" \
  --after "2025-01-01"

# Get single event by ID
~/.dataops-assistant/bin/outlook-calendar.sh get <event_id>

# Quick shortcuts (use primary Calendar)
~/.dataops-assistant/bin/outlook-calendar.sh today
~/.dataops-assistant/bin/outlook-calendar.sh week
```

## Search Options

| Option | Description | Example |
|--------|-------------|---------|
| `--calendar` | Calendar name(s) or ID. **Required - always specify!** | `--calendar "Calendar"` or `--calendar 156` |
| `--subject` | Subject contains term | `--subject "standup"` |
| `--location` | Location contains term | `--location "Room A"` |
| `--organizer` | Organizer email contains | `--organizer "boss@company.com"` |
| `--after` | Events after date | `--after "2025-01-01"` |
| `--before` | Events before date | `--before "2025-01-31"` |
| `--include-all` | Include ALL events (skip past-event status filter) | `--include-all` |
| `--limit` | Max results (default: 50) | `--limit 10` |
| `--offset` | Skip first N results | `--offset 20` |

**Multiple calendars**: Use comma-separated names: `--calendar "Calendar,1-1s"`

Omit unused options (don't include empty `--subject ""`).

### When to use `--include-all`

By default, past events with status "not responded" or "none" are filtered out as noise. However, **organizers of meetings always show status "none"** — so the default filter removes their own events.

Use `--include-all` when:
- Querying **all events in a date range** (e.g., meeting density, OOO days, person-activity research)
- The user is likely the **organizer** of many meetings (Directors, managers, leads)
- You need a **complete picture** of calendar activity

```bash
# All events in the last 30 days (no status filter)
~/.dataops-assistant/bin/outlook-calendar.sh search \
  --calendar "Calendar" \
  --after "2025-01-12" \
  --before "2025-02-11" \
  --include-all \
  --limit 200
```

## Search Response

```json
{
  "calendars_searched": 2,
  "total_matches": 47,
  "returned": 10,
  "offset": 0,
  "results": [
    {
      "id": 12345,
      "subject": "Team Standup",
      "start_time": "2025-01-28T09:00",
      "end_time": "2025-01-28T09:30",
      "location": "Room A",
      "organizer": "manager@company.com",
      "calendar": "Calendar",
      "calendar_id": 156,
      "is_all_day": false,
      "is_recurring": true,
      "status": "accepted"
    }
  ]
}
```

**Status values**: `accepted`, `tentatively accepted`, `declined`, `not responded`, `none`

**Note**: Past events with status `not responded` or `none` are automatically filtered out.

## Get Response

```json
{
  "id": 12345,
  "subject": "Team Standup",
  "start_time": "2025-01-28T09:00",
  "end_time": "2025-01-28T09:30",
  "location": "Room A",
  "organizer": "manager@company.com",
  "is_all_day": false,
  "is_recurring": true,
  "is_private": false,
  "calendar": "Calendar",
  "calendar_id": 156,
  "content": "Meeting notes and agenda...",
  "attendees": [
    {"name": "User Name", "email": "user@company.com"}
  ]
}
```

## Output Format

```
SEARCH STRATEGY:
- Query: [what user asked for]
- Calendars selected: [calendar names and why]
- Filters applied: [date range, subject, organizer]

RESULTS: [N] events found in [calendars]

EVENT: [ID] - [Subject]
TIME: [Start Time] - [End Time]
LOCATION: [Location]
ORGANIZER: [Organizer Name] <[email]>
CALENDAR: [Calendar name] (ID: [calendar_id])

RELEVANT FINDINGS:
- [Finding relevant to research context]

KEY DETAILS:
- [Important details from event body]
- [Attendee info if relevant]

RELEVANCE: [high|medium|low] - [explanation]
```

## Rules

- **ALWAYS list calendars first** - Don't guess at calendar names
- **Pick specific calendars** - Don't search everything
- **Past unaccepted events are filtered by default** - Events in the past with status "not responded" or "none" are excluded unless `--include-all` is passed. Use `--include-all` for date-range queries where you need all events (organizers always show "none")
- MAX ~1000 tokens output
- Focus on research context - extract what's RELEVANT
- If events have minimal relevance, say so briefly
- Include RELEVANCE rating

## Example Session

User asks: "What meetings do I have this week with my manager?"

1. **List calendars:**
   ```bash
   ~/.dataops-assistant/bin/outlook-calendar.sh calendars
   ```
   -> See "Calendar" (ID: 156, 4610 events), "1-1s" (ID: 132, 11 events)

2. **Analyze:** User wants their meetings -> primary Calendar. Also check 1-1s for manager meetings.

3. **Get date range:**
   - Today: 2025-02-03
   - End of week: 2025-02-09

4. **Search:**
   ```bash
   ~/.dataops-assistant/bin/outlook-calendar.sh search \
     --calendar "Calendar,1-1s" \
     --after "2025-02-03" \
     --before "2025-02-09" \
     --limit 30
   ```

5. **Filter results** for meetings with manager (by organizer or attendee).

6. **Summarize** the relevant meetings.
