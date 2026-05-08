#!/usr/bin/env bash
# Real user-visible storage on macOS lives on the Data volume.
df -h /System/Volumes/Data 2>/dev/null | awk 'NR==2 {print $5}'
