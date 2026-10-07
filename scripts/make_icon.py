#!/usr/bin/env python3
"""Render the app icon from scripts/render_icon.swift into the bundle and docs."""
from pathlib import Path
import shutil
import subprocess
import tempfile

from build import ROOT, swift_compiler

ICNS = ROOT / 'Sources/KeyminApp/Resources/KeyminIcon.icns'
PREVIEW = ROOT / 'docs/images/icon.png'

# Compile the Swift renderer in a scratch directory and run it there.
with tempfile.TemporaryDirectory(prefix='keymin-icon-', dir='/private/tmp') as directory:
    folder = Path(directory)
    renderer = folder / 'render_icon'
    subprocess.run(swift_compiler() + [
        '-module-cache-path', str(folder / 'modules'), '-target', 'arm64-apple-macos14.0',
        str(ROOT / 'scripts/render_icon.swift'), '-o', str(renderer),
    ], check=True)
    # The renderer takes the .icns and preview PNG paths; copy both into the tree only on success.
    icns = folder / 'KeyminIcon.icns'
    preview = folder / 'icon.png'
    subprocess.run([str(renderer), str(icns), str(preview)], check=True)
    ICNS.parent.mkdir(parents=True, exist_ok=True)
    PREVIEW.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(icns, ICNS)
    shutil.copy2(preview, PREVIEW)
print(f'Wrote {ICNS.relative_to(ROOT)} and {PREVIEW.relative_to(ROOT)}')
