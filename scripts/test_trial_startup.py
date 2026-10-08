#!/usr/bin/env python3
"""Exercise trial startup with delayed transactions and in-memory preferences."""
from pathlib import Path
import os
import subprocess
import tempfile

from build import ROOT, swift_compiler

# Compile the real store; substitute only signed-transaction input and preferences.
source = (ROOT / 'Sources/KeyminApp/ProStore.swift').read_text()
assert source.count('private let defaults = UserDefaults.standard') == 1
source = source.replace('private let defaults = UserDefaults.standard',
                        'private let defaults = TrialFixture.defaults')
source = source.replace('AppTransaction.shared', 'TrialFixture.shared')
source = source.replace('private(set)', '').replace('private ', '')
fixture = (ROOT / 'scripts/test_trial_startup.swift').read_text()
environment = os.environ.copy()
environment.setdefault('DEVELOPER_DIR', '/Applications/Xcode.app/Contents/Developer')

# No app is launched, no Apple Account is used, and preferences stay in memory.
with tempfile.TemporaryDirectory(prefix='keymin-trial-startup-', dir='/private/tmp') as directory:
    folder = Path(directory)
    store = folder / 'ProStore.swift'
    store.write_text(source)
    test = folder / 'Tests.swift'
    test.write_text(fixture)
    for flags, name in (([], 'source'), (['-D', 'KEYMIN_APP_STORE'], 'app-store')):
        binary = folder / name
        subprocess.run(swift_compiler() + [
            '-swift-version', '5', '-warnings-as-errors',
            '-module-cache-path', str(folder / 'modules'), *flags,
            str(ROOT / 'Sources/KeyminApp/BuildEdition.swift'),
            str(ROOT / 'Sources/KeyminApp/EditionSupport.swift'),
            str(ROOT / 'Sources/KeyminApp/ProEntitlementLogic.swift'),
            str(ROOT / 'Sources/KeyminApp/Localization.swift'),
            str(store), str(test), '-o', str(binary),
        ], check=True, env=environment)
        subprocess.run([str(binary)], check=True, timeout=30)
