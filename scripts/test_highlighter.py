#!/usr/bin/env python3
"""Check the Source page's syntax coloring against skhd lines."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# The highlighter, the modifier table it reads, and the localization helper; the test supplies main().
SOURCES = [
    ROOT / 'Sources/KeyminApp/Localization.swift',
    ROOT / 'Sources/KeyminApp/SkhdSyntax.swift',
    ROOT / 'Sources/KeyminApp/SkhdHighlighter.swift',
    ROOT / 'scripts/test_highlighter.swift',
]

# Compile against AppKit for NSTextStorage and NSColor, then run the checks with a time limit.
with tempfile.TemporaryDirectory(prefix='keymin-highlighter-', dir='/private/tmp') as directory:
    folder = Path(directory)
    executable = folder / 'tests'
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, SOURCES), '-framework', 'AppKit', '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=60)
