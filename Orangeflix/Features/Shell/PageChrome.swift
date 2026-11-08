import SwiftUI

/// The head of every screen: the back step, the title, the subtitle and the
/// actions of the page. All screens use it, so pages look the same and the
/// navigation sits in the same place everywhere.
struct PageChrome<Actions: View>: View {
    let title: String
    var subtitle: String?
    var detail: String?
    /// Shows a back button when set.
    var onBack: (() -> Void)?
    @ViewBuilder var actions: Actions

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.m) {
            if let onBack {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                        .frame(width: 28, height: 28)
                        .glassPlate(in: Circle(), interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Zurück")
                .accessibilityLabel("Zurück")
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 8 }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.display)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textTertiary)
                }
            }

            Spacer(minLength: Space.m)

            HStack(spacing: Space.xs) { actions }
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 6 }
        }
        .padding(.horizontal, Space.page)
        .padding(.top, Space.m)
        .padding(.bottom, Space.m)
    }
}
