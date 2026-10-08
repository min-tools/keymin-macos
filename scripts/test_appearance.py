#!/usr/bin/env python3
"""Keep the app adaptive with semantic text and explicit Light/Dark brand surfaces."""

from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parent.parent
# Scan every source for forced appearances, and the theme and the two banner views for required tokens.
sources = '\n'.join(path.read_text(encoding='utf-8') for path in (ROOT / 'Sources/KeyminApp').glob('*.swift'))
theme = (ROOT / 'Sources/KeyminApp/Theme.swift').read_text(encoding='utf-8')
root_view = (ROOT / 'Sources/KeyminApp/RootView.swift').read_text(encoding='utf-8')
banner = (ROOT / 'Sources/KeyminApp/AccessBanner.swift').read_text(encoding='utf-8')

for forbidden in ('.preferredColorScheme(.dark)', 'NSAppearance(named: .darkAqua)', 'window.appearance ='):
    # A forced appearance would override the user's system setting.
    if forbidden in sources:
        print(f'FAIL: forced appearance remains: {forbidden}')
        sys.exit(1)

# Semantic AppKit colors follow the system appearance, including increased contrast, on their own.
required = (
    '.windowBackgroundColor', '.controlBackgroundColor', '.textBackgroundColor',
    '.labelColor', '.secondaryLabelColor', '.tertiaryLabelColor',
    '.separatorColor', '.controlAccentColor', '.alternateSelectedControlTextColor',
)
missing = [token for token in required if token not in theme]
# A missing token needs review; this text check cannot establish the rendered color.
if missing:
    print('FAIL: missing semantic theme tokens: ' + ', '.join(missing))
    sys.exit(1)

# Brand surfaces need Light/Dark pairs, also selected for high-contrast appearances.
adaptive_tokens = (
    'NSColor(name: nil)', '.accessibilityHighContrastDarkAqua',
    'static let sidebarBackground = adaptive(', 'static let badgeActiveBackground = adaptive(',
    'static let segmentSelected = adaptive(', 'static let labelText = adaptive(',
    'static let inputBackground = adaptive(', 'static let inputBorder = adaptive(',
    'static let inputPlaceholderNSColor = adaptiveNSColor(', 'static let keyCapTop = adaptive(',
)
missing = [token for token in adaptive_tokens if token not in theme]
# Report every missing palette entry at once.
if missing:
    print('FAIL: missing adaptive palette tokens: ' + ', '.join(missing))
    sys.exit(1)

# Declaring the sidebar token is not enough; the sidebar must actually draw with it.
if '.background(Theme.sidebarBackground)' not in sources:
    print('FAIL: sidebar does not use its adaptive background')
    sys.exit(1)

# The main window keeps the standard title bar instead of a custom full-size content layout.
standard_titlebar = (
    '.windowStyle(.titleBar)',
    'window.styleMask.remove(.fullSizeContentView)',
    'window.titleVisibility = .visible',
    'window.titlebarAppearsTransparent = false',
    'window.titlebarSeparatorStyle = .line',
)
missing = [token for token in standard_titlebar if token not in sources]
# Each setting undoes part of the full-size style; all of them are needed.
if missing:
    print('FAIL: main window no longer uses the standard title bar: ' + ', '.join(missing))
    sys.exit(1)

# The external-change banner in RootView uses the system orange tint so it adapts to dark mode.
if 'Color(nsColor: .systemOrange).opacity(0.16)' not in root_view:
    print('FAIL: the external-change banner no longer uses the semantic amber tint')
    sys.exit(1)
# Its two actions are bordered buttons with the tint cleared, so neither looks like a default action.
if root_view.count('.buttonStyle(.bordered)') < 2 or '.tint(nil)' not in root_view:
    print('FAIL: the banner actions must use the same neutral native style')
    sys.exit(1)

# The restricted-access banner shares the same tint...
if 'Color(nsColor: .systemOrange).opacity(0.16)' not in banner:
    print('FAIL: the restricted-access banner no longer uses the semantic amber tint')
    sys.exit(1)
# ...and the same neutral button style for its purchase and restore actions.
if banner.count('.buttonStyle(.bordered)') < 2 or '.tint(nil)' not in banner:
    print('FAIL: purchase and restore must use the same neutral native style')
    sys.exit(1)

print('Adaptive light/dark appearance and semantic macOS colors verified.')
