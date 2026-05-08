#!/usr/bin/env bash
# 1-minute load average on macOS.
/usr/bin/uptime 2>/dev/null | sed -E 's/.*load averages?: *//; s/,.*//; s/ .*//'
