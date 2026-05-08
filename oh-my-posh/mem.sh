#!/usr/bin/env bash
# Free + speculative + inactive memory in GiB on macOS.
/usr/bin/vm_stat 2>/dev/null | awk '
  /page size of/ { ps = $8 }
  /Pages free/         { gsub(/\./, "", $3); f = $3 }
  /Pages speculative/  { gsub(/\./, "", $3); s = $3 }
  /Pages inactive/     { gsub(/\./, "", $3); i = $3 }
  END {
    if (ps && f) printf "%.1fG", (f + s + i) * ps / 1073741824
  }
'
