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

# Progress bar (10 segments, thin line style)
DARK_GRAY='\033[38;2;50;55;60m'

build_bar() {
  local pct=$1
  local color=$2
  local filled=$((pct * 10 / 100))
  [ "$filled" -gt 10 ] && filled=10
  local empty=$((10 - filled))
  local bar=""
  bar+="${color}"
  for ((i = 0; i < filled; i++)); do bar+="━"; done
  bar+="${DARK_GRAY}"
  for ((i = 0; i < empty; i++)); do bar+="┄"; done
  bar+="${RESET}"
  echo -e "$bar"
}

# Fetch rate limit usage with 360s cache
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/claude-code"
CACHE_FILE="$CACHE_DIR/usage-cache.json"
CACHE_MAX_AGE=360
CACHE_STALE_AGE=3600
FIVE_H_UTIL=0
FIVE_H_RESET=""
SEVEN_D_UTIL=0
SEVEN_D_RESET=""
USAGE_STALE=0
USAGE_UNAVAILABLE=0

fetch_usage() {
  local now
  now=$(date +%s)
  local need_fetch=1
  local cache_age=-1

  if [ -f "$CACHE_FILE" ]; then
    local cached_at
    cached_at=$(jq -r '.cached_at // 0' "$CACHE_FILE" 2>/dev/null)
    cache_age=$(( now - cached_at ))
    if [ "$cache_age" -lt "$CACHE_MAX_AGE" ]; then
      need_fetch=0
    fi
  fi

  if [ "$need_fetch" -eq 1 ]; then
    local fetch_ok=0
    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null | jq -r '.claudeAiOauth.accessToken // empty')
    if [ -n "$token" ]; then
      local resp
      resp=$(curl -sL --max-time 5 -H "Authorization: Bearer $token" -H "anthropic-beta: oauth-2025-04-20" "https://api.anthropic.com/api/oauth/usage" 2>/dev/null)
      if echo "$resp" | jq -e '.five_hour' >/dev/null 2>&1; then
        mkdir -p "$CACHE_DIR"
        echo "$resp" | jq --argjson ts "$now" '. + {cached_at: $ts}' > "$CACHE_FILE" 2>/dev/null
        chmod 600 "$CACHE_FILE" 2>/dev/null
        cache_age=0
        fetch_ok=1
      fi
    fi

    # If fetch failed and no cache exists, mark as unavailable
    if [ "$fetch_ok" -eq 0 ] && [ ! -f "$CACHE_FILE" ]; then
      USAGE_UNAVAILABLE=1
    fi
  fi

  if [ -f "$CACHE_FILE" ]; then
    eval "$(jq -r '
      @sh "FIVE_H_UTIL=\(.five_hour.utilization // 0 | floor | tostring)",
      @sh "FIVE_H_RESET=\(.five_hour.resets_at // "")",
      @sh "SEVEN_D_UTIL=\(.seven_day.utilization // 0 | floor | tostring)",
      @sh "SEVEN_D_RESET=\(.seven_day.resets_at // "")"
    ' "$CACHE_FILE" 2>/dev/null)"
    if [ "$cache_age" -ge "$CACHE_STALE_AGE" ]; then
      USAGE_STALE=1
    fi
  fi
}

# Format remaining time until reset as relative duration
format_reset_time() {
  local iso_ts=$1
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
  local now
  now=$(date +%s)
  local diff=$(( epoch - now ))
  if [ "$diff" -le 0 ]; then
    echo "now"
    return
  fi
  local days=$(( diff / 86400 ))
  local hrs=$(( (diff % 86400) / 3600 ))
  local mins=$(( (diff % 3600) / 60 ))
  if [ "$days" -ge 1 ]; then
    echo "${days}d${hrs}h"
  else
    echo "${hrs}h${mins}m"
  fi
}

fetch_usage

# Format reset times
FIVE_H_RESET_DISPLAY=$(format_reset_time "$FIVE_H_RESET")
SEVEN_D_RESET_DISPLAY=$(format_reset_time "$SEVEN_D_RESET")

# Build colored elements
CTX_COLOR=$(color_for_pct "$CONTEXT_PCT")
FIVE_COLOR=$(color_for_pct "$FIVE_H_UTIL")
SEVEN_COLOR=$(color_for_pct "$SEVEN_D_UTIL")
FIVE_BAR=$(build_bar "$FIVE_H_UTIL" "$FIVE_COLOR")
SEVEN_BAR=$(build_bar "$SEVEN_D_UTIL" "$SEVEN_COLOR")

# Dirty indicator color
DIRTY_DISPLAY=""
if [ -n "$DIRTY" ]; then
  DIRTY_DISPLAY=" ${RED}●${RESET}"
fi

# Format cost
COST_DISPLAY=""
if [ "$(echo "$COST > 0" | bc 2>/dev/null)" = "1" ]; then
  COST_ROUNDED=$(printf '%.2f' "$COST")
  COST_DISPLAY=" ${GRAY}│${RESET} \$${COST_ROUNDED}"
fi

# Line 1: model │ context │ diff │ branch
printf "󰯉 %s ${GRAY}│${RESET} 󰊚 ${CTX_COLOR}%s%%${RESET} ${GRAY}│${RESET} 󰘬 %s%b ${GRAY}│${RESET} ${GREEN}+%s${RESET}${GRAY}/${RESET}${RED}-%s${RESET}%b\n" \
  "$MODEL" "$CONTEXT_PCT" "$BRANCH" "$DIRTY_DISPLAY" "$LINES_ADDED" "$LINES_REMOVED" "$COST_DISPLAY"

# Line 2: 5h and 7d rate limits
if [ "$USAGE_UNAVAILABLE" -eq 1 ]; then
  printf "${GRAY}5h${RESET} ${YELLOW}--%%${RESET} ${GRAY}│${RESET} ${GRAY}7d${RESET} ${YELLOW}--%%${RESET} ${YELLOW}[no data]${RESET}\n"
else
  STALE_DISPLAY=""
  if [ "$USAGE_STALE" -eq 1 ]; then
    STALE_DISPLAY=" ${YELLOW}[stale]${RESET}"
  fi
  printf "${GRAY}5h${RESET} %b ${FIVE_COLOR}%s%%${RESET} 󰔟 %s ${GRAY}│${RESET} ${GRAY}7d${RESET} %b ${SEVEN_COLOR}%s%%${RESET} 󰔟 %s%b\n" \
    "$FIVE_BAR" "$FIVE_H_UTIL" "$FIVE_H_RESET_DISPLAY" \
    "$SEVEN_BAR" "$SEVEN_D_UTIL" "$SEVEN_D_RESET_DISPLAY" "$STALE_DISPLAY"
fi
