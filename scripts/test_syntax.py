#!/usr/bin/env python3
"""Compile the skhd parser and serializer with a fixture file and check round trips."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# The parser, serializer, syntax tables, open-command helper, and localization helper; the test
# program supplies main().
SOURCES = [
    ROOT / 'Sources/KeyminApp/Localization.swift',
    ROOT / 'Sources/KeyminApp/SkhdSyntax.swift',
    ROOT / 'Sources/KeyminApp/SkhdDocument.swift',
    ROOT / 'Sources/KeyminApp/OpenAppCommand.swift',
    ROOT / 'scripts/test_syntax.swift',
]

# Foundation is enough here; compile, then run the checks on the sample configuration.
with tempfile.TemporaryDirectory(prefix='keymin-syntax-', dir='/private/tmp') as directory:
    executable = Path(directory) / 'tests'
    command = swift_compiler() + [
        '-swift-version', '5', '-warnings-as-errors', '-module-cache-path', str(Path(directory) / 'modules'),
        '-target', 'arm64-apple-macos14.0', *map(str, SOURCES), '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable), str(ROOT / 'scripts/fixtures/sample.skhdrc')], check=True, timeout=60)
