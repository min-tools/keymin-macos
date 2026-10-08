#!/usr/bin/env python3
"""Type-check the App Store variant without building an app bundle."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

sources = sorted((ROOT / 'Sources/KeyminApp').glob('*.swift'))
# Type-check every source with the store flag set; warnings fail the check so archives stay clean.
with tempfile.TemporaryDirectory(prefix='keymin-app-store-source-', dir='/private/tmp') as directory:
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-typecheck', '-module-name', 'KeyminApp',
        '-module-cache-path', str(Path(directory) / 'modules'), '-D', 'KEYMIN_APP_STORE',
        '-target', 'arm64-apple-macos14.0', *map(str, sources),
    ]
    subprocess.run(command, check=True)
print('App Store source type-check passed')
