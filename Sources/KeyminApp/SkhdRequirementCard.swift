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
