#!/usr/bin/env python3
"""Build the native monitor and register it with the existing jobs controller."""
import os
from pathlib import Path
import plistlib
import subprocess

repo = Path(__file__).resolve().parents[3]
home = Path.home()
app = repo / 'build/Resource Watch.app'
binary = app / 'Contents/MacOS/resource-watch'
binary.parent.mkdir(parents=True, exist_ok=True)
subprocess.run(['swiftc', str(Path(__file__).with_name('main.swift')), '-O', '-framework', 'Cocoa', '-o', str(binary)], check=True)
(app / 'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.tianli.resource-watch', 'CFBundleName': 'Resource Watch',
    'CFBundleExecutable': 'resource-watch', 'CFBundlePackageType': 'APPL', 'LSUIElement': True,
}))
state = home / 'Library/Application Support/ResourceWatch'
state.mkdir(parents=True, exist_ok=True)
state.chmod(0o700)
source = repo / 'deploy/com.tianli.resource-watch.plist'
source.write_bytes(plistlib.dumps({
    'Label': 'com.tianli.resource-watch', 'ProgramArguments': [str(binary)],
    'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 30,
    'LimitLoadToSessionType': 'Aqua',
    'StandardOutPath': str(home / 'Library/Logs/resource-watch.log'),
    'StandardErrorPath': str(home / 'Library/Logs/resource-watch.err'),
}))
target = home / 'Library/LaunchAgents' / source.name
if target.is_symlink() and target.resolve() == source:
    pass
elif target.exists() or target.is_symlink():
    raise SystemExit(f'Refusing to replace existing file: {target}')
else:
    target.symlink_to(source)
print(f'Installed {target}; enable with jobs/ctl resume resource-watch')
