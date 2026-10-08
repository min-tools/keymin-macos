#!/usr/bin/env python3
"""Validate Keymin's language coverage and format safety."""

from pathlib import Path
import json
import re
import subprocess
import sys

from localization_keys import ROOT, source_keys

SOURCE = ROOT / 'Sources/KeyminApp'
RESOURCES = SOURCE / 'Resources'
LANGUAGES = ['en']
# printf-style directives: optional position, flags, width, precision, length modifier, conversion.
FORMAT = re.compile(r'%%|%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|ll|h|l|q|z|t|j)?([@diuoxXfFeEgGaAcCsSp])')
# Strings every user meets early; a language is not shipped until these are translated.
CORE_TRANSLATIONS = {
    'Record Shortcut',
    'Save changes to the skhd configuration?',
    'The command is empty.',
    'Choose the skhd configuration file to edit. It is usually ~/.config/skhd/skhdrc.',
    'Trial ended',
    'No Keymin Pro purchase was found for this Apple Account.',
    'The Source page needs Keymin Pro',
}


# strings_values(path): Parse a .strings file through plutil and return its key/value dictionary.
def strings_values(path):
    result = subprocess.run(
        ['plutil', '-convert', 'json', '-o', '-', str(path)],
        capture_output=True, check=True,
    )
    return json.loads(result.stdout)


# formats(text): Return the (position, conversion) pairs of a format string so a translation can be
# compared with its English source.
def formats(text):
    result = []
    for match in FORMAT.finditer(text):
        # A doubled percent sign is a literal, not an argument.
        if match.group(0) != '%%':
            result.append(((int(match.group(1)) if match.group(1) else None), (match.group(2) or '') + match.group(3)))
    return result


# fail(message): Print a failure and return False so callers can fold it into ok with &=.
def fail(message):
    print(f'FAIL: {message}')
    return False


# main(): Run every catalog check and return the process exit code.
def main():
    ok = True
    # Both build systems must embed the catalog, or localized() would return bare keys at runtime.
    project = (ROOT / 'Keymin.xcodeproj/project.pbxproj').read_text(encoding='utf-8')
    package = (ROOT / 'Package.swift').read_text(encoding='utf-8')
    # Xcode must include the catalog in the resources phase.
    if 'Localizable.strings in Resources' not in project:
        ok &= fail('Xcode does not embed the localization variant group')
    # SwiftPM uses a generated resource bundle instead of the Xcode resource phase.
    if '.process("Resources")' not in package:
        ok &= fail('Swift Package resources are not processed for localization lookup')
    for language in LANGUAGES:
        expected_path = f'Sources/KeyminApp/Resources/{language}.lproj/Localizable.strings'
        # Each language's catalog must be referenced by the Xcode project.
        if expected_path not in project:
            ok &= fail(f'Xcode is missing {expected_path}')

    folders = sorted(path.parent.name.removesuffix('.lproj') for path in RESOURCES.glob('*.lproj/Localizable.strings'))
    # The .lproj folders on disk must match the declared language list exactly.
    if sorted(LANGUAGES) != folders:
        ok &= fail(f'language folders differ: expected {sorted(LANGUAGES)}, found {folders}')

    english_path = RESOURCES / 'en.lproj/Localizable.strings'
    # English is the reference catalog; without it nothing else can be compared.
    if not english_path.exists():
        return 1 if not fail('English localization is missing') else 0
    english = strings_values(english_path)
    expected = set(english)
    # A much smaller catalog means the key scan or the catalog generator broke.
    if len(expected) < 150:
        ok &= fail(f'English catalog is unexpectedly small ({len(expected)} keys)')

    # The catalog and the source scan must match in both directions.
    keys = source_keys()
    missing_source = keys - expected
    # A key without an entry would show in the app as untranslated text.
    if missing_source:
        ok &= fail('localized() source keys missing from English: ' + ', '.join(sorted(missing_source)[:8]))
    stale = expected - keys
    # Leftover entries waste translators' effort.
    if stale:
        ok &= fail('English keys no longer used by the source: ' + ', '.join(sorted(stale)[:8]))
    untranslatable = sorted(key for key in expected if english[key] != key)
    # English values double as keys, so a differing value would hide the real source text.
    if untranslatable:
        ok &= fail('English values must equal their keys: ' + ', '.join(untranslatable[:8]))
    # The core strings must exist in the reference before coverage can be judged.
    if not CORE_TRANSLATIONS <= expected:
        ok &= fail('core UI text is missing from the catalog: ' + ', '.join(sorted(CORE_TRANSLATIONS - expected)))

    # Compare each language with English for key coverage and format-argument safety.
    for language in LANGUAGES:
        localizable = RESOURCES / f'{language}.lproj/Localizable.strings'
        values = strings_values(localizable)
        # Every language carries the same key set, no more and no less.
        if set(values) != expected:
            missing, extra = expected - set(values), set(values) - expected
            ok &= fail(f'{language}: {len(missing)} missing and {len(extra)} unexpected keys')
        mismatched = [key for key in expected & set(values) if formats(key) != formats(values[key])]
        # Different format arguments can produce incorrect text or crash formatting.
        if mismatched:
            ok &= fail(f'{language}: incompatible format arguments: {", ".join(sorted(mismatched)[:8])}')
        # Translation coverage applies to every language except the reference.
        if language != 'en':
            # Count only present translations because missing keys are reported above.
            changed = sum(key in values and values[key] != english[key] for key in expected)
            # Less than half translated is not ready to ship.
            if changed < len(expected) // 2:
                ok &= fail(f'{language}: only {changed}/{len(expected)} strings are translated')
            untranslated_core = sorted(key for key in CORE_TRANSLATIONS if values.get(key) == english.get(key))
            # The core strings must be real translations, not English copies.
            if untranslated_core:
                ok &= fail(f'{language}: core UI text is untranslated: {", ".join(untranslated_core)}')
        print(f'{language}: {len(values)} strings')

    print(f'{len(LANGUAGES)} languages; {len(expected)} strings per language')
    return 0 if ok else 1


# Run the checks as a command and exit with their result.
if __name__ == '__main__':
    sys.exit(main())
