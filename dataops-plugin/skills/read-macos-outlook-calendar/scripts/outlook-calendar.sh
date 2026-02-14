#!/usr/bin/env bash
#
# outlook-calendar.sh - Outlook calendar access via AppleScript (macOS only)
#
# Usage:
#   outlook-calendar.sh calendars           List all calendars with IDs and counts
#   outlook-calendar.sh search [options]    Search calendar events
#   outlook-calendar.sh get <event_id>      Get single event by ID
#   outlook-calendar.sh today               Get today's events (all calendars)
#   outlook-calendar.sh week                Get this week's events (all calendars)
#
# Search options:
#   --calendar <name|id>  Search specific calendar by name or ID
#                         Without --calendar, searches common calendars: Calendar
#   --subject <term>      Filter by subject containing term
#   --location <term>     Filter by location containing term
#   --organizer <email>   Filter by organizer email address
#   --after <date>        Filter events after date (YYYY-MM-DD)
#   --before <date>       Filter events before date (YYYY-MM-DD)
#   --include-all         Include ALL events (skip past-event status filter)
#   --limit <n>           Maximum results (default: 50)
#   --offset <n>          Skip first n results (default: 0)
#
# Examples:
#   outlook-calendar.sh calendars
#   outlook-calendar.sh search --subject "standup" --after 2025-01-01 --limit 10
#   outlook-calendar.sh search --calendar "Calendar" --after 2025-01-01
#   outlook-calendar.sh search --calendar 156 --limit 5
#   outlook-calendar.sh get 12345
#   outlook-calendar.sh today
#   outlook-calendar.sh week
#
# Output:
#   All commands output JSON to stdout. Errors go to stderr.
#
# Requirements:
#   - macOS with Microsoft Outlook installed
#   - Outlook must be running
#   - Legacy Outlook recommended (New Outlook has limited AppleScript support)

set -euo pipefail

# Track if we've already output an error (to avoid double-output on trap)
ERROR_OUTPUT=false

# Trap to ensure JSON error output on any unexpected exit
trap_handler() {
    local exit_code=$?
    if [[ $exit_code -ne 0 ]] && [[ "$ERROR_OUTPUT" == "false" ]]; then
        echo "{\"error\": \"Script failed with exit code $exit_code\"}" >&2
    fi
}
trap trap_handler EXIT

# --- Helpers ---

die() {
    ERROR_OUTPUT=true
    echo "{\"error\": \"$1\"}" >&2
    exit 1
}

check_outlook() {
    if ! pgrep -x "Microsoft Outlook" > /dev/null 2>&1; then
        die "Microsoft Outlook is not running"
    fi

    # Check if running New Outlook (incompatible with AppleScript)
    local is_new_outlook
    is_new_outlook=$(defaults read com.microsoft.Outlook IsRunningNewOutlook 2>/dev/null || echo "")

    if [[ "$is_new_outlook" == "1" ]] || [[ "$is_new_outlook" == "true" ]] || [[ "$is_new_outlook" == "YES" ]]; then
        die "New Outlook detected. This script requires Legacy Outlook. Switch to Legacy Outlook via: Outlook menu > Legacy Outlook"
    fi
}

# Get today's date in YYYY-MM-DD format
get_today() {
    date "+%Y-%m-%d"
}

# Get date N days from now in YYYY-MM-DD format
get_date_offset() {
    local days="$1"
    date -v+"${days}d" "+%Y-%m-%d"
}

# --- Commands ---

