#!/bin/bash

# prevent stale index.lock files. Blocks claude's commits https://github.com/anthropics/claude-code/issues/11005
GIT_OPTIONAL_LOCKS=0

ICON_FOLDER=$'\xF3\xB0\x9D\xB0'
ICON_BRANCH=$'\xF3\xB0\x98\xAC'
ICON_ROBOT=$'\xF3\xB0\x9A\xA9'
ICON_CASH=$'\xF3\xB0\x84\x94'
ICON_TIMER=$'\xF3\xB1\x8E\xAB'

CLOUD_ARG="${1:-}"
case "$CLOUD_ARG" in
  aws)   CLOUD=$'\xEF\x89\xB0'; CLOUD_COLOR="\033[38;5;208m" ;;
  azure) CLOUD=$'\xEE\xAF\x98'; CLOUD_COLOR="\033[94m" ;;
  *)     CLOUD=""; CLOUD_COLOR="" ;;
esac

# Read JSON input from stdin
INPUT=$(cat)
echo "$INPUT" > ~/tmp/status.json
MODEL_RAW=$(echo "$INPUT" | jq -r '.model.display_name // "Claude"')
case "$MODEL_RAW" in
  *opus*|*Opus*) MODEL="opus" ;;
  *sonnet*|*Sonnet*) MODEL="sonnet" ;;
  *haiku*|*Haiku*) MODEL="haiku" ;;
  *) MODEL="$MODEL_RAW" ;;
esac
CWD=$(echo "$INPUT" | jq -r '.workspace.current_dir // .cwd')
DIR=$(echo "$CWD" | sed "s|^$HOME|~|")
COST=$(echo "$INPUT" | jq -r '.cost.total_cost_usd // 0' | awk '{printf "%.2f", $1}')
DURATION_MS=$(echo "$INPUT" | jq -r '.cost.total_duration_ms // 0')
DURATION_SEC=$((DURATION_MS / 1000))
DAYS=$((DURATION_SEC / 86400))
HOURS=$(( (DURATION_SEC % 86400) / 3600 ))
MINS=$(( (DURATION_SEC % 3600) / 60 ))
SECS=$((DURATION_SEC % 60))
CTX_PCT=$(echo "$INPUT" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
CTX_USABLE=$(echo "$CTX_PCT" | awk '{v = $1 * 100 / 83.5; printf "%.0f", (v > 100 ? 100 : v)}')

# Get git info
if cd "$CWD" 2>/dev/null && git rev-parse --is-inside-work-tree &>/dev/null; then
  GIT_EMAIL=$(git config user.email 2>/dev/null)
  case "$GIT_EMAIL" in
    jim.weller@gmail.com) GIT_USER="jw";   GIT_USER_ICON=$'\xEF\x8A\xBB'; GIT_USER_COLOR="\033[38;5;33m" ;;
    jim.weller@mcg.com)   GIT_USER="work"; GIT_USER_ICON=$'\xEF\x91\xAE'; GIT_USER_COLOR="\033[38;5;196m" ;;
    "")                   GIT_USER="" ;;
    *)                    GIT_USER="$GIT_EMAIL"; GIT_USER_ICON=$'\xEF\x8A\xBB'; GIT_USER_COLOR="\033[38;5;29m" ;;
  esac

  BRANCH=$(git branch --show-current 2>/dev/null)

  # Ahead/behind remote
  AHEAD=$(git rev-list --count @{upstream}..HEAD 2>/dev/null || echo 0)
  BEHIND=$(git rev-list --count HEAD..@{upstream} 2>/dev/null || echo 0)

  # Stash count
  STASH=$(git stash list 2>/dev/null | wc -l | tr -d ' ')

  # Use git status --porcelain for staged/unstaged/untracked/conflicted
  GIT_STATUS=$(git status --porcelain 2>/dev/null)
  STAGED=$(echo "$GIT_STATUS" | grep -c '^[MADRC]' 2>/dev/null || echo 0)
  UNSTAGED=$(echo "$GIT_STATUS" | grep -c '^.[MD]' 2>/dev/null || echo 0)
  UNTRACKED=$(echo "$GIT_STATUS" | grep -c '^??' 2>/dev/null || echo 0)
  CONFLICTS=$(echo "$GIT_STATUS" | grep -c '^UU\|^AA\|^DD' 2>/dev/null || echo 0)
