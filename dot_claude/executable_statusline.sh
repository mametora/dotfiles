#!/bin/bash
# Claude Code statusline - 2 lines: model/context/git, rate limits
# Style: Fine Bar + Gradient (Pattern 4 inspired)

input=$(cat)

# Extract all fields in a single jq call
eval "$(echo "$input" | jq -r '
  @sh "MODEL=\(.model.display_name // "Unknown")",
  @sh "CONTEXT_PCT=\(.context_window.used_percentage // 0 | floor | tostring)",
  @sh "LINES_ADDED=\(.cost.total_lines_added // 0 | tostring)",
  @sh "LINES_REMOVED=\(.cost.total_lines_removed // 0 | tostring)",
  @sh "CWD=\(.workspace.current_dir // ".")",
  @sh "COST=\(.cost.total_cost_usd // 0 | tostring)",
  @sh "FIVE_H_UTIL=\(.rate_limits.five_hour.used_percentage // -1 | tostring)",
  @sh "FIVE_H_RESET=\(.rate_limits.five_hour.resets_at // "" | tostring)",
  @sh "SEVEN_D_UTIL=\(.rate_limits.seven_day.used_percentage // -1 | tostring)",
  @sh "SEVEN_D_RESET=\(.rate_limits.seven_day.resets_at // "" | tostring)"
' 2>/dev/null)"

# Git branch + dirty state
BRANCH=$(git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "n/a")
DIRTY=$(git -C "$CWD" diff --quiet HEAD 2>/dev/null && echo "" || echo " ●")

# ANSI 24-bit colors (aligned with gradient endpoints)
DIFF_GREEN='\033[38;2;0;200;80m'
DIFF_RED='\033[38;2;255;60;60m'
GRAY='\033[38;2;74;88;92m'
BLUE='\033[38;2;110;160;210m'
AMBER='\033[38;2;220;170;60m'
DIM='\033[2m'
R='\033[0m'

# Smooth gradient: green -> yellow -> red
gradient_color() {
  local pct=$1
  if [ "$pct" -lt 50 ] 2>/dev/null; then
    local r=$(( pct * 255 / 50 ))
    printf '\033[38;2;%d;200;80m' "$r"
  else
    local g=$(( 200 - (pct - 50) * 4 ))
    [ "$g" -lt 0 ] && g=0
    printf '\033[38;2;255;%d;60m' "$g"
  fi
}

# Progress bar (10 segments, line style with gradient)
DARK_GRAY='\033[38;2;50;55;60m'

build_bar() {
  local pct=$1
  local width=${2:-10}
  [ "$pct" -gt 100 ] && pct=100
  [ "$pct" -lt 0 ] && pct=0

  local filled=$(( pct * width / 100 ))
  local empty=$(( width - filled ))

  local color
  color=$(gradient_color "$pct")
  local bar="${color}"

  for ((i = 0; i < filled; i++)); do bar+="━"; done
  bar+="${DARK_GRAY}"
  for ((i = 0; i < empty; i++)); do bar+="┄"; done

  bar+="${R}"
  printf '%b' "$bar"
}

# Colored bar + percentage
fmt_bar() {
  local pct=$1
  local color
  color=$(gradient_color "$pct")
  local bar_str
  bar_str=$(build_bar "$pct")
  printf '%b %b%d%%%b' "$bar_str" "$color" "$pct" "$R"
}

# Format remaining time from Unix epoch to relative duration
format_reset_time() {
  local epoch=$1
  if [ -z "$epoch" ]; then
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

# --- Line 1: model │ branch │ diff │ cost ---

DIRTY_DISPLAY=""
if [ -n "$DIRTY" ]; then
  DIRTY_DISPLAY=" ${AMBER}●${R}"
fi

COST_DISPLAY=""
if [ "$(echo "$COST > 0" | bc 2>/dev/null)" = "1" ]; then
  COST_ROUNDED=$(printf '%.2f' "$COST")
  COST_DISPLAY=" ${GRAY}│${R} \$${COST_ROUNDED}"
fi

printf "${BLUE}󰯉${R} %s ${GRAY}│${R} ${BLUE}󰘬${R} %s%b ${GRAY}│${R} ${DIFF_GREEN}+%s${R}${GRAY}/${R}${DIFF_RED}-%s${R}%b\n" \
  "$MODEL" "$BRANCH" "$DIRTY_DISPLAY" "$LINES_ADDED" "$LINES_REMOVED" "$COST_DISPLAY"

# --- Line 2: ctx │ 5h │ 7d ---

FIVE_H_INT=${FIVE_H_UTIL%.*}
SEVEN_D_INT=${SEVEN_D_UTIL%.*}

LINE2="${BLUE}ctx${R} $(fmt_bar "$CONTEXT_PCT")"

if [ "$FIVE_H_INT" -eq -1 ] 2>/dev/null && [ "$SEVEN_D_INT" -eq -1 ] 2>/dev/null; then
  LINE2+=" ${GRAY}│${R} ${BLUE}5h${R} ${DIM}--%%${R} ${GRAY}│${R} ${BLUE}7d${R} ${DIM}--%%${R} ${DIM}[no data]${R}"
else
  for LABEL_PCT_RESET in "5h:${FIVE_H_INT}:${FIVE_H_RESET}" "7d:${SEVEN_D_INT}:${SEVEN_D_RESET}"; do
    IFS=':' read -r LABEL PCT RESET <<< "$LABEL_PCT_RESET"
    [ "$PCT" -eq -1 ] 2>/dev/null && PCT=0

    BAR_STR=$(fmt_bar "$PCT")
    RESET_STR=$(format_reset_time "$RESET")
    RESET_DISPLAY=""
    [ -n "$RESET_STR" ] && RESET_DISPLAY=" 󰔟 ${RESET_STR}"

    LINE2+=" ${GRAY}│${R} ${BLUE}${LABEL}${R} ${BAR_STR}${RESET_DISPLAY}"
  done
fi
printf '%b\n' "$LINE2"