cmd_calendars() {
    osascript <<'APPLESCRIPT'
tell application "Microsoft Outlook"
    set allCalendars to calendars
    set jsonParts to {}

    repeat with c in allCalendars
        set cid to id of c

        -- Handle potentially missing calendar name
        set cname to "unknown"
        try
            set tmpName to name of c
            if tmpName is not missing value then
                set cname to tmpName
            end if
        end try

        try
            set evtCount to count of calendar events of c
        on error
            set evtCount to 0
        end try

        -- Escape calendar name for JSON
        if cname is not "unknown" then
            set cleanName to my replaceText(cname, "\\", "\\\\")
            set cleanName to my replaceText(cleanName, "\"", "\\\"")
        else
            set cleanName to "unknown"
        end if

        set jsonObj to "{\"id\": " & cid & ", \"name\": \"" & cleanName & "\", \"count\": " & evtCount & "}"
        set end of jsonParts to jsonObj
    end repeat

    set AppleScript's text item delimiters to ", "
    set jsonArray to "[" & (jsonParts as text) & "]"
    return jsonArray
end tell

on replaceText(theText, searchStr, replaceStr)
    if theText is missing value then return ""
    set AppleScript's text item delimiters to searchStr
    set textItems to text items of theText
    set AppleScript's text item delimiters to replaceStr
    set theText to textItems as text
    set AppleScript's text item delimiters to ""
    return theText
end replaceText
APPLESCRIPT
}

cmd_search() {
    local calendar=""
    local subject=""
    local location=""
    local organizer=""
    local after_date=""
    local before_date=""
    local include_all="false"
    local limit=50
    local offset=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --calendar) calendar="$2"; shift 2 ;;
            --subject) subject="$2"; shift 2 ;;
            --location) location="$2"; shift 2 ;;
            --organizer) organizer="$2"; shift 2 ;;
            --after) after_date="$2"; shift 2 ;;
            --before) before_date="$2"; shift 2 ;;
            --include-all) include_all="true"; shift ;;
            --limit) limit="$2"; shift 2 ;;
            --offset) offset="$2"; shift 2 ;;
            *) die "Unknown option: $1. Usage: search [--calendar name|id] [--subject term] [--location term] [--organizer email] [--after YYYY-MM-DD] [--before YYYY-MM-DD] [--include-all] [--limit N]" ;;
        esac
    done

    # If no calendar specified, search common calendars
    if [[ -z "$calendar" ]]; then
        calendar="Calendar"
    fi

    osascript - "$calendar" "$subject" "$location" "$organizer" "$after_date" "$before_date" "$limit" "$offset" "$include_all" <<'APPLESCRIPT'
