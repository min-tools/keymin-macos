#!/usr/bin/env python3
"""Build Keymin locally without requiring signing credentials."""
from pathlib import Path
import argparse
import os
import plistlib
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent


DEFAULT_DEVELOPER_DIR = Path('/Applications/Xcode.app/Contents/Developer')


# swift_compiler(): Return the swiftc command prefix that every build and test script compiles with.
# Let xcrun select Swift and its SDK as one toolchain so the linker records the real SDK version.
# Supply Xcode's compiler plugins when available because SwiftUI needs them on some installations.
def swift_compiler():
    developer = Path(os.environ.get('DEVELOPER_DIR', DEFAULT_DEVELOPER_DIR))
    plugins = developer / 'Platforms/MacOSX.platform/Developer/usr/lib/swift/host/plugins'
    command = ['xcrun', 'swiftc']
    # The Command Line Tools ship no plugin directory; only pass a path that exists.
    if plugins.is_dir():
        command += ['-plugin-path', str(plugins)]
    return command


# build_app(root, output, [configuration='Release'], [architectures=None], [app_store=False],
# [sign=True]): Compile a complete app in staging before replacing a prior bundle. Returns the
# output path. app_store selects the App Store edition; sign applies an ad-hoc signature.
def build_app(root, output, *, configuration='Release', architectures=None,
              app_store=False, sign=True):
    root, output = Path(root).resolve(), Path(output).absolute()
    # The output is deleted and replaced below, so it must be a real bundle path, never a link.
    if output.suffix != '.app' or output.is_symlink():
        raise ValueError('The output must be an .app directory, not a symbolic link.')
    architectures = architectures or ['arm64']
    # The compile target below is fixed, so any other request would be silently ignored.
    if architectures != ['arm64']:
        raise ValueError('Keymin builds target Apple silicon (arm64) only.')

    source_root = root / 'Sources/KeyminApp'
    sources = sorted(source_root.glob('*.swift'))
    required = {'SkhdDocument.swift', 'SkhdSyntax.swift', 'ConfigStore.swift', 'ProStore.swift', 'AccessBanner.swift'}
    # Reject incomplete checkouts before invoking the compiler.
    if not sources or not required.issubset({path.name for path in sources}):
        raise ValueError('The Keymin source checkout is incomplete.')
    output.parent.mkdir(parents=True, exist_ok=True)
    environment = os.environ.copy()
    # Point xcrun at the standard Xcode unless the caller already selected a toolchain.
    if 'DEVELOPER_DIR' not in environment and DEFAULT_DEVELOPER_DIR.is_dir():
        environment['DEVELOPER_DIR'] = str(DEFAULT_DEVELOPER_DIR)

    # Stage the bundle next to the output so the final move stays on one filesystem.
    with tempfile.TemporaryDirectory(prefix='keymin-build-', dir=output.parent) as folder:
        work = Path(folder)
        bundle = work / output.name
        executable = bundle / 'Contents/MacOS/KeyminApp'
        executable.parent.mkdir(parents=True)
        # Compile every source as one module for macOS 14 on Apple silicon.
        command = swift_compiler() + [
            '-swift-version', '5', '-module-name', 'KeyminApp',
            '-module-cache-path', str(work / 'modules'), '-target', 'arm64-apple-macos14.0'
        ]
        command += ['-O', '-whole-module-optimization'] if configuration == 'Release' else ['-Onone', '-D', 'DEBUG']
        # The flag selects the App Store edition in BuildEdition.swift.
        if app_store:
            command += ['-D', 'KEYMIN_APP_STORE']
        command += [*map(str, sources), '-o', str(executable)]
        subprocess.run(command, check=True, env=environment)

        # Fill Info.plist from the Xcode project so both build paths ship the same version.
        shutil.copytree(source_root / 'Resources', bundle / 'Contents/Resources')
        info = (root / 'KeyminInfo.plist').read_text()
        project_path = root / 'Keymin.xcodeproj/project.pbxproj'
        project = project_path.read_text()
        versions = {}
        for key in ('MARKETING_VERSION', 'CURRENT_PROJECT_VERSION'):
            matches = set(re.findall(r'\b' + key + r' = ([^;]+);', project))
            # Every configuration repeats the setting; a mismatch would leave the version ambiguous.
            if len(matches) != 1:
                raise ValueError(f'Expected one consistent {key} in {project_path}.')
            versions[key] = matches.pop().strip('"')
        values = {
            'KEYMIN_DISPLAY_NAME': 'Keymin',
            'PRODUCT_BUNDLE_IDENTIFIER': 'tools.min.keymin',
            **versions,
        }
        for key, value in values.items():
            info = info.replace('$(' + key + ')', value)
        plist = plistlib.loads(info.encode())
        (bundle / 'Contents/Info.plist').write_bytes(plistlib.dumps(plist, sort_keys=False))

        # An ad-hoc signature applies the entitlements, so local runs use the same sandbox rules.
        if sign:
            subprocess.run([
                'codesign', '--force', '--sign', '-', '--entitlements',
                str(root / 'KeyminApp.entitlements'), str(bundle)
            ], check=True)
            subprocess.run(['codesign', '--verify', '--deep', '--strict', str(bundle)], check=True)
        # Replace the previous build only now, after the new one is complete and verified.
        if output.exists():
            # Guard against a mistyped --output deleting an unrelated directory.
            if not (output / 'Contents/Info.plist').is_file():
                raise ValueError('Refusing to replace a directory that is not an app bundle.')
            shutil.rmtree(output)
        shutil.move(bundle, output)
    mode = 'App Store' if app_store else 'source'
    print(f'Built {output} ({", ".join(architectures)}, {mode})', flush=True)
    return output


# arguments([description=__doc__]): Define the command-line options for building one or both editions.
def arguments(description=__doc__):
    parser = argparse.ArgumentParser(description=description)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--configuration', choices=['Debug', 'Release'], default='Release')
    parser.add_argument('--arch', action='append', choices=['arm64'], dest='architectures')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--app-store', action='store_true',
                      help='Build build/app-store/Keymin.app with the App Store flag.')
    mode.add_argument('--both', action='store_true',
                      help='Build both the source and App Store test bundles.')
    parser.add_argument('--unsigned', action='store_true')
    return parser


# build_requested(root, args): Build the bundles the parsed options ask for and return their paths.
def build_requested(root, args):
    root = Path(root).resolve()
    common = {
        'configuration': args.configuration,
        'architectures': args.architectures,
        'sign': not args.unsigned,
    }
    # --both builds each edition at its standard path, so a release review can compare them.
    if args.both:
        # One output path cannot hold two bundles.
        if args.output is not None:
            raise ValueError('--output cannot be used with --both.')
        return [
            build_app(root, root / 'build/Keymin.app', **common),
            build_app(root, root / 'build/app-store/Keymin.app', app_store=True, **common),
        ]

    # Give the App Store test build its own default path so it cannot replace the local build.
    output = args.output or root / (
        'build/app-store/Keymin.app' if args.app_store else 'build/Keymin.app'
    )
    return [build_app(root, output, app_store=args.app_store, **common)]


# Build what the command line asks for when the script runs directly.
if __name__ == '__main__':
    args = arguments().parse_args()
    build_requested(ROOT, args)
