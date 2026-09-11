#!/bin/bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SRC/../../.." && pwd)"
APP="$ROOT/build/Automation Monitor.app"
mkdir -p "$APP/Contents/MacOS"
xcrun swiftc -O -swift-version 5 -framework AppKit -framework SwiftUI "$SRC/main.swift" -o "$APP/Contents/MacOS/automation-menu"
/usr/bin/python3 - "$APP" <<'PY'
import plistlib,sys
from pathlib import Path
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'cyou.tianli.automation-monitor','CFBundleName':'自动化','CFBundleDisplayName':'自动化','CFBundleExecutable':'automation-menu','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0','CFBundleVersion':'1','LSUIElement':True,'NSHighResolutionCapable':True,'LSMinimumSystemVersion':'14.0','NSAppTransportSecurity':{'NSAllowsLocalNetworking':True}}))
PY
codesign --force --deep --sign - "$APP"
printf '%s\n' "$APP"
