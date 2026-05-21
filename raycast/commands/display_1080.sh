#!/bin/bash
# Raycast parameters
# @raycast.schemaVersion 1
# @raycast.title display_1080
# @raycast.mode fullOutput
# @raycast.icon 📺
# @raycast.packageName Display
# @raycast.description Set external displays to 1080p (1920x1080) for presentation
exec "$(dirname "${BASH_SOURCE[0]}")/display_set.sh" 1080
