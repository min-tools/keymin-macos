# Build and test

## Public source build

```bash
python3 scripts/build.py
```

The output is `build/Keymin.app`, ad-hoc signed for local use. Source builds keep the 30-day trial, five-binding Free limit, and purchase verification. The access banner stays hidden until startup finishes and appears only without Pro after the trial. The script does not install or launch the app.

Build options:

- `--configuration Debug`: disable release optimizations and define `DEBUG`.
- `--unsigned`: skip ad-hoc signing.
- `--arch arm64`: select the only supported architecture explicitly.
- `--output /private/tmp/Keymin.app`: choose another output path, ending in `.app`.

The Xcode Debug and Release configurations build the same app:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  xcodebuild -project Keymin.xcodeproj \
  -scheme Keymin -configuration Release \
  -derivedDataPath /private/tmp/KeyminDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

The script builds in a staging directory and replaces the previous bundle only after all steps succeed.

Swift Package Manager builds (`swift build`) work too. All three build paths use Swift 5 language mode. `Package.swift` defines `KEYMIN_SWIFTPM` so resources and strings load from `Bundle.module`.

## App Store build

Use Xcode's AppStore configuration for App Review. The shared scheme selects it for archives. It defines `KEYMIN_APP_STORE` and includes dSYM crash symbols.

In production, this build counts the trial from Apple's verified original acquisition date. It permits a local trial clock only in verified StoreKit test environments. The Free limit, purchase verification, and access banner match the source build.

For compilation and packaging checks, the build script also supports the App Store flag:

```bash
python3 scripts/build.py --app-store
```

This writes `build/app-store/Keymin.app` and leaves the local bundle alone. `python3 scripts/build.py --both` builds both variants at their default paths and does not accept `--output`. Submit only a properly signed Xcode archive, never the ad-hoc bundle produced by the script.

## Source layout

| Path | Contents |
| --- | --- |
| `Keymin.xcodeproj` | The Debug, Release, and AppStore configurations and the shared scheme |
| `Sources/KeyminApp` | SwiftUI interface, skhd parser and writer, file access, and resources |
| `Sources/KeyminApp/Resources/*.lproj` | String catalogs; English is the only language so far |
| `scripts` | Build script, source export, release audit, icon and screenshot renderers, string catalog sync, and test suites |
| `scripts/fixtures` | skhd configurations for the parser tests and the README screenshots |
| `docs` | Architecture and build guidance, and the README images |

## Test

```bash
python3 scripts/test_all.py
```

The runner executes every `scripts/test_*.py` suite, two at a time by default (`--jobs`), and writes each suite's log to a fresh directory under `/private/tmp` or to the directory given with `--logs`. Together the suites:

- type-check the source and App Store variants with warnings treated as errors;
- round-trip `scripts/fixtures/sample.skhdrc` through the parser and writer, check that parsing every prefix of the fixtures finishes, and check the editing and diagnostic helpers;
- check the Source page's syntax coloring and the placement of pop-up menus;
- check link resolution and link-preserving writes on a temporary dotfiles layout;
- check how the first screen detects skhd;
- test the trial, the Free binding limit, and the entitlement decisions without StoreKit or an Apple Account;
- drive the purchase panel against a suspended StoreKit stand-in;
- validate localization coverage and format-string safety;
- check that no appearance is forced and that the theme's own colors have Light and Dark variants;
- check the app identity, privacy manifest, entitlements, privacy policy, license, staged packaging, SDK linkage, and the Xcode archive configuration.

No suite launches the app, touches a real skhd configuration, or makes a purchase.

After adding or changing text in the source, regenerate the English catalog:

```bash
python3 scripts/sync_english_strings.py
```

After changing `scripts/render_icon.swift`, regenerate the bundled icon and its README preview:

```bash
python3 scripts/make_icon.py
```

The README screenshots, `docs/images/hero-light.png` and `hero-dark.png`, use the sample configuration in `scripts/fixtures/hero.skhdrc`. The renderer draws the app's views offscreen with a title bar and shadow. Regenerate them when the pictured interface changes:

```bash
python3 scripts/render_hero.py
```

## Export source

```bash
python3 scripts/export_source.py --output /private/tmp/keymin-source
```

The export copies every file git tracks, plus untracked files git does not ignore, into a new directory. That directory must not exist yet and must be outside the checkout. Repository metadata, build output, app bundles, caches, and Xcode user data are skipped. The export stops with an error if it finds a symbolic link.
