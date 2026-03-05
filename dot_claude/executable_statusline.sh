#!/bin/bash
# Claude Code statusline - 2 lines: model/context/git, rate limits

input=$(cat)

# Extract all fields in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "Unknown")",
  @sh "CONTEXT_PCT=\(.context_window.used_percentage // 0 | floor | tostring)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0 | tostring)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0 | tostring)",
  @sh "CWD=\(.workspace.current_dir // ".")",
  @sh "COST=\(.cost.total_cost_usd // 0 | tostring)"
' 2>/dev/null)"

# Git branch + dirty state
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "n/a")
DIRTY=$(git -C "$CWD" diff --quiet HEAD 2>/dev/null && echo "" || echo " ●")

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
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code"
CACHE_FILE="$CACHE_DIR/usage-cache.json"
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
        mkdir -p "$CACHE_DIR"
        echo "$resp" | jq --argjson ts "$now" '. + {cached_at: $ts}' > "$CACHE_FILE" 2>/dev/null
        chmod 600 "$CACHE_FILE" 2>/dev/null
      fi
    fi
  fi

  if [ -f "$CACHE_FILE" ]; then
    eval "$(jq -r '
      @sh "FIVE_H_UTIL=\(.five_hour.utilization // 0 | floor | tostring)",
      @sh "FIVE_H_RESET=\(.five_hour.resets_at // "")",
      @sh "SEVEN_D_UTIL=\(.seven_day.utilization // 0 | floor | tostring)",
      @sh "SEVEN_D_RESET=\(.seven_day.resets_at // "")"
    ' "$CACHE_FILE" 2>/dev/null)"
  fi
}

# Convert ISO 8601 UTC timestamp to JST short display
format_reset_time() {
  local iso_ts=$1
  local label=$2
  if [ -z "$iso_ts" ]; then
    echo "N/A"
    return
  fi
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
    LANG=en_US.UTF-8 TZ=Asia/Tokyo date -r "$epoch" "+%b %-d %-l%p" 2>/dev/null | sed 's/AM/am/;s/PM/pm/'
  fi
}

fetch_usage

# Format reset times
FIVE_H_RESET_DISPLAY=$(format_reset_time "$FIVE_H_RESET" "5h")
SEVEN_D_RESET_DISPLAY=$(format_reset_time "$SEVEN_D_RESET" "7d")

# Build colored elements
CTX_COLOR=$(color_for_pct "$CONTEXT_PCT")
FIVE_COLOR=$(color_for_pct "$FIVE_H_UTIL")
SEVEN_COLOR=$(color_for_pct "$SEVEN_D_UTIL")
FIVE_BAR=$(build_bar "$FIVE_H_UTIL")
SEVEN_BAR=$(build_bar "$SEVEN_D_UTIL")

# Dirty indicator color
DIRTY_DISPLAY=""
if [ -n "$DIRTY" ]; then
  DIRTY_DISPLAY=" ${RED}●${RESET}"
fi

# Format cost
COST_DISPLAY=""
if [ "$(echo "$COST > 0" | bc 2>/dev/null)" = "1" ]; then
  COST_DISPLAY=" ${GRAY}│${RESET} 💰 \$${COST}"
fi

# Line 1: model | context % | lines changed | cost | branch
printf "🤖 %s ${GRAY}│${RESET} 📊 ${CTX_COLOR}%s%%${RESET} ${GRAY}│${RESET} ✏️  ${GREEN}+%s${RESET}${GRAY}/${RESET}${RED}-%s${RESET}%b ${GRAY}│${RESET} 🔀 %s%b\n" \
  "$MODEL" "$CONTEXT_PCT" "$LINES_ADDED" "$LINES_REMOVED" "$COST_DISPLAY" "$BRANCH" "$DIRTY_DISPLAY"

# Line 2: 5h and 7d rate limits combined
printf "⏰ 5h ${FIVE_COLOR}%s %s%%${RESET} →%s ${GRAY}│${RESET} 📅 7d ${SEVEN_COLOR}%s %s%%${RESET} →%s\n" \
  "$FIVE_BAR" "$FIVE_H_UTIL" "$FIVE_H_RESET_DISPLAY" \
  "$SEVEN_BAR" "$SEVEN_D_UTIL" "$SEVEN_D_RESET_DISPLAY"
