#!/usr/bin/env bash
#
# outlook-email.sh - Outlook email access via AppleScript (macOS only)
#
# Usage:
#   outlook-email.sh folders              List all folders with IDs and counts
#   outlook-email.sh search [options]     Search emails
#   outlook-email.sh get <message_id>     Get single email by ID
#   outlook-email.sh thread <conv_id>     Get email thread
#
# Search options:
#   --folder <name|id>    Search specific folder by name or ID (searches all matches)
#                         Without --folder, searches common folders: Inbox, Sent Items
#   --subject <term>      Filter by subject containing term
#   --sender <email>      Filter by sender email address
#   --after <date>        Filter emails after date (YYYY-MM-DD)
#   --before <date>       Filter emails before date (YYYY-MM-DD)
#   --limit <n>           Maximum results (default: 50)
#   --offset <n>          Skip first n results (default: 0)
#
# Note: If no date filter is provided, defaults to last 90 days to prevent
#       timeout on large folders. Check "date_filter_defaulted" in output.
#
# Examples:
#   outlook-email.sh folders
#   outlook-email.sh search --subject "Azure" --after 2025-01-01 --limit 10
#   outlook-email.sh search --folder "Sent Items" --after 2025-01-01
#   outlook-email.sh search --folder 117 --limit 5
#   outlook-email.sh get 12345
#
# Output:
#   All commands output JSON to stdout. Errors go to stderr.
#
# Requirements:
#   - macOS with Microsoft Outlook installed
#   - Outlook must be running

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

# --- Commands ---

cmd_folders() {
    osascript <<'APPLESCRIPT'
tell application "Microsoft Outlook"
    set allFolders to mail folders
    set jsonParts to {}

    repeat with f in allFolders
        set fid to id of f

        -- Handle potentially missing folder name
        set fname to "unknown"
        try
            set tmpName to name of f
            if tmpName is not missing value then
                set fname to tmpName
            end if
        end try

        try
            set msgCount to count of messages of f
        on error
            set msgCount to 0
        end try

        -- Escape folder name for JSON (handle missing value)
        if fname is not "unknown" then
            set cleanName to my replaceText(fname, "\\", "\\\\")
            set cleanName to my replaceText(cleanName, "\"", "\\\"")
        else
            set cleanName to "unknown"
        end if

        set jsonObj to "{\"id\": " & fid & ", \"name\": \"" & cleanName & "\", \"count\": " & msgCount & "}"
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
    local folder=""
    local subject=""
    local sender=""
    local after_date=""
    local before_date=""
    local limit=50
    local offset=0

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --folder) folder="$2"; shift 2 ;;
            --subject) subject="$2"; shift 2 ;;
            --sender) sender="$2"; shift 2 ;;
            --after) after_date="$2"; shift 2 ;;
            --before) before_date="$2"; shift 2 ;;
            --limit) limit="$2"; shift 2 ;;
            --offset) offset="$2"; shift 2 ;;
            *) die "Unknown option: $1. Usage: search [--folder name|id] [--subject term] [--sender email] [--after YYYY-MM-DD] [--before YYYY-MM-DD] [--limit N]" ;;
        esac
    done

    # If no folder specified, search common folders
    if [[ -z "$folder" ]]; then
        folder="Inbox,Sent Items,Sent"
    fi

    # Default to 90 days if no date filter provided (prevents timeout on large folders)
    local date_defaulted="false"
    if [[ -z "$after_date" ]] && [[ -z "$before_date" ]]; then
        after_date=$(date -v-90d +%Y-%m-%d)
        date_defaulted="true"
    fi

    osascript - "$folder" "$subject" "$sender" "$after_date" "$before_date" "$limit" "$offset" "$date_defaulted" <<'APPLESCRIPT'
