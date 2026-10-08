#!/usr/bin/env python3
"""Type-check the complete source build without building an app bundle."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

sources = sorted((ROOT / 'Sources/KeyminApp').glob('*.swift'))
# Type-check every source without edition flags; warnings fail the check so builds stay clean.
with tempfile.TemporaryDirectory(prefix='keymin-source-build-', dir='/private/tmp') as directory:
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-typecheck', '-module-name', 'KeyminApp',
        '-module-cache-path', str(Path(directory) / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, sources),
    ]
    subprocess.run(command, check=True)
print('Complete source build type-check passed')