fi

if [ "$CTX_USABLE" -ge 90 ]; then
  CTX_COLOR="\033[38;5;196m"
elif [ "$CTX_USABLE" -ge 75 ]; then
  CTX_COLOR="\033[38;5;208m"
elif [ "$CTX_USABLE" -ge 50 ]; then
  CTX_COLOR="\033[38;5;186m"
else
  CTX_COLOR="\033[38;5;114m"
fi

BAR_WIDTH=12
BUFFER_WIDTH=2
FILLED=$((CTX_PCT * BAR_WIDTH / 100))
REMAINING=$((BAR_WIDTH - FILLED))
if [ "$REMAINING" -lt "$BUFFER_WIDTH" ]; then
  BUFFER_SHOW=$REMAINING
else
  BUFFER_SHOW=$BUFFER_WIDTH
fi
EMPTY=$((REMAINING - BUFFER_SHOW))
BAR_FILLED=""
BAR_EMPTY=""
BAR_BUFFER=""
[ "$FILLED" -gt 0 ] && BAR_FILLED=$(printf "%${FILLED}s" | tr ' ' '█')
[ "$EMPTY" -gt 0 ] && BAR_EMPTY=$(printf "%${EMPTY}s" | tr ' ' '█')
[ "$BUFFER_SHOW" -gt 0 ] && BAR_BUFFER=$(printf "%${BUFFER_SHOW}s" | tr ' ' '░')

# Build statusline
[ -n "$CLOUD" ] && printf "${CLOUD_COLOR}${CLOUD}\033[0m | "
printf "\033[38;5;117m${ICON_FOLDER} $DIR\033[0m"
[ -n "$GIT_USER" ] && printf " | ${GIT_USER_COLOR}${GIT_USER_ICON} $GIT_USER\033[0m"
if [ -n "$BRANCH" ]; then
  printf " | \033[33m${ICON_BRANCH} $BRANCH\033[0m"
  # p10k-style git status indicators
  [ "$BEHIND" -gt 0 ] 2>/dev/null && printf " \033[96m⇣$BEHIND\033[0m"
  [ "$AHEAD" -gt 0 ] 2>/dev/null && printf " \033[96m⇡$AHEAD\033[0m"
  [ "$STASH" -gt 0 ] 2>/dev/null && printf " \033[95m*$STASH\033[0m"
  [ "$CONFLICTS" -gt 0 ] 2>/dev/null && printf " \033[91m~$CONFLICTS\033[0m"
  [ "$STAGED" -gt 0 ] 2>/dev/null && printf " \033[92m+$STAGED\033[0m"
  [ "$UNSTAGED" -gt 0 ] 2>/dev/null && printf " \033[93m!$UNSTAGED\033[0m"
  [ "$UNTRACKED" -gt 0 ] 2>/dev/null && printf " \033[97m?$UNTRACKED\033[0m"
fi
printf " | ${CTX_COLOR}${ICON_ROBOT} $MODEL\033[0m"
printf " ${CTX_COLOR}${BAR_FILLED}\033[2;90m${BAR_EMPTY}\033[0m\033[2;90m${BAR_BUFFER}\033[0m ${CTX_COLOR}${CTX_USABLE}%%\033[0m"
printf " | \033[38;5;186m${ICON_CASH} \$${COST}\033[0m"
if [ "$DAYS" -gt 0 ]; then
  DURATION="${DAYS}d ${HOURS}h ${MINS}m ${SECS}s"
elif [ "$HOURS" -gt 0 ]; then
  DURATION="${HOURS}h ${MINS}m ${SECS}s"
elif [ "$MINS" -gt 0 ]; then
  DURATION="${MINS}m ${SECS}s"
else
  DURATION="${SECS}s"
fi
printf " | \033[38;5;250m${ICON_TIMER} ${DURATION}\033[0m"

echo
