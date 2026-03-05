#!/bin/bash
# Claude Code statusline - 3 lines: model/context/git, 5h rate limit, 7d rate limit

input=$(cat)

# Extract fields from stdin JSON
MODEL=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
CONTEXT_PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
LINES_ADDED=$(echo "$input" | jq -r '.cost.total_lines_added // 0')
LINES_REMOVED=$(echo "$input" | jq -r '.cost.total_lines_removed // 0')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // "."')

# Git branch
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "n/a")

# ANSI 24-bit colors
GREEN='\033[38;2;151;201;195m'
YELLOW='\033[38;2;229;192;123m'
RED='\033[38;2;224;108;117m'
GRAY='\033[38;2;74;88;92m'
RESET='\033[0m'

# Color by percentage
color_for_pct() {
  local pct=$1
  if [ "$pct" -ge 80 ] 2>/dev/null; then
    printf '%b' "$RED"
  elif [ "$pct" -ge 50 ] 2>/dev/null; then
    printf '%b' "$YELLOW"
  else
    printf '%b' "$GREEN"
  fi
}

# Progress bar (10 segments, ▰▱)
build_bar() {
  local pct=$1
  local filled=$((pct * 10 / 100))
  [ "$filled" -gt 10 ] && filled=10
  local empty=$((10 - filled))
  local bar=""
  for ((i = 0; i < filled; i++)); do bar="${bar}▰"; done
  for ((i = 0; i < empty; i++)); do bar="${bar}▱"; done
  echo "$bar"
}

# Fetch rate limit usage with 360s cache
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_MAX_AGE=360
FIVE_H_UTIL=0
FIVE_H_RESET=""
SEVEN_D_UTIL=0
SEVEN_D_RESET=""

fetch_usage() {
  local now
  now=$(date +%s)
  local need_fetch=1

  if [ -f "$CACHE_FILE" ]; then
    local cached_at
    cached_at=$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null)
    local age=$(( now - cached_at ))
    if [ "$age" -lt "$CACHE_MAX_AGE" ]; then
      need_fetch=0
    fi
  fi

  if [ "$need_fetch" -eq 1 ]; then
    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
    if [ -n "$token" ]; then
      local resp
      resp=$(curl -sL --max-time 5 -H "x-api-key: $token" "https://console.anthropic.com/api/oauth/usage" 2>/dev/null)
      if echo "$resp" | jq -e '.five_hour' >/dev/null 2>&1; then
        echo "$resp" | jq --argjson ts "$now" '. + {cached_at: $ts}' > "$CACHE_FILE" 2>/dev/null
      fi
    fi
  fi

  if [ -f "$CACHE_FILE" ]; then
    FIVE_H_UTIL=$(jq -r '.five_hour.utilization // 0' "$CACHE_FILE" | cut -d. -f1)
    FIVE_H_RESET=$(jq -r '.five_hour.resets_at // empty' "$CACHE_FILE")
    SEVEN_D_UTIL=$(jq -r '.seven_day.utilization // 0' "$CACHE_FILE" | cut -d. -f1)
    SEVEN_D_RESET=$(jq -r '.seven_day.resets_at // empty' "$CACHE_FILE")
  fi
}

# Convert ISO 8601 UTC timestamp to JST display (English locale)
format_reset_time() {
  local iso_ts=$1
  local label=$2
  if [ -z "$iso_ts" ]; then
    echo "N/A"
    return
  fi
  # Parse UTC timestamp, convert to epoch, then format in JST
  local utc_str
  utc_str=$(echo "$iso_ts" | sed 's/\.[^+]*//; s/+00:00//')
  local epoch
  epoch=$(TZ=UTC date -jf "%Y-%m-%dT%H:%M:%S" "$utc_str" "+%s" 2>/dev/null)
  if [ -z "$epoch" ]; then
    echo "N/A"
    return
  fi
  if [ "$label" = "5h" ]; then
    LANG=en_US.UTF-8 TZ=Asia/Tokyo date -r "$epoch" "+%-l%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
  else
    LANG=en_US.UTF-8 TZ=Asia/Tokyo date -r "$epoch" "+%b %-d at %-l%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
  fi
}

fetch_usage

# Format reset times in JST
FIVE_H_RESET_DISPLAY=$(format_reset_time "$FIVE_H_RESET" "5h")
SEVEN_D_RESET_DISPLAY=$(format_reset_time "$SEVEN_D_RESET" "7d")

# Build bars
CTX_COLOR=$(color_for_pct "$CONTEXT_PCT")
FIVE_COLOR=$(color_for_pct "$FIVE_H_UTIL")
SEVEN_COLOR=$(color_for_pct "$SEVEN_D_UTIL")
FIVE_BAR=$(build_bar "$FIVE_H_UTIL")
SEVEN_BAR=$(build_bar "$SEVEN_D_UTIL")

# Line 1: model | context % | lines changed | branch
printf "🤖 %s ${GRAY}│${RESET} 📊 ${CTX_COLOR}%s%%${RESET} ${GRAY}│${RESET} ✏️  ${GREEN}+%s${RESET}${GRAY}/${RESET}${RED}-%s${RESET} ${GRAY}│${RESET} 🔀 %s\n" \
  "$MODEL" "$CONTEXT_PCT" "$LINES_ADDED" "$LINES_REMOVED" "$BRANCH"

# Line 2: 5-hour rate limit
printf "⏰ 5h  ${FIVE_COLOR}%s${RESET}  ${FIVE_COLOR}%s%%${RESET}  Resets %s (Asia/Tokyo)\n" \
  "$FIVE_BAR" "$FIVE_H_UTIL" "$FIVE_H_RESET_DISPLAY"

# Line 3: 7-day rate limit
printf "📅 7d  ${SEVEN_COLOR}%s${RESET}  ${SEVEN_COLOR}%s%%${RESET}  Resets %s (Asia/Tokyo)\n" \
  "$SEVEN_BAR" "$SEVEN_D_UTIL" "$SEVEN_D_RESET_DISPLAY"
