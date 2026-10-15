#!/usr/bin/env python3
"""Render the README hero images and the Mac App Store screenshots from the fictional hero
configuration, without launching the app."""
from pathlib import Path
import argparse
import subprocess
import tempfile

from build import ROOT, swift_compiler

FIXTURE = ROOT / 'scripts/fixtures/hero.skhdrc'
OUTPUT = ROOT / 'docs/images'
# KeyminApp.swift holds the app's own entry point; the renderer supplies its own.
SOURCES = [path for path in sorted((ROOT / 'Sources/KeyminApp').glob('*.swift')) if path.name != 'KeyminApp.swift']
SOURCES += [ROOT / 'scripts/hero_canvas.swift', ROOT / 'scripts/render_hero.swift']

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument(
    '--app-store', type=Path, default=ROOT / 'private/app-store/screenshots',
    help='directory for the 2880x1800 App Store set (default: private/app-store/screenshots)',
)
parser.add_argument('--no-app-store', action='store_true', help='skip the App Store set')
args = parser.parse_args()

# Build the renderer from the real app sources so the images show the actual views.
with tempfile.TemporaryDirectory(prefix='keymin-hero-', dir='/private/tmp') as directory:
    folder = Path(directory)
    executable = folder / 'render-hero'
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-parse-as-library', '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, SOURCES), '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    OUTPUT.mkdir(parents=True, exist_ok=True)
    # The renderer stages a copy of the fixture in a throwaway home directory under this folder.
    arguments = [str(executable), str(FIXTURE), str(OUTPUT), str(folder)]
    if not args.no_app_store:
        arguments += ['--app-store', str(args.app_store.resolve())]
    subprocess.run(arguments, check=True, timeout=300)
