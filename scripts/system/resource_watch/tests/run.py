#!/usr/bin/env python3
"""Run resource monitor checks without touching user applications or live settings."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
suites = {
    "sampling": ["ProcessSampling.swift", "Telemetry.swift", "tests/main.swift"],
    "policy": ["IncidentPolicy.swift", "tests/policy/main.swift"],
    "store": ["IncidentPolicy.swift", "IncidentStore.swift", "tests/store/main.swift"],
    "diagnostics": ["ProcessSampling.swift", "AdditionalDiagnostics.swift", "tests/diagnostics/main.swift"],
    "actions": ["ProcessSampling.swift", "SafeActions.swift", "tests/actions/main.swift"],
}
with tempfile.TemporaryDirectory(prefix="resource-watch-checks-") as directory:
    fixture = Path(directory) / "fixture-app"
    subprocess.run(["swiftc", str(root / "tests/actions/FixtureApp.swift"), "-framework", "Cocoa", "-o", str(fixture)], check=True)
    for name, sources in suites.items():
        binary = Path(directory) / name
        subprocess.run(["swiftc", *[str(root / source) for source in sources], "-framework", "Cocoa", "-o", str(binary)], check=True)
        arguments = [str(binary)]
        if name == "actions":
            arguments.extend(["--integration-fixture", str(fixture)])
        subprocess.run(arguments, check=True, cwd=root)
