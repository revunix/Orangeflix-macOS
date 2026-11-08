import AppKit
import SwiftUI

// MARK: - Choice cards

/// A card of a choice with a picture: the chosen one carries the accent ring
/// and a soft accent behind it, like the cards of the themes.
struct SettingsChoiceCard<Preview: View>: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    let preview: Preview

    init(title: String, isSelected: Bool, action: @escaping () -> Void,
         @ViewBuilder preview: () -> Preview) {
        self.title = title
        self.isSelected = isSelected
        self.action = action
        self.preview = preview()
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                preview
                    .padding(3)
                Text(title)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.vertical, 4)
            .background {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.tint)
                    .opacity(isSelected ? 0.14 : 0)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(.tint, lineWidth: isSelected ? 2 : 0)
            }
            .frame(width: 124)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// The color scheme as a small window; "Automatisch" keeps the light page
/// and the dark sidebar, the two fixed ones take the whole appearance.
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
            accent: Color(hex: "F19100"))
    }
}

/// A miniature app window for the cards of the appearance.
struct WindowSketch: View {
    var window: Color
    var sidebar: Color
    var line: Color
    var ink: Color
    var accent: Color

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    Circle().fill(Color(hex: "FF5F57")).frame(width: 3.5, height: 3.5)
                    Circle().fill(Color(hex: "FEBC2E")).frame(width: 3.5, height: 3.5)
                    Circle().fill(Color(hex: "28C840")).frame(width: 3.5, height: 3.5)
                }
                .padding(.bottom, 2)
                ForEach(0..<3, id: \.self) { index in
                    Capsule()
                        .fill(index == 0 ? accent.opacity(0.85) : ink.opacity(0.5))
                        .frame(width: index == 0 ? 17 : 14, height: 3)
                }
            }
            .padding(6)
            .frame(width: 36)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(sidebar)
            VStack(alignment: .leading, spacing: 4) {
                Capsule().fill(ink.opacity(0.75)).frame(width: 34, height: 4)
                Capsule().fill(line).frame(height: 3)
                Capsule().fill(line).frame(width: 48, height: 3)
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Capsule().fill(accent).frame(width: 22, height: 7)
                    Capsule().fill(line).frame(width: 16, height: 7)
                }
            }
            .padding(7)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 118, height: 70)
        .background(window)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(line.opacity(0.9), lineWidth: 0.5)
        }
    }
}

/// The interface style as a small window: solid panels in the classic one,
/// panels that show the light behind them in the glass one.
struct InterfaceStylePreview: View {
    let style: AppSettings.InterfaceStyle

    var body: some View {
        ZStack {
            if style == .glass {
                LinearGradient(colors: [Color(hex: "2B2347"), Color(hex: "51365F")],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Circle().fill(Color(hex: "F19100").opacity(0.6))
                    .frame(width: 46, height: 46)
                    .blur(radius: 14)
                    .offset(x: -36, y: 22)
                Circle().fill(Color(hex: "2BC59A").opacity(0.45))
                    .frame(width: 40, height: 40)
                    .blur(radius: 14)
                    .offset(x: 38, y: -20)
            } else {
                Color(hex: "1A1917")
            }
            HStack(spacing: 5) {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(.white.opacity(index == 0 ? 0.5 : 0.22))
                            .frame(width: index == 0 ? 18 : 14, height: 3)
                    }
                }
                .padding(6)
                .frame(width: 34)
                .frame(maxHeight: .infinity, alignment: .top)
                .background { panel(radius: 5) }
                VStack(spacing: 5) {
                    panel(radius: 4).frame(height: 22)
                    panel(radius: 4).frame(height: 14)
                }
            }
            .padding(8)
        }
        .frame(width: 118, height: 70)
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .strokeBorder(.white.opacity(style == .glass ? 0.2 : 0.08), lineWidth: 0.5)
        }
    }

    private func panel(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(style == .glass
                  ? AnyShapeStyle(.ultraThinMaterial)
                  : AnyShapeStyle(Color(hex: "2A2724")))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(.white.opacity(style == .glass ? 0.28 : 0.08), lineWidth: 0.5)
            }
    }
}

// MARK: - Theme card

/// The preview of a theme: its page, a text, a chip with the accent and the
/// dots of its palette.
struct ThemeCard: View {
    let theme: AppTheme
    let isSelected: Bool
    let action: () -> Void

    private func color(_ hex: String) -> Color { Color(hex: hex) }

    var body: some View {
        Button(action: action) {
            VStack(spacing: Space.xs) {
                preview
                    .padding(3)
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(.tint, lineWidth: isSelected ? 2 : 0)
                    }
                Text(theme.name)
                    .font(.caption)
                    .fontWeight(isSelected ? .semibold : .regular)
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .frame(width: 124)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(theme.name)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Aa")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(color(theme.colors.textPrimary))
                Spacer(minLength: 0)
                Text("~/")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color(theme.colors.textPrimary))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(color(theme.colors.surfaceRaised)))
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(color(theme.colors.accent))
                    .frame(width: 9, height: 20)
            }
            HStack(spacing: 3) {
                ForEach(Array(theme.swatches.enumerated()), id: \.offset) { _, hex in
                    Circle().fill(color(hex)).frame(width: 9, height: 9)
                }
            }
        }
        .padding(10)
        .frame(width: 118, height: 70, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(color(theme.colors.background)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(color(theme.colors.border), lineWidth: 1))
    }
}
