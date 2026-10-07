# Architecture

Source and App Store builds compile the same Swift files and use the same product identity.

| Concern | Source build | App Store build |
| --- | --- | --- |
| Bundle identifier | `tools.min.keymin` | `tools.min.keymin` |
| Trial clock | Local start date | Apple's verified original acquisition date in production; local start date in verified StoreKit test environments |
| Access | 30 days of Pro, then Free or verified Pro access | The same |
| StoreKit verification | Enabled | Enabled |
| Amber access banner | Hidden during startup and the trial; shown afterward without Pro | The same |
| Build configuration | Debug or Release | AppStore |
| Edition flag | None | `KEYMIN_APP_STORE` |
| Configuration access | User-selected file and security-scoped bookmarks | The same |

## Builds and Pro access

`KEYMIN_APP_STORE` marks App Store builds. A compile-time check excludes the private local override from them. Debug, Release, Swift Package Manager, and App Store builds share StoreKit verification, the Free limit, and the access banner. Swift Package Manager uses `Bundle.module` for resources; other builds use `Bundle.main`.

`KeyminProStore` verifies purchases and selects the trial clock. The first-launch notice and initial trial lookup finish before the access banner can appear.

Without Pro after the trial, `AppModel.editableHotkeys` exposes only the first five bindings. Adding or duplicating beyond that limit opens the Pro panel. The Source page is locked because it exposes the whole file. Modes, the blacklist, included files, and After Saving remain editable.

Hidden bindings stay in `SkhdDocument` and are kept when saving. Renaming a mode updates all references, including those in hidden bindings. Existing errors in hidden bindings and unparsed lines do not block a Free save. Errors introduced by later edits still do, such as removing a mode used by a hidden binding. `AppModel` records existing errors at load and save, matching each by its message and statement text.

If the Free limit takes effect with an unapplied Source draft, that draft is ignored. Keymin does not apply it or ask to save it. The next document change or save drops it.

## File access and saving

Keymin runs in the App Sandbox with user-selected file access and app-scoped bookmarks. It edits the configuration chosen in an Open or Save panel and stores its bookmark in the app container. It also reads app metadata for the app picker and binding icons.

`ConfigStore` follows symbolic links one hop at a time. If the sandbox blocks the target, the interface asks for access and stores a second bookmark. A save that lacks the required access reports an error.

Saving first writes a hidden temporary file beside the target, then replaces the target through `FileManager.replaceItemAt`. This preserves the target's permissions and the symbolic link. If that attempt fails, for example because a file-only grant prevents creating the temporary file, Keymin tries an in-place write through the chosen path. This fallback is not atomic.

A `DispatchSource` watches for external edits. Keymin reloads automatically when there is no unsaved work; otherwise, a banner offers a choice.

Before quitting, opening or creating another file, or forgetting file access, Keymin asks what to do with unsaved changes. These include any editable Source draft. Save is offered only when there are no blocking errors, and a failed save cancels the requested action. Revert to Saved and Reload From Disk also ask before discarding work.

The document is dirty when its serialized text differs from the serialized text at the last load or save. Formatting cleanup alone, such as dropping extra blank lines at the end, therefore does not mark a newly opened file as changed.

Line-ending carriage returns are an exception. skhd would pass them to the shell as part of a command, so Keymin marks the file as changed and saves it with `\n` endings. Carriage returns elsewhere, including escaped ones, are preserved. A leading byte order mark is also preserved so the parser can report it as an error.

## skhd and Shortcuts

The welcome screen checks for skhd installation files and a running process. `SkhdPresence` checks file metadata at common installation paths, on the app's PATH, and at known launch-agent paths. It reads process names through `sysctl`. These checks are best effort: sandbox restrictions may hide files or prevent a process query. They read no file contents and store no results.

Keymin never executes configuration commands, spawns a process, or signals skhd. With hot loading enabled, skhd watches its configuration and reloads saved changes itself.

The optional After Saving action opens a `shortcuts://run-shortcut` URL after a successful save. Shortcuts runs the named shortcut with its own permissions, outside Keymin's sandbox, and receives the saved file's path. Keymin can confirm that macOS opened the URL, but cannot check the shortcut's result.

## Interface