on run argv
    set folderSpec to item 1 of argv
    set subjectFilter to item 2 of argv
    set senderFilter to item 3 of argv
    set afterDateStr to item 4 of argv
    set beforeDateStr to item 5 of argv
    set maxResults to (item 6 of argv) as integer
    set skipCount to (item 7 of argv) as integer
    set dateDefaulted to item 8 of argv

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

        -- Parse folder specification - support mixed names and IDs
        set targetFolderIds to {}
        set targetFolderNames to {}

        set AppleScript's text item delimiters to ","
        set specParts to text items of folderSpec
        set AppleScript's text item delimiters to ""

        repeat with part in specParts
            try
                set partInt to (part as integer)
                set end of targetFolderIds to partInt
            on error
                set end of targetFolderNames to (part as text)
            end try
        end repeat

        set allFolders to mail folders
        set jsonResults to {}
        set matchCount to 0
        set skipped to 0
        set foldersSearched to {}

        repeat with f in allFolders
            set fname to name of f
            set fid to id of f
            set shouldSearch to false

            -- Check if we should search this folder (supports mixed IDs and names)
            repeat with tid in targetFolderIds
                if fid is (tid as integer) then
                    set shouldSearch to true
                    exit repeat
                end if
            end repeat
            if not shouldSearch then
                repeat with targetName in targetFolderNames
                    if fname is (targetName as text) then
                        set shouldSearch to true
                        exit repeat
                    end if
                end repeat
            end if

            if shouldSearch then
                set end of foldersSearched to fname & " (" & fid & ")"

                -- Determine which filters are active
                set hasSubject to (subjectFilter is not "")
                set hasAfter to (afterDate is not missing value)
                set hasBefore to (beforeDate is not missing value)
                set hasSender to (senderFilter is not "")

                -- Try optimized 'whose' query first (fast on large folders)
                set msgList to {}
                set whoseErrored to false
                try
                    if hasSubject and hasAfter and hasBefore and hasSender then
                        set msgList to (messages of f whose subject contains subjectFilter and time sent ≥ afterDate and time sent ≤ beforeDate and headers contains senderFilter)
                    else if hasSubject and hasAfter and hasSender then
                        set msgList to (messages of f whose subject contains subjectFilter and time sent ≥ afterDate and headers contains senderFilter)
                    else if hasSubject and hasBefore and hasSender then
                        set msgList to (messages of f whose subject contains subjectFilter and time sent ≤ beforeDate and headers contains senderFilter)
                    else if hasAfter and hasBefore and hasSender then
                        set msgList to (messages of f whose time sent ≥ afterDate and time sent ≤ beforeDate and headers contains senderFilter)
                    else if hasSubject and hasAfter and hasBefore then
                        set msgList to (messages of f whose subject contains subjectFilter and time sent ≥ afterDate and time sent ≤ beforeDate)
                    else if hasSubject and hasAfter then
                        set msgList to (messages of f whose subject contains subjectFilter and time sent ≥ afterDate)
                    else if hasSubject and hasBefore then
                        set msgList to (messages of f whose subject contains subjectFilter and time sent ≤ beforeDate)
                    else if hasSubject and hasSender then
                        set msgList to (messages of f whose subject contains subjectFilter and headers contains senderFilter)
                    else if hasAfter and hasBefore then
                        set msgList to (messages of f whose time sent ≥ afterDate and time sent ≤ beforeDate)
                    else if hasAfter and hasSender then
                        set msgList to (messages of f whose time sent ≥ afterDate and headers contains senderFilter)
                    else if hasBefore and hasSender then
                        set msgList to (messages of f whose time sent ≤ beforeDate and headers contains senderFilter)
                    else if hasSubject then
                        set msgList to (messages of f whose subject contains subjectFilter)
                    else if hasAfter then
                        set msgList to (messages of f whose time sent ≥ afterDate)
                    else if hasBefore then
                        set msgList to (messages of f whose time sent ≤ beforeDate)
                    else if hasSender then
                        set msgList to (messages of f whose headers contains senderFilter)
                    else
                        set msgList to messages of f
                    end if
                on error
                    set whoseErrored to true
                end try

                -- Fallback: get all messages if whose failed on this folder
                if whoseErrored then
                    try
                        set msgList to messages of f
                    end try
                end if

                -- Iterate with full filter verification
                -- (redundant when whose worked, essential for fallback)
                repeat with msg in msgList
                    set includeMsg to true

                    -- Verify date filters
                    try
                        set msgDate to time sent of msg
                        if hasAfter then
                            if msgDate < afterDate then set includeMsg to false
                        end if
                        if includeMsg and hasBefore then
                            if msgDate > beforeDate then set includeMsg to false
                        end if
                    on error
                        set includeMsg to false
                    end try

                    -- Verify subject filter
                    if includeMsg and hasSubject then
                        if subject of msg does not contain subjectFilter then set includeMsg to false
                    end if

                    -- Get sender (needed for both filter check and JSON output)
                    if includeMsg then
                        set msgSender to sender of msg
                        set senderAddr to address of msgSender
                        if hasSender then
                            if senderAddr does not contain senderFilter then set includeMsg to false
                        end if
                    end if

                    if includeMsg then
                        set matchCount to matchCount + 1

                        -- Handle offset
                        if skipped < skipCount then
                            set skipped to skipped + 1
                        else if (count of jsonResults) < maxResults then
                            -- Get message properties for JSON
                            set msgId to id of msg
                            set msgSubject to subject of msg
                            set msgDate to time sent of msg
                            set senderName to name of msgSender
                            set convId to conversation id of msg
                            set isPartial to is partially downloaded of msg

                            -- Format date
                            set y to year of msgDate as string
                            set m to (month of msgDate as integer) as string
                            if length of m is 1 then set m to "0" & m
                            set d to day of msgDate as string
                            if length of d is 1 then set d to "0" & d
                            set dateStr to y & "-" & m & "-" & d

                            -- Escape subject for JSON
                            set cleanSubject to my replaceText(msgSubject, "\\", "\\\\")
                            set cleanSubject to my replaceText(cleanSubject, "\"", "\\\"")
                            set cleanSubject to my replaceText(cleanSubject, return, " ")
                            set cleanSubject to my replaceText(cleanSubject, (ASCII character 10), " ")

                            set cleanSenderName to my replaceText(senderName, "\"", "\\\"")

                            set jsonObj to "{\"id\": " & msgId
                            set jsonObj to jsonObj & ", \"subject\": \"" & cleanSubject & "\""
                            set jsonObj to jsonObj & ", \"sender_email\": \"" & senderAddr & "\""
                            set jsonObj to jsonObj & ", \"sender_name\": \"" & cleanSenderName & "\""
                            set jsonObj to jsonObj & ", \"date\": \"" & dateStr & "\""
                            set jsonObj to jsonObj & ", \"folder\": \"" & fname & "\""
                            set jsonObj to jsonObj & ", \"folder_id\": " & fid
                            set jsonObj to jsonObj & ", \"conversation_id\": " & convId
                            set jsonObj to jsonObj & ", \"is_partial\": " & isPartial & "}"

                            set end of jsonResults to jsonObj
                        end if
                    end if
                end repeat
            end if

            -- Stop if we have enough results
            if (count of jsonResults) >= maxResults then
                exit repeat
            end if
        end repeat

        set AppleScript's text item delimiters to ", "
        set resultsJson to "[" & (jsonResults as text) & "]"
        set foldersJson to "[\"" & (foldersSearched as text) & "\"]"

        return "{\"folders_searched\": " & (count of foldersSearched) & ", \"total_matches\": " & matchCount & ", \"returned\": " & (count of jsonResults) & ", \"offset\": " & skipCount & ", \"date_filter_defaulted\": " & dateDefaulted & ", \"results\": " & resultsJson & "}"
    end tell
