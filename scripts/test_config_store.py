#!/usr/bin/env python3
"""Exercise link resolution and link-preserving writes on a temporary dotfiles layout."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# The store and the localization helper it calls; the test program supplies main().
SOURCES = [
    ROOT / 'Sources/KeyminApp/Localization.swift',
    ROOT / 'Sources/KeyminApp/ConfigStore.swift',
    ROOT / 'scripts/test_config_store.swift',
]

# Compile the test program against AppKit, which the store imports, then run it on a fresh layout.
with tempfile.TemporaryDirectory(prefix='keymin-config-store-', dir='/private/tmp') as directory:
    folder = Path(directory)
    executable = folder / 'tests'
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, SOURCES), '-framework', 'AppKit', '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    # The test program builds its dotfiles and home directories inside this empty directory.
    fixture = folder / 'fixture'
    fixture.mkdir()
    subprocess.run([str(executable), str(fixture)], check=True, timeout=60)