on run argv
    set calendarSpec to item 1 of argv
    set subjectFilter to item 2 of argv
    set locationFilter to item 3 of argv
    set organizerFilter to item 4 of argv
    set afterDateStr to item 5 of argv
    set beforeDateStr to item 6 of argv
    set maxResults to (item 7 of argv) as integer
    set skipCount to (item 8 of argv) as integer
    set includeAllEvents to (item 9 of argv)

    tell application "Microsoft Outlook"
        -- Parse dates if provided (YYYY-MM-DD format)
        set afterDate to missing value
        set beforeDate to missing value

        if afterDateStr is not "" then
            set afterDate to my parseISODate(afterDateStr)
        end if
        if beforeDateStr is not "" then
            set beforeDate to my parseISODate(beforeDateStr)
        end if

        -- Parse calendar specification - support mixed names and IDs
        set targetCalendarIds to {}
        set targetCalendarNames to {}

        set AppleScript's text item delimiters to ","
        set specParts to text items of calendarSpec
        set AppleScript's text item delimiters to ""

        repeat with part in specParts
            try
                set partInt to (part as integer)
                set end of targetCalendarIds to partInt
            on error
                set end of targetCalendarNames to (part as text)
            end try
        end repeat

        set allCalendars to calendars
        set jsonResults to {}
        set matchCount to 0
        set skipped to 0
        set calendarsSearched to {}

        repeat with c in allCalendars
            set cid to id of c

            -- Handle potentially missing calendar name
            set cname to "unknown"
            try
                set tmpName to name of c
                if tmpName is not missing value then
                    set cname to tmpName
                end if
            end try

            set shouldSearch to false

            -- Check if we should search this calendar (supports mixed IDs and names)
            repeat with tid in targetCalendarIds
                if cid is (tid as integer) then
                    set shouldSearch to true
                    exit repeat
                end if
            end repeat
            if not shouldSearch then
                repeat with targetName in targetCalendarNames
                    if cname is (targetName as text) then
                        set shouldSearch to true
                        exit repeat
                    end if
                end repeat
            end if

            if shouldSearch then
                set end of calendarsSearched to cname & " (" & cid & ")"

                try
                    set evtList to calendar events of c

                    set rightNow to current date

                    repeat with evt in evtList
                        set includeEvt to true

                        -- Get event properties
                        set evtSubject to subject of evt
                        set evtStart to start time of evt
                        set evtEnd to end time of evt

                        -- Get acceptance status (my status property)
                        set evtStatus to "none"
                        try
                            set tmpStatus to my status of evt
                            if tmpStatus is not missing value then
                                set evtStatus to tmpStatus as string
                            end if
                        end try

                        -- Filter out past unaccepted events (unless --include-all)
                        -- (past events where status is "not responded" or "none" are noise,
                        --  but organizers always show "none" so this filter misses their events)
                        if includeAllEvents is not "true" then
                            if evtStart < rightNow then
                                if evtStatus is "not responded" or evtStatus is "none" then
                                    set includeEvt to false
                                end if
                            end if
                        end if

                        -- Location (may be missing value)
                        set evtLocation to ""
                        try
                            set tmpLoc to location of evt
                            if tmpLoc is not missing value then set evtLocation to tmpLoc
                        end try

                        -- Organizer (may be missing value)
                        set evtOrganizer to ""
                        try
                            set tmpOrg to organizer of evt
                            if tmpOrg is not missing value then set evtOrganizer to tmpOrg
                        end try

                        -- Subject filter
                        if subjectFilter is not "" then
                            if evtSubject does not contain subjectFilter then
                                set includeEvt to false
                            end if
                        end if

                        -- Location filter
                        if includeEvt and locationFilter is not "" then
                            if evtLocation does not contain locationFilter then
                                set includeEvt to false
                            end if
                        end if

                        -- Organizer filter
                        if includeEvt and organizerFilter is not "" then
                            if evtOrganizer does not contain organizerFilter then
                                set includeEvt to false
                            end if
                        end if

                        -- Date filters (use start time)
                        if includeEvt and afterDate is not missing value then
                            if evtStart < afterDate then
                                set includeEvt to false
                            end if
                        end if

                        if includeEvt and beforeDate is not missing value then
                            if evtStart > beforeDate then
                                set includeEvt to false
                            end if
                        end if

                        if includeEvt then
                            set matchCount to matchCount + 1

                            -- Handle offset
                            if skipped < skipCount then
                                set skipped to skipped + 1
                            else if (count of jsonResults) < maxResults then
                                set evtId to id of evt
                                set isAllDay to all day flag of evt
                                set isRecurring to is recurring of evt

                                -- Format times
                                set startStr to my formatDateTime(evtStart)
                                set endStr to my formatDateTime(evtEnd)

                                -- Escape strings for JSON
                                set cleanSubject to my replaceText(evtSubject, "\\", "\\\\")
                                set cleanSubject to my replaceText(cleanSubject, "\"", "\\\"")
                                set cleanSubject to my replaceText(cleanSubject, return, " ")
                                set cleanSubject to my replaceText(cleanSubject, (ASCII character 10), " ")

                                set cleanLocation to my replaceText(evtLocation, "\"", "\\\"")
                                set cleanOrganizer to my replaceText(evtOrganizer, "\"", "\\\"")

                                set jsonObj to "{\"id\": " & evtId
                                set jsonObj to jsonObj & ", \"subject\": \"" & cleanSubject & "\""
                                set jsonObj to jsonObj & ", \"start_time\": \"" & startStr & "\""
                                set jsonObj to jsonObj & ", \"end_time\": \"" & endStr & "\""
                                set jsonObj to jsonObj & ", \"location\": \"" & cleanLocation & "\""
                                set jsonObj to jsonObj & ", \"organizer\": \"" & cleanOrganizer & "\""
                                set jsonObj to jsonObj & ", \"calendar\": \"" & cname & "\""
                                set jsonObj to jsonObj & ", \"calendar_id\": " & cid
                                set jsonObj to jsonObj & ", \"is_all_day\": " & isAllDay
                                set jsonObj to jsonObj & ", \"is_recurring\": " & isRecurring
                                set jsonObj to jsonObj & ", \"status\": \"" & evtStatus & "\"}"

                                set end of jsonResults to jsonObj
                            end if
                        end if
                    end repeat
                end try
            end if

            -- Stop if we have enough results
            if (count of jsonResults) >= maxResults then
                exit repeat
            end if
        end repeat

        set AppleScript's text item delimiters to ", "
        set resultsJson to "[" & (jsonResults as text) & "]"

        return "{\"calendars_searched\": " & (count of calendarsSearched) & ", \"total_matches\": " & matchCount & ", \"returned\": " & (count of jsonResults) & ", \"offset\": " & skipCount & ", \"results\": " & resultsJson & "}"
    end tell
