#!/bin/bash
# Raycast parameters
# @raycast.schemaVersion 1
# @raycast.title display_4k
# @raycast.mode fullOutput
# @raycast.icon 🖥️
# @raycast.packageName System
# @raycast.description Set external displays to 4K (3840x2160)
exec "$(dirname "${BASH_SOURCE[0]}")/display_set.sh" 4k
