import SwiftUI

/// The header of a screen: the title in the display size. The window chrome
/// carries search and actions; here the name of the screen stays.
struct BrandHeader: View {
    let title: String
    var subtitle: String?
    /// A small line under the subtitle (the filter, the hint).
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Space.l)
        .padding(.top, Space.m)
        .padding(.bottom, Space.s)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(Palette.divider)
                .frame(height: 1)
        }
    }
}

/// The wordmark of the app: the iris and the name beside it.
struct BrandWordmark: View {
    /// How far the iris is closed (0…1).
    var closed: Double
    var size: CGFloat = 26

    var body: some View {
        HStack(spacing: Space.s) {
            IrisBrandMark(closed: closed, size: size)
            Text("orangeflix")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Palette.textPrimary)
        }
    }
}
