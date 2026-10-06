import AppKit
import SwiftUI

/// Shows detected skhd status, with start or installation help when needed.
/// File and process checks are best effort within the sandbox.
struct SkhdRequirementCard: View {
    /// Nil until the first look has finished.
    let presence: SkhdPresence?
    /// Called by Check Again; the owner scans again and passes in a new presence.
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The status row is always there; the section below depends on what was found.
            statusRow
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
            switch presence?.status {
            case .installed:
                Divider()
                startSection
                    .padding(18)
            case .missing:
                Divider()
                installSection
                    .padding(18)
            case .running, nil:
                EmptyView()
            }
        }
        .frame(maxWidth: 720)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }

    private var statusRow: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(Theme.color(for: tone))
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(explanation)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                // The program that was found, so the user can tell which install Keymin saw.
                if let path = presence?.programPath {
                    Text(path)
                        .font(Theme.mono(11.5))
                        .foregroundStyle(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer(minLength: 12)
            Button(localized("Check Again"), action: onRefresh)
                .buttonStyle(.keymin(.secondary, size: .small))
                .keyboardFocusable()
                .help(localized("Look for skhd again"))
        }
    }

    /// A start command to try when installation files exist but no process is found.
    private var startSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(localized("Run this in Terminal, then check again:"))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            CommandChip(command: "skhd --start-service", purpose: localized("Copy the command that starts skhd"))
                .frame(maxWidth: 320)
            Text(localized("Keymin does not include, start, or control skhd."))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
        }
    }

    /// Nothing was found: the two projects, side by side, as an either/or choice.
    private var installSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Pick one. Both read the same configuration file."))
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.textSecondary)
            HStack(alignment: .top, spacing: 12) {
                SkhdProjectTile(
                    name: "skhd",
                    summary: localized("The original hotkey daemon, written in C and maintained by Åsmund Vikane."),
                    command: "brew install asmvik/formulae/skhd",
                    link: AppLinks.skhd
                )
                OrDivider()
                SkhdProjectTile(
                    name: "skhd.zig",
                    summary: localized("A compatible hotkey daemon written in Zig by Jackie Li."),
                    command: "brew install jackielii/tap/skhd-zig",
                    link: AppLinks.skhdZig
                )
            }
            .fixedSize(horizontal: false, vertical: true)
            Text(localized("After installing, run skhd --start-service once. Keymin does not include, start, or control skhd."))
                .font(.system(size: 11.5))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var tone: Tone {
        switch presence?.status {
        case .running: return .positive
        case .installed, .missing: return .warning
        case nil: return .neutral
        }
    }

    private var symbol: String {
        switch presence?.status {
        case .running: return "checkmark.circle.fill"
        case .installed: return "pause.circle.fill"
        case .missing: return "exclamationmark.triangle.fill"
        case nil: return "magnifyingglass.circle.fill"
        }
    }

    private var headline: String {
        switch presence?.status {
        case .running: return localized("skhd is running on this Mac")
        case .installed: return localized("skhd was found, but no running process was detected")
        case .missing: return localized("skhd was not found on this Mac")
        case nil: return localized("Looking for skhd")
        }
    }

    private var explanation: String {
        switch presence?.status {
        case .running: return localized("With hot loading enabled, skhd applies saved changes automatically.")
        case .installed: return localized("Start skhd to use your hotkeys, then check again.")
        case .missing: return localized("Install one of the projects below and start it. You can prepare the configuration in the meantime.")
        case nil: return localized("Checking installation paths and running processes.")
        }
    }
}

/// One of the two daemons: name, a short description, its Homebrew command, and its GitHub page.
private struct SkhdProjectTile: View {
    let name: String
    let summary: String
    let command: String
    let link: URL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer(minLength: 8)
                // Opens the project's GitHub page in the browser.
                Button {
                    NSWorkspace.shared.open(link)
                } label: {
                    HStack(spacing: 3) {
                        Text(localized("GitHub"))
                        Image(systemName: "arrow.up.forward")
                            .font(.system(size: 9, weight: .bold))
                    }
                }
                .buttonStyle(.keymin(.link, size: .small))
                .keyboardFocusable()
                .help(localizedFormat("Open the %@ project on GitHub", name))
                .accessibilityLabel(localizedFormat("Open the %@ project on GitHub", name))
            }
            Text(summary)
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            CommandChip(command: command, purpose: localizedFormat("Copy the install command for %@", name))
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.border, lineWidth: 1))
        .accessibilityElement(children: .contain)
    }
}

/// A thin vertical rule with "or" in the middle, between the two project tiles.
private struct OrDivider: View {
    var body: some View {
        VStack(spacing: 6) {
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
            Text(localized("or"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.textTertiary)
            Rectangle()
                .fill(Theme.border)
                .frame(width: 1)
                .frame(maxHeight: .infinity)
        }
        .frame(width: 24)
        .accessibilityHidden(true)
    }
}

/// A command in monospace with a copy button that confirms for a moment.
private struct CommandChip: View {
    let command: String
    /// What the copy button does, for VoiceOver.
    let purpose: String
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Text(command)
                .font(Theme.mono(11))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .textSelection(.enabled)
                .padding(.leading, 10)
            Spacer(minLength: 0)
            Button(action: copy) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(copied ? Theme.success : Theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bare)
            .keyboardFocusable()
            .help(copied ? localized("Copied") : localized("Copy"))
            .accessibilityLabel(purpose)
        }
        .frame(height: 30)
        .background(Theme.surfaceSunken, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).stroke(Theme.border, lineWidth: 1))
    }

    // copy(): Put the command on the pasteboard and show the check mark for 1.5 seconds.
    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.easeIn(duration: 0.2)) { copied = false }
        }
    }
}

/// How the first screen looks for skhd. The default scans this Mac; tests and previews supply a
/// fixed answer instead so they never touch the file system or the process list.
private struct SkhdPresenceScannerKey: EnvironmentKey {
    static let defaultValue: () -> SkhdPresence = SkhdPresence.scan
}

extension EnvironmentValues {
    /// The scanner the welcome screen calls; tests and previews replace it with a fixed answer.
    var skhdPresenceScanner: () -> SkhdPresence {
        get { self[SkhdPresenceScannerKey.self] }
        set { self[SkhdPresenceScannerKey.self] = newValue }
    }
}
