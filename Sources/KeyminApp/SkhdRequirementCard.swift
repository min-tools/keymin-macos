import AppKit
import SwiftUI

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