Menus use SwiftUI commands because SwiftUI rebuilds menus when focus changes and can drop items inserted through AppKit. Command groups observe the model to keep enabled states and View menu checkmarks current.

The Source page edits a draft. Apply, Save, leaving the page, or another document edit applies it first, so later changes build on that text. When there is no unapplied text, the draft follows document changes. Discard Edits drops an unapplied draft. The Free-limit exception is described above.

The minimum window size is 1010 by 520 points. `WindowFrameMemory` centers the first-run screen at 1180 by 760 points and restores the saved editor frame when reopening a configuration. It adjusts the frame to fit the screen without going below the minimum size. If the screen is smaller than that minimum, the top-left corner and title bar remain visible.

## Parsing and writing

`SkhdTokenizer` and `SkhdParser` follow skhd's `tokenize.c` and `parse.c`: token classification, line-based commands and continuations, process lists, mode declarations, `.load`, and `.blacklist`.

Like skhd, the tokenizer treats space, tab, line feed, vertical tab, form feed, and carriage return as whitespace. Other invisible characters are errors that name the code point. Mode names must start with a letter; single letters, modifiers, and key names are classified as keys instead. Key codes require uppercase hex digits, so the error for `0x2c` suggests `0x2C`.

After an error, the parser keeps the rejected text as a raw item and continues. Later lines remain visible. Raw items block saving until corrected, usually on the Source page, except for the existing-error rule in Free.

Each statement stores its original text. The writer reuses it while the statement is unchanged and generates skhd syntax for edited statements. Statements that originally shared a line are regenerated on separate lines. If parsing any statement on that line fails, the whole line becomes one raw item.

Comments and blank lines are document items. A comment block directly above a binding supplies its name and notes. The writer trims whitespace around comments, empties whitespace-only lines, removes line-ending carriage returns, and ends the file with one newline.

### Multiline commands

Edited commands are trimmed and empty lines removed. The writer usually joins command lines with ` ; \` followed by a newline, so the shell runs them in sequence. It uses only ` \` where the next line continues shell syntax:

- a line ends with an unescaped `;`, `&`, or `|`, or the next line starts with one;
- a line ends with a shell construct that needs continuation, such as `then`, `do`, `else`, `{` at the start of a command, or `$(`.

An existing unescaped continuation backslash is retained. If the next line is blank, that line ends the command, so the writer removes both the blank line and the continuation backslash. A newline inside quotes or a here-document produces a warning because skhd cannot preserve it as entered. This formatting uses shell heuristics, not a full shell parser.

### Validation and editing

`SkhdDocument.diagnostics()` reports syntax errors that block saving, including:

- a mode used before its declaration, or a malformed or duplicate mode name;
- an empty command or a per-app list without a named app;
- a quote in an app name or `.load` path;
- an edited command ending in an unescaped backslash, which would consume the next line.

The default mode must exist before `; default` can target it. skhd creates it when it encounters an unscoped binding, a mode list naming `default`, or `:: default`. Duplicate shortcuts within a mode are warnings.

Renaming a mode updates bindings scoped to it and actions that activate it. The default mode cannot be renamed, and another mode cannot take its name. Names must be valid and unique.

`AppModel` rejects a `.load` path that points back to the current configuration. It compares the chosen path and its link target, tries relative paths from both folders, expands `~`, and follows links as far as the sandbox permits.

An include-path edit is committed with Return, Apply, or Choose. Invalid paths and mode names stay in the field with an explanation; the document keeps its previous value.

When a key changes, Keymin adjusts `fn` to match skhd's rules. skhd supplies it for named arrow, navigation, and function keys. Keymin adds it explicitly for their numeric key codes and removes it when switching back to a name or an ordinary key.

## Localization and appearance

English source strings are localization keys and fallbacks. SwiftUI and AppKit controls share `Localizable.strings` through `localized()`. `scripts/sync_english_strings.py` regenerates the catalog; tests reject missing or stale keys and unsafe format strings.

Keymin does not force an appearance. Text, status colors, separators, and accents use AppKit semantic colors. `SkhdHighlighter` uses these colors too, so syntax highlighting follows appearance changes without reparsing.

Custom surfaces, inputs, and key caps use fixed Light and Dark color pairs resolved through AppKit. They update when the system appearance changes.
