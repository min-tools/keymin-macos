#!/usr/bin/env python3
"""Verify Keymin records the selected macOS SDK instead of compatibility SDK 14."""
from pathlib import Path
import os
import re
import subprocess
import tempfile

from build import DEFAULT_DEVELOPER_DIR, swift_compiler

environment = os.environ.copy()
# Select the toolchain the same way build.py does so the check reflects real builds.
if 'DEVELOPER_DIR' not in environment and DEFAULT_DEVELOPER_DIR.is_dir():
    environment['DEVELOPER_DIR'] = str(DEFAULT_DEVELOPER_DIR)

# Compile a trivial program with the shared compiler command, then compare the SDK recorded in its
# build version load command with the SDK xcrun selects.
with tempfile.TemporaryDirectory(prefix='keymin-sdk-linkage-', dir='/private/tmp') as directory:
    folder = Path(directory)
    source = folder / 'main.swift'
    executable = folder / 'sdk-linkage'
    source.write_text('print("Keymin SDK linkage")\n')
    command = swift_compiler() + [
        '-module-cache-path', str(folder / 'modules'),
        '-target', 'arm64-apple-macos14.0',
        str(source),
        '-o', str(executable),
    ]
    subprocess.run(command, check=True, env=environment)
    # vtool prints the load command, including the "sdk" line the linker recorded.
    build = subprocess.check_output(
        ['xcrun', 'vtool', '-show-build', str(executable)],
        text=True,
        env=environment,
    )
    expected = subprocess.check_output(
        ['xcrun', '--sdk', 'macosx', '--show-sdk-version'],
        text=True,
        env=environment,
    ).strip()
    match = re.search(r'^\s*sdk\s+([0-9.]+)$', build, re.MULTILINE)
    assert match is not None, build
    assert match.group(1) == expected, (
        f'Keymin linked SDK {match.group(1)} instead of selected SDK {expected}'
    )

print(f'Keymin SDK linkage: macOS {expected} recorded')
