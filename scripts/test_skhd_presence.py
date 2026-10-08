#!/usr/bin/env python3
"""Check how the first screen decides whether skhd is installed and running."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# The presence check, the store it asks for the home directory, and the localization helper;
# the test program supplies main().
SOURCES = [
    ROOT / 'Sources/KeyminApp/Localization.swift',
    ROOT / 'Sources/KeyminApp/ConfigStore.swift',
    ROOT / 'Sources/KeyminApp/SkhdPresence.swift',
    ROOT / 'scripts/test_skhd_presence.swift',
]

# Compile against AppKit, which the store imports, then run the checks with a time limit.
with tempfile.TemporaryDirectory(prefix='keymin-skhd-presence-', dir='/private/tmp') as directory:
    folder = Path(directory)
    executable = folder / 'presence-tests'
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, SOURCES), '-framework', 'AppKit', '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=60)
