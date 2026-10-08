#!/usr/bin/env python3
"""Check which way pop-up menus open against the room above and below their button."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# The placement logic stands alone, so only it and the test program are compiled.
SOURCES = [
    ROOT / 'Sources/KeyminApp/PopUpMenuPlacement.swift',
    ROOT / 'scripts/test_popup_placement.swift',
]

# Compile against AppKit for NSRect and NSPoint, then run the checks with a time limit.
with tempfile.TemporaryDirectory(prefix='keymin-popup-placement-', dir='/private/tmp') as directory:
    folder = Path(directory)
    executable = folder / 'tests'
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, SOURCES), '-framework', 'AppKit', '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=60)