end run

on replaceText(theText, searchStr, replaceStr)
    set AppleScript's text item delimiters to searchStr
    set textItems to text items of theText
    set AppleScript's text item delimiters to replaceStr
    set theText to textItems as text
    set AppleScript's text item delimiters to ""
    return theText
end replaceText

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
    local msg_id="$1"

    osascript - "$msg_id" <<'APPLESCRIPT'
on run argv
    set msgId to (item 1 of argv) as integer

    tell application "Microsoft Outlook"
        try
            set msg to message id msgId

            set msgSubject to subject of msg
            set msgSender to sender of msg
            set senderAddr to address of msgSender
            set senderName to name of msgSender
            set msgDate to time sent of msg
            set msgReceived to time received of msg
            set convId to conversation id of msg
            set isPartial to is partially downloaded of msg
            set isRead to is read of msg
            set msgFolder to folder of msg
            set folderName to name of msgFolder
            set folderId to id of msgFolder

            -- Format dates
            set dateSentStr to my formatDateTime(msgDate)
            set dateRecvStr to my formatDateTime(msgReceived)

            -- Get content (may be empty if partially downloaded)
            set msgContent to ""
            try
                set msgContent to plain text content of msg
            end try

            -- Escape strings for JSON
            set cleanSubject to my replaceText(msgSubject, "\\", "\\\\")
            set cleanSubject to my replaceText(cleanSubject, "\"", "\\\"")
            set cleanSubject to my replaceText(cleanSubject, return, " ")
            set cleanSubject to my replaceText(cleanSubject, (ASCII character 10), " ")

            set cleanSenderName to my replaceText(senderName, "\"", "\\\"")

            set cleanContent to my replaceText(msgContent, "\\", "\\\\")
            set cleanContent to my replaceText(cleanContent, "\"", "\\\"")
            set cleanContent to my replaceText(cleanContent, return, "\\n")
            set cleanContent to my replaceText(cleanContent, (ASCII character 10), "\\n")
            set cleanContent to my replaceText(cleanContent, tab, " ")

            -- Get recipients
            set toRecips to {}
            try
                set toList to to recipients of msg
                repeat with r in toList
                    set rName to my replaceText(name of r, "\"", "\\\"")
                    set end of toRecips to "{\"name\": \"" & rName & "\", \"email\": \"" & address of r & "\"}"
                end repeat
            end try

            set ccRecips to {}
            try
                set ccList to cc recipients of msg
                repeat with r in ccList
                    set rName to my replaceText(name of r, "\"", "\\\"")
                    set end of ccRecips to "{\"name\": \"" & rName & "\", \"email\": \"" & address of r & "\"}"
                end repeat
            end try

            set AppleScript's text item delimiters to ", "
            set toJson to "[" & (toRecips as text) & "]"
            set ccJson to "[" & (ccRecips as text) & "]"

            set jsonResult to "{\"id\": " & msgId
            set jsonResult to jsonResult & ", \"subject\": \"" & cleanSubject & "\""
            set jsonResult to jsonResult & ", \"sender_email\": \"" & senderAddr & "\""
            set jsonResult to jsonResult & ", \"sender_name\": \"" & cleanSenderName & "\""
            set jsonResult to jsonResult & ", \"date_sent\": \"" & dateSentStr & "\""
            set jsonResult to jsonResult & ", \"date_received\": \"" & dateRecvStr & "\""
            set jsonResult to jsonResult & ", \"folder\": \"" & folderName & "\""
            set jsonResult to jsonResult & ", \"folder_id\": " & folderId
            set jsonResult to jsonResult & ", \"conversation_id\": " & convId
            set jsonResult to jsonResult & ", \"is_read\": " & isRead
            set jsonResult to jsonResult & ", \"is_partial\": " & isPartial
            set jsonResult to jsonResult & ", \"to\": " & toJson
            set jsonResult to jsonResult & ", \"cc\": " & ccJson
            set jsonResult to jsonResult & ", \"content\": \"" & cleanContent & "\"}"

            return jsonResult
        on error errMsg
            return "{\"error\": \"" & errMsg & "\"}"
        end try
    end tell