end run

on replaceText(theText, searchStr, replaceStr)
    if theText is missing value then return ""
    set AppleScript's text item delimiters to searchStr
    set textItems to text items of theText
    set AppleScript's text item delimiters to replaceStr
    set theText to textItems as text
    set AppleScript's text item delimiters to ""
    return theText
end replaceText

on formatDateTime(theDate)
    set y to year of theDate as string
    set m to (month of theDate as integer) as string
    if length of m is 1 then set m to "0" & m
    set d to day of theDate as string
    if length of d is 1 then set d to "0" & d
    set h to hours of theDate as string
    if length of h is 1 then set h to "0" & h
    set min to minutes of theDate as string
    if length of min is 1 then set min to "0" & min
    return y & "-" & m & "-" & d & "T" & h & ":" & min
end formatDateTime

-- Parse ISO date (YYYY-MM-DD) into AppleScript date
on parseISODate(isoDateStr)
    set AppleScript's text item delimiters to "-"
    set dateParts to text items of isoDateStr
    set AppleScript's text item delimiters to ""

    set y to item 1 of dateParts as integer
    set m to item 2 of dateParts as integer
    set d to item 3 of dateParts as integer

    -- Create a base date and set components in safe order
    set baseDate to current date
    set day of baseDate to 1
    set year of baseDate to y
    set month of baseDate to m
    set day of baseDate to d
    set hours of baseDate to 0
    set minutes of baseDate to 0
    set seconds of baseDate to 0

    return baseDate
end parseISODate
APPLESCRIPT
}

