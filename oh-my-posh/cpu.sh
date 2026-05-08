#!/usr/bin/env bash
# CPU usage % across all cores. Try `top` first, fall back to `ps`.
out=$(top -l 1 -n 0 2>/dev/null | awk '/CPU usage/ {gsub("%","",$3); gsub("%","",$5); printf "%.0f%%\n", $3 + $5}')
if [[ -z "$out" ]]; then
  cores=$(sysctl -n hw.ncpu 2>/dev/null || echo 1)
  out=$(ps -A -o %cpu | awk -v c="$cores" 'NR>1 {s+=$1} END {printf "%.0f%%\n", s/c}')
fi
echo "$out"
