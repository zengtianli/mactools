#!/bin/bash
set -euo pipefail
# Existing shared image provider credentials; never print their contents.
source "$HOME/.personal_env"
exec /usr/bin/caffeinate -i /Users/tianli/Dev/.venv/bin/python3 /Users/tianli/Dev/tools/mactools/bin/weekly_reports.py "$@"
