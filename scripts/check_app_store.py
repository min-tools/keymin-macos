#!/usr/bin/env python3
"""Report local release failures and optionally verify public submission URLs."""
from datetime import date
from pathlib import Path
import plistlib
import re
import socket
import sys
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parent.parent


# valid_release_version(version, build_number): Accept a YY.M or YY.M.N public version paired with a
# ten-digit YYYYMMDDNN build number whose date exists.
def valid_release_version(version, build_number):
    # Keep public versions compact, without leading zeros or a day component.
    if not isinstance(version, str) or re.fullmatch(r'[0-9]{2}\.(?:[1-9]|1[0-2])(?:\.[1-9][0-9]*)?', version) is None:
        return False
    # Check the date-plus-sequence shape; this does not compare with previous uploads.
    if not isinstance(build_number, str) or re.fullmatch(r'[0-9]{10}', build_number) is None:
        return False
    # A patch can be built in a later month, but its build date must be real.
    try:
        date(int(build_number[:4]), int(build_number[4:6]), int(build_number[6:8]))
    except ValueError:
        return False
    return True


# blockers([check_online=False]): Collect failures from these local release checks.
# With check_online, also fetch the public URLs named in BuildEdition.swift.
def blockers(check_online=False):
    issues = []
    # Load every project file, source file, and policy that the checks below inspect.
    project = (ROOT / 'Keymin.xcodeproj/project.pbxproj').read_text()
    scheme = (ROOT / 'Keymin.xcodeproj/xcshareddata/xcschemes/Keymin.xcscheme').read_text()
    info = plistlib.loads((ROOT / 'KeyminInfo.plist').read_bytes())
    entitlements = plistlib.loads((ROOT / 'KeyminApp.entitlements').read_bytes())
    manifest = plistlib.loads((ROOT / 'Sources/KeyminApp/Resources/PrivacyInfo.xcprivacy').read_bytes())
    edition = (ROOT / 'Sources/KeyminApp/BuildEdition.swift').read_text()
    store = (ROOT / 'Sources/KeyminApp/ConfigStore.swift').read_text()
    products = (ROOT / 'Sources/KeyminApp/ProEntitlementLogic.swift').read_text()
    banner = (ROOT / 'Sources/KeyminApp/AccessBanner.swift').read_text()
    model = (ROOT / 'Sources/KeyminApp/AppModel.swift').read_text()
    pro_store = (ROOT / 'Sources/KeyminApp/ProStore.swift').read_text()
    editors = (ROOT / 'Sources/KeyminApp/ConfigEditorsView.swift').read_text()
    sidebar = (ROOT / 'Sources/KeyminApp/SidebarView.swift').read_text()
    sources = '\n'.join(path.read_text() for path in (ROOT / 'Sources/KeyminApp').glob('*.swift'))
    policy = (ROOT / 'PRIVACY.md').read_text()
    bundled_policy = (ROOT / 'Sources/KeyminApp/Resources/PRIVACY.md').read_text()

    # The store edition is selected by a compile flag at both the project and the target level.
    if project.count('SWIFT_ACTIVE_COMPILATION_CONDITIONS = KEYMIN_APP_STORE;') < 2:
        issues.append('AppStore must compile KEYMIN_APP_STORE at project and target level.')
    # Crash symbols are a target-level setting, so inspect only the target's AppStore block.
    app_store_target = re.search(r'100000000000000000000807.*?name = AppStore;', project, re.S)
    # Without that configuration the scheme below has nothing to archive.
    if app_store_target is None:
        issues.append('The Keymin target is missing its AppStore configuration.')
    # Without dSYMs, App Store crash reports cannot be symbolicated.
    elif 'DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";' not in app_store_target.group():
        issues.append('The AppStore archive must include dSYM crash symbols.')
    # Archiving any other configuration would upload a source edition.
    if '<ArchiveAction buildConfiguration="AppStore"' not in scheme:
        issues.append('The shared scheme must archive the AppStore configuration.')
    # Debug, Release, and AppStore must all produce the same bundle identifier.
    if project.count('PRODUCT_BUNDLE_IDENTIFIER = tools.min.keymin;') < 3:
        issues.append('The Keymin bundle identifier is not consistent across configurations.')
    versions = re.findall(r'MARKETING_VERSION = ([^;]+);', project)
    build_numbers = re.findall(r'CURRENT_PROJECT_VERSION = ([^;]+);', project)
    # All three target configurations must agree on one version and build number.
    if len(versions) != 3 or len(build_numbers) != 3 or len(set(versions)) != 1 or len(set(build_numbers)) != 1:
        issues.append('The release version is inconsistent across configurations.')
    # The agreed pair must also follow the dated release scheme.
    elif not valid_release_version(versions[0].strip('"'), build_numbers[0].strip('"')):
        issues.append('Use a YY.M or YY.M.N public version and a valid YYYYMMDDNN build number.')
    # Info.plist resolves $(KEYMIN_DISPLAY_NAME); an unset configuration would ship a blank name.
    if project.count('KEYMIN_DISPLAY_NAME = Keymin;') != 3:
        issues.append('The Keymin display name is unresolved in one or more target configurations.')
    # Info.plist is hand-written, so its executable name must track the Xcode setting.
    if 'EXECUTABLE_NAME = KeyminApp;' not in project or info.get('CFBundleExecutable') != 'KeyminApp':
        issues.append('The Xcode product and Info.plist executable names do not match.')
    # The store listing promises Apple silicon and macOS 14.
    if 'ARCHS = arm64;' not in project or info.get('LSMinimumSystemVersion') != '14.0':
        issues.append('The supported architecture or minimum macOS version changed.')
    # Release builds are configured to enable the hardened runtime.
    if 'ENABLE_HARDENED_RUNTIME = YES;' not in project:
        issues.append('Hardened Runtime is not enabled.')
    # BuildEdition.swift holds the identity constants and the compile-time guard against local
    # access in store builds.
    if 'tools.min.keymin' not in edition or 'KEYMIN_LOCAL_BUILD && KEYMIN_APP_STORE' not in edition:
        issues.append('The shared app identity or private-build boundary is incomplete.')
    # Both product identifiers must match App Store Connect exactly.
    if 'tools.min.keymin.pro.yearly' not in products or 'tools.min.keymin.pro.lifetime' not in products:
        issues.append('StoreKit product identifiers are incomplete.')
    # The trial length and Free limit are what the listing and privacy policy describe.
    if 'static let trialLengthDays = 30' not in products or 'static let freeBindingLimit = 5' not in products:
        issues.append('The 30-day trial or five-binding Free allowance is missing.')
    # Public builds show the banner only once the entitlement is known and access is limited.
    if 'struct KeyminAccessBanner' not in banner or 'if store.hasResolvedEntitlement && store.hasPreparedFreeAccess && !store.hasFullAccess' not in banner:
        issues.append('The shared access banner is missing from public builds.')
    # The model must trim the editable bindings and route both gated actions to the paywall.
    if 'KeyminFreeAccessPolicy.editableBindings(document.hotkeys, limited: isLimitedToFreeBindings)' not in model \
            or 'presentPro(for: .allBindings)' not in model or 'presentPro(for: .sourceEditing)' not in model:
        issues.append('The Free binding limit is not enforced by the model.')
    # The Source page is a Pro feature once the trial ends.
    if 'if model.isLimitedToFreeBindings' not in editors:
        issues.append('The Source page is not gated after the trial.')
    # Users must learn why bindings beyond the Free limit are hidden.
    if 'model.hiddenBindingCount > 0' not in sidebar:
        issues.append('The sidebar does not explain hidden bindings.')
    # Subscriptions must link to the terms and privacy policy from the purchase panel.
    if 'AppLinks.termsOfUse' not in pro_store or 'AppLinks.privacyPolicy' not in pro_store:
        issues.append('The purchase panel is missing its legal links.')
    # The purchase panel's terms link must be Apple's standard EULA, not a page of the app's own.
    if 'static let termsOfUse = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!' not in edition:
        issues.append("Apple's standard EULA link is missing.")
    # An explicit false skips the export compliance questions on every upload.
    if info.get('ITSAppUsesNonExemptEncryption') is not False:
        issues.append('Encryption export declaration is missing or unresolved.')
    # The About panel shows this notice.
    if info.get('NSHumanReadableCopyright') != '© 2026 Ilia Ross':
        issues.append('The About-panel copyright notice is missing.')
    # The Mac App Store requires the sandbox.
    if not entitlements.get('com.apple.security.app-sandbox'):
        issues.append('App Sandbox is not enabled.')
    # The user picks the skhd configuration file through an open panel.
    if not entitlements.get('com.apple.security.files.user-selected.read-write'):
        issues.append('User-selected file access is missing; the configuration cannot be opened.')
    # Access to the chosen file is kept across launches through a security-scoped bookmark.
    if not entitlements.get('com.apple.security.files.bookmarks.app-scope'):
        issues.append('App-scoped bookmarks are missing; access would not survive a relaunch.')
    # The privacy policy promises an offline app.
    if any(key.startswith('com.apple.security.network') for key in entitlements):
        issues.append('Keymin must not request network access.')
    # The manifest must deny tracking explicitly rather than omit the key.
    if manifest.get('NSPrivacyTracking') is not False:
        issues.append('Privacy manifest tracking declaration is missing.')
    # The manifest must list no collected data types.
    if manifest.get('NSPrivacyCollectedDataTypes') != []:
        issues.append('Keymin collects no data; the privacy manifest must declare none.')
    # The in-app policy window shows the bundled copy, so it must match the published one.
    if not policy.strip() or policy != bundled_policy:
        issues.append('The repository and bundled privacy policies are missing or inconsistent.')
    # Info.plist and the Xcode project must both reference the production icon.
    if info.get('CFBundleIconFile') != 'KeyminIcon' or 'KeyminIcon.icns' not in project:
        issues.append('The production Keymin icon is not configured.')
    # A referenced icon still has to exist on disk.
    if not (ROOT / 'Sources/KeyminApp/Resources/KeyminIcon.icns').is_file():
        issues.append('The Keymin icon file is missing from the bundle resources.')
    for marker in ('.withSecurityScope', 'startAccessingSecurityScopedResource()', 'replaceItemAt(', 'resolveLink('):
        # Each marker is part of the sandbox-safe, link-preserving file access the policy describes.
        if marker not in store:
            issues.append(f'The configuration store no longer uses {marker}.')
    for forbidden in ('Process(', 'NSAppleScript', 'posix_spawn'):
        # The policy promises the app does not run commands itself.
        if forbidden in sources:
            issues.append(f'The app must not run commands: {forbidden}.')
    # Only the first screen's skhd check may name package-manager paths, and only to see whether
    # a file exists there.
    presence = (ROOT / 'Sources/KeyminApp/SkhdPresence.swift').read_text()
    others = '\n'.join(path.read_text() for path in (ROOT / 'Sources/KeyminApp').glob('*.swift') if path.name != 'SkhdPresence.swift')
    for forbidden in ('/opt/homebrew', '/usr/local'):
        # Any other source naming these paths would tie the app to a package manager.
        if forbidden in others:
            issues.append(f'The app must not depend on package managers outside the skhd presence check: {forbidden}.')
    # The presence check must stat paths, never list directories or read file contents.
    if 'fileExists(atPath:' not in presence or any(marker in presence for marker in ('contentsOfDirectory', 'Data(contentsOf', 'String(contentsOf', 'FileHandle')):
        issues.append('The skhd presence check must only test whether files exist.')
    # Resolve and fetch each public URL so a dead listing link is caught before submission.
    if check_online:
        urls = re.findall(r'static let (?:website|privacyPolicy|termsOfUse|support) = URL\(string: "(https://[^"]+)"\)!', edition)
        for url in urls:
            try:
                host = re.match(r'https://([^/]+)', url).group(1)
                socket.getaddrinfo(host, 443, type=socket.SOCK_STREAM)
                request = Request(url, headers={'User-Agent': 'Keymin release checker/1.0'})
                with urlopen(request, timeout=10) as response:
                    # urlopen normally raises HTTPError for 4xx and 5xx; this covers any other handler.
                    if response.status >= 400:
                        issues.append(f'Public submission URL returned HTTP {response.status}: {url}')
            # The host answered with an error status; report that status code.
            except HTTPError as error:
                issues.append(f'Public submission URL returned HTTP {error.code}: {url}')
            # DNS, connection, timeout, and malformed-URL failures all mean the link cannot be reached.
            except (OSError, URLError, AttributeError) as error:
                issues.append(f'Public submission URL is unavailable: {url} ({error})')
    return issues


# Run the audit as a command; --online is the only accepted option.
if __name__ == '__main__':
    unknown = [argument for argument in sys.argv[1:] if argument != '--online']
    # Reject anything else so a typo cannot silently skip the online checks.
    if unknown:
        print(f'Usage: {Path(sys.argv[0]).name} [--online]', file=sys.stderr)
        sys.exit(2)
    found = blockers(check_online='--online' in sys.argv[1:])
    # List every blocker and exit nonzero so release scripts stop here.
    if found:
        print('App Store archive is blocked:')
        for issue in found:
            print(f'- {issue}')
        sys.exit(1)
    print('App Store release metadata checks passed')
