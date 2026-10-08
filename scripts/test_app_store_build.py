#!/usr/bin/env python3
"""Check App Store packaging mode with a fake compiler."""
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build as builder


class AppStoreBuildTests(unittest.TestCase):
    # setUp(self): Create a minimal checkout with the files build_app reads and a fresh output path.
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix='keymin-app-store-build-', dir='/private/tmp')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'Keymin'
        self.output = Path(self.temp.name) / 'output/Keymin.app'
        # The required source names, one resource, and the real plist inputs satisfy a fake compile.
        files = {
            self.root / 'Sources/KeyminApp/SkhdDocument.swift': '// fixture',
            self.root / 'Sources/KeyminApp/SkhdSyntax.swift': '// fixture',
            self.root / 'Sources/KeyminApp/ConfigStore.swift': '// fixture',
            self.root / 'Sources/KeyminApp/ProStore.swift': '// fixture',
            self.root / 'Sources/KeyminApp/AccessBanner.swift': '// fixture',
            self.root / 'Sources/KeyminApp/Resources/PRIVACY.md': '# fixture\n',
            self.root / 'KeyminInfo.plist': (builder.ROOT / 'KeyminInfo.plist').read_text(),
            self.root / 'KeyminApp.entitlements': (builder.ROOT / 'KeyminApp.entitlements').read_text(),
            self.root / 'Keymin.xcodeproj/project.pbxproj':
                'MARKETING_VERSION = 2.5; CURRENT_PROJECT_VERSION = 25;',
        }
        for path, text in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.command = None

    # compile_fixture(self, command, [**kwargs]): Stand in for swiftc, ignoring subprocess
    # options; record the command and write a placeholder executable where -o points.
    def compile_fixture(self, command, **kwargs):
        self.command = command
        Path(command[command.index('-o') + 1]).write_bytes(b'fixture executable')
        return subprocess.CompletedProcess(command, 0)

    # test_app_store_mode_sets_the_app_store_flag(self): The store flag is passed, the local flag
    # never is, and the bundle still lands at the output path.
    def test_app_store_mode_sets_the_app_store_flag(self):
        with patch.object(builder.subprocess, 'run', side_effect=self.compile_fixture):
            builder.build_app(self.root, self.output, app_store=True, sign=False)
        self.assertIn('KEYMIN_APP_STORE', self.command)
        self.assertNotIn('KEYMIN_LOCAL_BUILD', self.command)
        self.assertTrue(self.output.is_dir())


# Run the tests as a command.
if __name__ == '__main__':
    unittest.main()