end run

on replaceText(theText, searchStr, replaceStr)
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

cmd_thread() {
    local conv_id="$1"
    local limit="${2:-20}"

    osascript - "$conv_id" "$limit" <<'APPLESCRIPT'
on run argv
    set targetConvId to (item 1 of argv) as integer
    set maxResults to (item 2 of argv) as integer

    tell application "Microsoft Outlook"
        set allFolders to mail folders
        set jsonResults to {}
        set matchCount to 0

        repeat with f in allFolders
            try
                set msgList to messages of f
                set fname to name of f
                set fid to id of f

                repeat with msg in msgList
                    if conversation id of msg is targetConvId then
                        set matchCount to matchCount + 1

                        if (count of jsonResults) < maxResults then
                            set msgId to id of msg
                            set msgSubject to subject of msg
                            set msgSender to sender of msg
                            set senderAddr to address of msgSender
                            set senderName to name of msgSender
                            set msgDate to time sent of msg
                            set isPartial to is partially downloaded of msg

                            -- Format date
                            set y to year of msgDate as string
                            set m to (month of msgDate as integer) as string
                            if length of m is 1 then set m to "0" & m
                            set d to day of msgDate as string
                            if length of d is 1 then set d to "0" & d
                            set dateStr to y & "-" & m & "-" & d

                            set cleanSubject to my replaceText(msgSubject, "\\", "\\\\")
                            set cleanSubject to my replaceText(cleanSubject, "\"", "\\\"")
                            set cleanSubject to my replaceText(cleanSubject, return, " ")
                            set cleanSubject to my replaceText(cleanSubject, (ASCII character 10), " ")

                            set cleanSenderName to my replaceText(senderName, "\"", "\\\"")

                            set jsonObj to "{\"id\": " & msgId
                            set jsonObj to jsonObj & ", \"subject\": \"" & cleanSubject & "\""
                            set jsonObj to jsonObj & ", \"sender_email\": \"" & senderAddr & "\""
                            set jsonObj to jsonObj & ", \"sender_name\": \"" & cleanSenderName & "\""
                            set jsonObj to jsonObj & ", \"date\": \"" & dateStr & "\""
                            set jsonObj to jsonObj & ", \"folder\": \"" & fname & "\""
                            set jsonObj to jsonObj & ", \"folder_id\": " & fid
                            set jsonObj to jsonObj & ", \"is_partial\": " & isPartial & "}"

                            set end of jsonResults to jsonObj
                        end if
                    end if
                end repeat
            end try
        end repeat

        set AppleScript's text item delimiters to ", "
        set resultsJson to "[" & (jsonResults as text) & "]"

        return "{\"conversation_id\": " & targetConvId & ", \"total_in_thread\": " & matchCount & ", \"returned\": " & (count of jsonResults) & ", \"messages\": " & resultsJson & "}"
    end tell
end run

on replaceText(theText, searchStr, replaceStr)
    set AppleScript's text item delimiters to searchStr
    set textItems to text items of theText
    set AppleScript's text item delimiters to replaceStr
    set theText to textItems as text
    set AppleScript's text item delimiters to ""
    return theText
end replaceText
APPLESCRIPT
}

# --- Main ---

main() {
    [[ $# -eq 0 ]] && die "Usage: outlook-email.sh <command> [options]. Commands: folders, search, get, thread"

    check_outlook

    local cmd="$1"
    shift

    case "$cmd" in
        folders)
            cmd_folders
            ;;
        search)
            cmd_search "$@"
            ;;
        get)
            [[ $# -lt 1 ]] && die "Usage: outlook-email.sh get <message_id>"
            cmd_get "$1"
            ;;
        thread)
            [[ $# -lt 1 ]] && die "Usage: outlook-email.sh thread <conversation_id> [limit]"
            cmd_thread "$@"
            ;;
        *)
            die "Unknown command: $cmd. Use: folders, search, get, thread"
            ;;
    esac
}

main "$@"
