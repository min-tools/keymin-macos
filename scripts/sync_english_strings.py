#!/usr/bin/env python3
"""Regenerate the English catalog from the source so every runtime key has an entry."""
from pathlib import Path

from localization_keys import ROOT, source_keys

CATALOG = ROOT / 'Sources/KeyminApp/Resources/en.lproj/Localizable.strings'


# escape(text): Quote a key or value for the .strings file format.
def escape(text):
    return text.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n')


# render(keys): Produce the catalog text with one commented entry per key, in case-insensitive order.
def render(keys):
    lines = ['/* Keymin — en localization. Each comment shows the English source text. */', '']
    for key in sorted(keys, key=lambda value: (value.casefold(), value)):
        # A key containing */ would end its comment early, and newlines would break the layout.
        comment = key.replace('*/', '* /').replace('\n', ' ')
        lines += [f'/* {comment} */', f'"{escape(key)}" = "{escape(key)}";', '']
    return '\n'.join(lines).rstrip('\n') + '\n'


# Rewrite the English catalog from the current sources when run as a command.
if __name__ == '__main__':
    keys = source_keys()
    CATALOG.parent.mkdir(parents=True, exist_ok=True)
    CATALOG.write_text(render(keys), encoding='utf-8')
    print(f'{len(keys)} English strings written to {CATALOG.relative_to(ROOT)}')
