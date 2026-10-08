#!/usr/bin/env python3
"""Check staged source-build packaging with a fake compiler."""
from pathlib import Path
import argparse
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import build as builder


class BuildTests(unittest.TestCase):
    # setUp(self): Create a minimal checkout with the files build_app reads and a fresh output path.
    def setUp(self):
        # Start from an empty environment so the build cannot pick up the workstation's DEVELOPER_DIR.
        environment = patch.dict(builder.os.environ, {}, clear=True)
        environment.start()
        self.addCleanup(environment.stop)
        self.temp = tempfile.TemporaryDirectory(prefix='keymin-build-fixture-', dir='/private/tmp')
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
                'MARKETING_VERSION = 1.2.3; CURRENT_PROJECT_VERSION = 123;',
        }
        for path, text in files.items():
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(text)
        self.commands = []

    # compile_fixture(self, command, [**kwargs]): Stand in for swiftc and check its target.
    # Ignore subprocess options, record the command, and write a placeholder at -o.
    def compile_fixture(self, command, **kwargs):
        self.assertEqual(command[command.index('-target') + 1], 'arm64-apple-macos14.0')
        self.commands.append(command)
        Path(command[command.index('-o') + 1]).write_bytes(b'fixture executable')
        return subprocess.CompletedProcess(command, 0)

    # test_xcrun_selects_the_compiler_and_sdk_together(self): No explicit -sdk, so xcrun picks the
    # SDK that matches the compiler.
    def test_xcrun_selects_the_compiler_and_sdk_together(self):
        command = builder.swift_compiler()
        self.assertEqual(command[:2], ['xcrun', 'swiftc'])
        self.assertNotIn('-sdk', command)

    # test_source_identity_and_version(self): A default build fills Info.plist from the project,
    # passes neither edition flag, and copies the resources.
    def test_source_identity_and_version(self):
        with patch.object(builder.subprocess, 'run', side_effect=self.compile_fixture):
            builder.build_app(self.root, self.output, sign=False)
        info = plistlib.loads((self.output / 'Contents/Info.plist').read_bytes())
        self.assertEqual(info['CFBundleIdentifier'], 'tools.min.keymin')
        self.assertEqual(info['CFBundleDisplayName'], 'Keymin')
        self.assertEqual(info['CFBundleShortVersionString'], '1.2.3')
        self.assertEqual(info['CFBundleVersion'], '123')
        self.assertNotIn('KEYMIN_APP_STORE', self.commands[0])
        self.assertNotIn('KEYMIN_LOCAL_BUILD', self.commands[0])
        self.assertTrue((self.output / 'Contents/Resources/PRIVACY.md').is_file())

    # test_unsupported_architecture_fails_before_compile(self): An Intel request is rejected
    # before swiftc runs.
    def test_unsupported_architecture_fails_before_compile(self):
        with patch.object(builder.subprocess, 'run') as compiler:
            with self.assertRaisesRegex(ValueError, 'arm64'):
                builder.build_app(self.root, self.output, architectures=['x86_64'], sign=False)
            compiler.assert_not_called()

    # test_incomplete_source_fails_before_compile(self): A missing required source is reported
    # before swiftc runs.
    def test_incomplete_source_fails_before_compile(self):
        (self.root / 'Sources/KeyminApp/ConfigStore.swift').unlink()
        with patch.object(builder.subprocess, 'run') as compiler:
            with self.assertRaisesRegex(ValueError, 'source checkout is incomplete'):
                builder.build_app(self.root, self.output, sign=False)
            compiler.assert_not_called()

    # test_failed_compile_preserves_previous_app(self): A compile error leaves the existing bundle
    # untouched because staging happens elsewhere.
    def test_failed_compile_preserves_previous_app(self):
        previous = self.output / 'Contents/Info.plist'
        previous.parent.mkdir(parents=True)
        previous.write_text('previous')
        with patch.object(builder.subprocess, 'run', side_effect=subprocess.CalledProcessError(1, 'swiftc')):
            with self.assertRaises(subprocess.CalledProcessError):
                builder.build_app(self.root, self.output, sign=False)
        self.assertEqual(previous.read_text(), 'previous')

    # test_both_modes_keep_distinct_default_outputs(self): --both builds the source bundle first and
    # the store bundle second, each at its own default path.
    def test_both_modes_keep_distinct_default_outputs(self):
        args = argparse.Namespace(
            output=None, configuration='Release', architectures=['arm64'],
            app_store=False, both=True, unsigned=True,
        )
        with patch.object(builder, 'build_app', side_effect=lambda root, output, **kwargs: Path(output)) as build:
            outputs = builder.build_requested(self.root, args)
        self.assertEqual(outputs, [
            self.root.resolve() / 'build/Keymin.app',
            self.root.resolve() / 'build/app-store/Keymin.app',
        ])
        self.assertNotIn('app_store', build.call_args_list[0].kwargs)
        self.assertTrue(build.call_args_list[1].kwargs['app_store'])

    # test_app_store_mode_uses_its_own_default_output(self): --app-store alone never writes over
    # the local build's path.
    def test_app_store_mode_uses_its_own_default_output(self):
        args = argparse.Namespace(
            output=None, configuration='Release', architectures=None,
            app_store=True, both=False, unsigned=True,
        )
        with patch.object(builder, 'build_app', side_effect=lambda root, output, **kwargs: Path(output)):
            outputs = builder.build_requested(self.root, args)
        self.assertEqual(outputs, [self.root.resolve() / 'build/app-store/Keymin.app'])

    # test_both_modes_reject_one_shared_output(self): --both with --output fails before any build.
    def test_both_modes_reject_one_shared_output(self):
        args = argparse.Namespace(
            output=self.output, configuration='Release', architectures=None,
            app_store=False, both=True, unsigned=True,
        )
        with self.assertRaisesRegex(ValueError, '--output'):
            builder.build_requested(self.root, args)


# Run the tests as a command.
if __name__ == '__main__':
    unittest.main()
