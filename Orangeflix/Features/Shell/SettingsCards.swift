import AppKit
import SwiftUI

// MARK: - Choice cards

/// A flexible visual choice card with miniature preview and label.
struct SettingsChoiceCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let preview: Preview

    @State private var hovering = false

    init(
        title: String,
        isSelected: Bool,
        action: @escaping () -> Void,
        @ViewBuilder preview: () -> Preview
    ) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(spacing: 6) {
                preview
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                Text(title)
                    .font(AppFont.captionMedium)
                    .fontWeight(isSelected ? .semibold : .medium)
                    .foregroundStyle(isSelected ? Palette.textPrimary : Palette.textSecondary)
                    .lineLimit(1)
            }
            .padding(7)
            .frame(maxWidth: .infinity)
            .background {
                shape.fill(
                    isSelected
                        ? Palette.accentSoft
                        : Palette.surfaceMuted.opacity(hovering ? 0.95 : 0.65)
                )
            }
            .overlay {
                shape.strokeBorder(
                    isSelected ? Palette.accent : Palette.divider,
                    lineWidth: isSelected ? 1.75 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// Miniature window preview for Automatisch / Hell / Dunkel.
struct ModePreview: View {
    let theme: AppSettings.Theme

    var body: some View {
        let window = theme == .dark ? Color(hex: "1C1A17") : Color(hex: "FFFFFF")
        let sidebar = theme == .light ? Color(hex: "F1EEE7") : Color(hex: "141210")
        WindowSketch(
            window: window,
            sidebar: sidebar,
            line: theme == .dark ? Color(hex: "3A352E") : Color(hex: "E3DDD1"),
            ink: theme == .dark ? Color(hex: "A8A196") : Color(hex: "8A8376"),
            accent: Color(hex: "F19100")
        )
    }
}

/// A miniature app window for the appearance choice cards.
struct WindowSketch: View {
    var window: Color
    var sidebar: Color
    var line: Color
    var ink: Color
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3.5) {
                HStack(spacing: 2) {
                    Circle().fill(Color(hex: "FF5F57")).frame(width: 3.2, height: 3.2)
                    Circle().fill(Color(hex: "FEBC2E")).frame(width: 3.2, height: 3.2)
                    Circle().fill(Color(hex: "28C840")).frame(width: 3.2, height: 3.2)
                }
                .padding(.bottom, 1)
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == 0 ? accent.opacity(0.9) : ink.opacity(0.45))
                        .frame(width: index == 0 ? 15 : 12, height: 2.5)
                }
            }
            .padding(5)
            .frame(width: 28)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(sidebar)

            VStack(alignment: .leading, spacing: 3.5) {
                Capsule().fill(ink.opacity(0.75)).frame(width: 28, height: 3.5)
                Capsule().fill(line).frame(height: 2.5)
                Capsule().fill(line).frame(width: 34, height: 2.5)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Capsule().fill(accent).frame(width: 18, height: 5.5)
                    Capsule().fill(line).frame(width: 13, height: 5.5)
                }
            }
            .padding(6)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(window)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(line.opacity(0.9), lineWidth: 0.75)
        }
    }
}

/// Miniature window preview for Klassisch vs. Glas.
struct InterfaceStylePreview: View {
    let style: AppSettings.InterfaceStyle

    var body: some View {
        ZStack {
            if style == .glass {
                LinearGradient(
                    colors: [Color(hex: "2B2347"), Color(hex: "51365F")],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Circle()
                    .fill(Color(hex: "F19100").opacity(0.65))
                    .frame(width: 38, height: 38)
                    .blur(radius: 11)
                    .offset(x: -26, y: 14)
                Circle()
                    .fill(Color(hex: "2BC59A").opacity(0.45))
                    .frame(width: 32, height: 32)
                    .blur(radius: 11)
                    .offset(x: 28, y: -12)
            } else {
                Color(hex: "1A1917")
            }
            HStack(spacing: 4) {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == 0 ? 0.55 : 0.22))
                            .frame(width: index == 0 ? 15 : 12, height: 2.5)
                    }
                }
                .padding(5)
                .frame(width: 28)
                .frame(maxHeight: .infinity, alignment: .top)
                .background { panel(radius: 4) }

                VStack(spacing: 4) {
                    panel(radius: 4).frame(height: 17)
                    panel(radius: 4).frame(height: 11)
                }
            }
            .padding(6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(.white.opacity(style == .glass ? 0.22 : 0.09), lineWidth: 0.75)
        }
    }

    private func panel(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(
                style == .glass
                    ? AnyShapeStyle(.ultraThinMaterial)
                    : AnyShapeStyle(Color(hex: "2A2724"))
            )
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(style == .glass ? 0.28 : 0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - Theme card (Grid tile)

/// Full-width grid tile for an `AppTheme` with typography sample, accent bar,
/// palette swatches, active checkmark, and optional remove action for imported themes.
struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    var badge: String? = nil
    var onRemove: (() -> Void)? = nil
    let action: () -> Void

    @State private var hovering = false

    private func color(_ hex: String) -> Color { Color(hex: hex) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center, spacing: 6) {
                    Text("Aa")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(color(theme.colors.textPrimary))

                    if let badge {
                        Text(badge)
                            .font(.system(size: 9.5, weight: .semibold))
                            .foregroundStyle(color(theme.colors.textSecondary))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(
                                Capsule().fill(color(theme.colors.surfaceRaised))
                            )
                    }

                    Spacer(minLength: 0)

                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(color(theme.colors.accent))
                        .frame(width: 9, height: 18)
                }

                HStack(spacing: 3.5) {
                    ForEach(Array(theme.swatches.prefix(7).enumerated()), id: \.offset) { _, hex in
                        Circle()
                            .fill(color(hex))
                            .frame(width: 8, height: 8)
                    }
                    Spacer(minLength: 0)
                }

                HStack(spacing: 4) {
                    Text(theme.name)
                        .font(AppFont.captionMedium)
                        .fontWeight(isSelected ? .semibold : .medium)
                        .foregroundStyle(color(theme.colors.textPrimary))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(color(theme.colors.accent))
                    }
                }
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(shape.fill(color(theme.colors.background)))
            .overlay {
                shape.strokeBorder(
                    isSelected ? Palette.accent : color(theme.colors.border),
                    lineWidth: isSelected ? 2 : 1
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .topTrailing) {
            if let onRemove, hovering {
                Button(role: .destructive, action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.white, Color.black.opacity(0.65))
                }
                .buttonStyle(.plain)
                .padding(6)
                .help("Importiertes Theme entfernen")
            }
        }
        .onHover { hovering = $0 }
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
