#!/usr/bin/env python3
"""Compile and run entitlement decisions without StoreKit or an Apple Account."""
from pathlib import Path
import subprocess
import tempfile

from build import ROOT, swift_compiler

# The entitlement logic depends only on Foundation, so it compiles with the test program alone.
with tempfile.TemporaryDirectory(prefix='keymin-entitlements-', dir='/private/tmp') as directory:
    executable = Path(directory) / 'tests'
    command = swift_compiler() + [
        '-swift-version', '5', '-module-cache-path', str(Path(directory) / 'modules'),
        str(ROOT / 'Sources/KeyminApp/ProEntitlementLogic.swift'),
        str(ROOT / 'scripts/test_pro_entitlements.swift'), '-o', str(executable),
    ]
    subprocess.run(command, check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
