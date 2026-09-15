#!/usr/bin/env python3
"""Build the native monitor and register it with the existing jobs controller."""
import argparse
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-only', action='store_true', help='Atomically replace the binary; preserve installed plist, app metadata and config')
args = parser.parse_args()
repo = Path(__file__).resolve().parents[3]
home = Path.home()
app = repo / 'build/Resource Watch.app'
binary = app / 'Contents/MacOS/resource-watch'
if args.build_only and not binary.is_file():
    raise SystemExit('--build-only requires an existing installation')
binary.parent.mkdir(parents=True, exist_ok=True)
# Compile alongside the installed image, then replace it atomically. A running
# monitor keeps its existing image until the jobs controller reloads it.
with tempfile.TemporaryDirectory(prefix='.resource-watch-build-', dir=binary.parent) as staging:
    built = Path(staging) / binary.name
    sources = ['main.swift', 'ProcessSampling.swift', 'Telemetry.swift', 'IncidentPolicy.swift',
               'IncidentStore.swift', 'SafeActions.swift', 'PromptUI.swift', 'AdditionalDiagnostics.swift']
    subprocess.run(['swiftc', *[str(Path(__file__).with_name(name)) for name in sources],
                    '-O', '-framework', 'Cocoa', '-o', str(built)], check=True)
    os.replace(built, binary)
if args.build_only:
    print(f'Updated {binary}; reload only resource-watch through jobs/ctl')
    raise SystemExit(0)
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
