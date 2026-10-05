import AppKit
import SwiftUI

/// The shared page layout: an icon, a title, and a summary above the page's own content.
private struct PageFrame<Content: View>: View {
    let symbol: String
    let title: String
    let summary: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Icon, title and summary, then the page's own content below.
                HStack(spacing: 18) {
                    IconTile(symbol: symbol, size: 60)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(localized(title))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(localized(summary))
                            .font(.system(size: 15))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                content()
            }
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 40)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .top)
        }
    }
}

/// The reason a typed name or path was refused, in red under its field.
private struct FieldProblem: View {
    let message: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.circle.fill")
            Text(message)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.danger)
    }
}
