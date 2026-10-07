# Keymin Privacy Policy

Effective and last updated: October 7, 2026

This policy explains what data Keymin handles, where it goes, and how you can control it.

Keymin edits one text file: the configuration that the skhd hotkey daemon reads. It has no advertising, analytics, tracking SDKs, account system, or developer-operated service, and it makes no network connections of its own.

## Data on your Mac

Keymin stores a macOS security-scoped bookmark for the configuration file you choose. If that path is a symbolic link and you grant access to its target, Keymin stores a second bookmark. These bookmarks stay in Keymin's app container and let it reopen the file on later launches. Keymin edits only this configuration. It also reads app names, identifiers, and icons as described below.

Before you choose a file, Keymin checks for skhd at common install locations, on the app's PATH, and in your LaunchAgents folder. It checks file metadata without reading the files' contents. It also asks macOS for running process names. These checks depend on what the sandbox allows Keymin to see. The results appear on the first screen and are not stored.

The contents of the configuration stay in memory while you edit them. Keymin writes them back only to that file, and only when you choose Save. Unsaved edits are lost if you quit without saving.

When you pick an app for a binding or the blacklist, Keymin reads the names, bundle identifiers, and icons of the running apps from macOS to offer them in a list. If you choose an app in an Open panel instead, Keymin reads only that app's name or bundle identifier. To show which app an **Open an app** binding opens, Keymin asks macOS for that app's name and icon. None of this is stored, except the name or identifier you pick, which becomes part of your configuration. When you use **Copy as Text**, or copy a command from the first screen, the text is placed on the macOS general pasteboard.

The app does not run the commands in your configuration, does not monitor your keystrokes outside its own window, and does not start, stop, or signal skhd itself.

If you turn on **After Saving → Run a shortcut after every save**, Keymin asks the Shortcuts app to run the shortcut you named, passing the path of the saved file as the shortcut's input. **Run Now** on the same page runs it right away with the current file's path. The shortcut runs under Shortcuts' own permissions, outside Keymin's sandbox, and Keymin does not learn what it did. Nothing runs until you turn the option on and name a shortcut. The option and the name are stored in the app container.

Keymin stores trial state in its app container. In production, the Mac App Store build uses Apple's verified original acquisition date for the 30-day Pro trial. Source builds and verified StoreKit test environments use a local start date. Trial information is not sent to the developer.

After the 30-day Pro trial, without a purchase, Keymin shows and edits only the first five bindings. The others stay in your configuration file and become visible again with Pro. Renaming a mode updates references in all bindings, including hidden ones. The limit does not move, delete, or upload bindings.

Apple processes Keymin Pro purchases and does not share payment details with Keymin's developer. The app reads your Apple purchase status to unlock Pro, including purchases shared through Family Sharing.

## Network requests

Keymin itself makes no network requests and has no network entitlement. StoreKit, part of macOS, communicates with Apple for product information, purchases, and purchase status. Links in the app, such as those on the first screen, in the About panel, in the Pro panel, and in this policy, open in your browser only when you click them.

## Retention and deletion

The file bookmarks remain in the app container until you pick a different file, choose **Keymin → Forget File Access…**, or remove the container. Forgetting access does not change or delete the configuration file.

The local trial start date, when used, and other preferences remain in the app container when you forget file access. Removing Keymin and its app container deletes all app-managed data. Your skhd configuration remains where it is. Apple controls the purchase records associated with your Apple Account.

## Your choices

You choose which configuration Keymin opens and when it saves. Choose **Keymin → Forget File Access…** to stop it reopening that file on later launches. During the trial or with Pro, you can review and edit the exact text on the Source page before saving.

## Changes and contact

This policy and its date will be updated when material changes occur. For privacy questions or requests, visit [Keymin support](https://min.tools/keymin/support/).