cmd_get() {
    local event_id="$1"

    osascript - "$event_id" <<'APPLESCRIPT'
on run argv
    set evtId to (item 1 of argv) as integer

    tell application "Microsoft Outlook"
        try
            set evt to calendar event id evtId

            set evtSubject to subject of evt
            set evtStart to start time of evt
            set evtEnd to end time of evt
            set isAllDay to all day flag of evt
            set isRecurring to is recurring of evt

            -- Get calendar info
            set evtCal to calendar of evt
            set calName to name of evtCal
            set calId to id of evtCal

            -- Location (may be missing value)
            set evtLocation to ""
            try
                set tmpLoc to location of evt
                if tmpLoc is not missing value then set evtLocation to tmpLoc
            end try

            -- Organizer (may be missing value)
            set evtOrganizer to ""
            try
                set tmpOrg to organizer of evt
                if tmpOrg is not missing value then set evtOrganizer to tmpOrg
            end try

            -- Content/body (may be missing)
            set evtContent to ""
            try
                set tmpContent to plain text content of evt
                if tmpContent is not missing value then set evtContent to tmpContent
            end try

            -- Is private
            set isPrivate to false
            try
                set isPrivate to is private of evt
            end try

            -- Format times
            set startStr to my formatDateTime(evtStart)
            set endStr to my formatDateTime(evtEnd)

            -- Escape strings for JSON
            set cleanSubject to my replaceText(evtSubject, "\\", "\\\\")
            set cleanSubject to my replaceText(cleanSubject, "\"", "\\\"")
            set cleanSubject to my replaceText(cleanSubject, return, " ")
            set cleanSubject to my replaceText(cleanSubject, (ASCII character 10), " ")

            set cleanLocation to my replaceText(evtLocation, "\"", "\\\"")
            set cleanOrganizer to my replaceText(evtOrganizer, "\"", "\\\"")
            set cleanContent to my replaceText(evtContent, "\\", "\\\\")
            set cleanContent to my replaceText(cleanContent, "\"", "\\\"")
            set cleanContent to my replaceText(cleanContent, return, "\\n")
            set cleanContent to my replaceText(cleanContent, (ASCII character 10), "\\n")

            -- Get attendees
            set attendeeList to {}
            try
                set attList to attendees of evt
                repeat with att in attList
                    set attName to my replaceText(name of att, "\"", "\\\"")
                    set attEmail to email address of att
                    set end of attendeeList to "{\"name\": \"" & attName & "\", \"email\": \"" & attEmail & "\"}"
                end repeat
            end try

            set AppleScript's text item delimiters to ", "
            set attendeesJson to "[" & (attendeeList as text) & "]"

            set jsonResult to "{\"id\": " & evtId
            set jsonResult to jsonResult & ", \"subject\": \"" & cleanSubject & "\""
            set jsonResult to jsonResult & ", \"start_time\": \"" & startStr & "\""
            set jsonResult to jsonResult & ", \"end_time\": \"" & endStr & "\""
            set jsonResult to jsonResult & ", \"location\": \"" & cleanLocation & "\""
            set jsonResult to jsonResult & ", \"organizer\": \"" & cleanOrganizer & "\""
            set jsonResult to jsonResult & ", \"calendar\": \"" & calName & "\""
            set jsonResult to jsonResult & ", \"calendar_id\": " & calId
            set jsonResult to jsonResult & ", \"is_all_day\": " & isAllDay
            set jsonResult to jsonResult & ", \"is_recurring\": " & isRecurring
            set jsonResult to jsonResult & ", \"is_private\": " & isPrivate
            set jsonResult to jsonResult & ", \"content\": \"" & cleanContent & "\""
            set jsonResult to jsonResult & ", \"attendees\": " & attendeesJson & "}"

            return jsonResult
        on error errMsg
            return "{\"error\": \"" & errMsg & "\"}"
        end try
    end tell
end run

on replaceText(theText, searchStr, replaceStr)
    if theText is missing value then return ""
    set AppleScript's text item delimiters to searchStr
    set textItems to text items of theText
    set AppleScript's text item delimiters to replaceStr
    set theText to textItems as text
    set AppleScript's text item delimiters to ""
    return theText
end replaceText

on formatDateTime(theDate)
    set y to year of theDate as string
    set m to (month of theDate as integer) as string
    if length of m is 1 then set m to "0" & m
    set d to day of theDate as string
    if length of d is 1 then set d to "0" & d
    set h to hours of theDate as string
    if length of h is 1 then set h to "0" & h
    set min to minutes of theDate as string
    if length of min is 1 then set min to "0" & min
    return y & "-" & m & "-" & d & "T" & h & ":" & min
end formatDateTime
APPLESCRIPT
}

cmd_today() {
    local today
    today=$(get_today)
    local tomorrow
    tomorrow=$(get_date_offset 1)

    cmd_search --after "$today" --before "$tomorrow" --limit 50
}

cmd_week() {
    local today
    today=$(get_today)
    local next_week
    next_week=$(get_date_offset 7)

    cmd_search --after "$today" --before "$next_week" --limit 100
}

# --- Main ---

main() {
    [[ $# -eq 0 ]] && die "Usage: outlook-calendar.sh <command> [options]. Commands: calendars, search, get, today, week"

    check_outlook

    local cmd="$1"
    shift

    case "$cmd" in
        calendars)
            cmd_calendars
            ;;
        search)
            cmd_search "$@"
            ;;
        get)
            [[ $# -lt 1 ]] && die "Usage: outlook-calendar.sh get <event_id>"
            cmd_get "$1"
            ;;
        today)
            cmd_today
            ;;
        week)
            cmd_week
            ;;
        *)
            die "Unknown command: $cmd. Use: calendars, search, get, today, week"
            ;;
    esac
}

main "$@"
