#!/usr/bin/env python3
"""Render the README hero images from the fictional hero configuration, without launching the app."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

FIXTURE = ROOT / 'scripts/fixtures/hero.skhdrc'
OUTPUT = ROOT / 'docs/images'
# KeyminApp.swift holds the app's own entry point; the renderer supplies its own.
SOURCES = [path for path in sorted((ROOT / 'Sources/KeyminApp').glob('*.swift')) if path.name != 'KeyminApp.swift']
SOURCES.append(ROOT / 'scripts/render_hero.swift')

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
    subprocess.run([str(executable), str(FIXTURE), str(OUTPUT), str(folder)], check=True, timeout=120)
