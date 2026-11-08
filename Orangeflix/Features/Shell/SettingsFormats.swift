import SwiftUI

/// Which formats the list in the settings shows.
enum SettingsFormatFilter: String, CaseIterable, Identifiable, Hashable {
    case all, visible, hidden, notified

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .visible: "Sichtbar"
        case .hidden: "Ausgeblendet"
        case .notified: "Gemeldet"
        }
    }
}

/// The search field and the filter above the format list.
struct SettingsFormatSearch: View {
    @Binding var query: String
    @Binding var filter: SettingsFormatFilter
    let counts: [SettingsFormatFilter: Int]

    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            HStack(spacing: Space.s) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Formate suchen", text: $query, prompt: Text("Formate suchen"))
                    .textFieldStyle(.plain)
                    .labelsHidden()
                    .focused($focused)
                    .onExitCommand { query = "" }
                if !query.isEmpty {
                    Button {
                        query = ""
                        focused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Suche leeren")
                    .accessibilityLabel("Suche leeren")
                }
            }
            .padding(.horizontal, Space.s)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: Radius.s, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .strokeBorder(focused ? Palette.accent.opacity(0.7) : .clear, lineWidth: 1.5)
            }
            .animation(.easeOut(duration: 0.15), value: focused)

            // Capsules that wrap instead of a segmented control, which
            // cannot shrink and pushed the whole page wider than the window.
            FlowLayout(spacing: Space.xs) {
                ForEach(SettingsFormatFilter.allCases) { item in
                    filterChip(item)
                }
            }
        }
        .padding(.vertical, 2)
    }
}

extension SettingsFormatSearch {
    fileprivate func filterChip(_ item: SettingsFormatFilter) -> some View {
        let chosen = filter == item
        return Button {
            withAnimation(.snappy(duration: 0.18)) { filter = item }
        } label: {
            HStack(spacing: 4) {
                Text(item.title)
                Text("\(counts[item] ?? 0)")
                    .monospacedDigit()
                    .foregroundStyle(chosen ? Palette.accentText.opacity(0.75) : Color.secondary.opacity(0.7))
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(chosen ? Palette.accentText : Color.primary)
            .padding(.horizontal, Space.s)
            .frame(height: 24)
            .background(Capsule().fill(chosen ? Palette.accentSoft : Color.primary.opacity(0.05)))
            .overlay(Capsule().strokeBorder(chosen ? Palette.accent.opacity(0.4) : Color.primary.opacity(0.1)))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }
}

/// One format: the cover, the name, its state, and the two switches.
struct SettingsFormatRow: View {
    let format: Format
    @Binding var visible: Bool
    @Binding var notify: Bool
    /// The main switch of the notifications; off mutes every format.
    let notificationsOn: Bool

    var body: some View {
        HStack(spacing: Space.m) {
            FormatCover(format: format)
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .opacity(visible ? 1 : 0.45)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(format.title)
                        .foregroundStyle(visible ? .primary : .secondary)
                        .lineLimit(1)
                    if format.newEpisode {
                        Text("Neu")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Palette.accent, in: Capsule())
                    }
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(-1)
            SettingsFormatChip(
                title: "Mediathek",
                symbol: visible ? "eye" : "eye.slash",
                on: visible,
                help: visible ? "In der Mediathek ausblenden" : "In der Mediathek anzeigen"
            ) { visible.toggle() }
            SettingsFormatChip(
                title: "Melden",
                symbol: notify && notificationsOn ? "bell.fill" : "bell.slash",
                on: notify && notificationsOn,
                help: !visible ? "Ausgeblendete Formate werden nicht gemeldet"
                    : notify ? "Nicht mehr melden" : "Neue Folgen melden"
            ) { notify.toggle() }
            .disabled(!visible)
            .searchAnchor("formats.notify.\(format.pid)")
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .searchAnchor("formats.visible.\(format.pid)")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(format.title)
    }

    /// "aktiv · 420 Folgen · Letzte Folge 05.11.2026"
    private var detail: String {
        var parts: [String] = []
        let status = format.status.label
        if !status.isEmpty { parts.append(status.prefix(1).uppercased() + status.dropFirst()) }
        if format.clipCount > 0 { parts.append(format.clipCount == 1 ? "1 Folge" : "\(format.clipCount) Folgen") }
        if !format.lastEpisode.isEmpty { parts.append("Letzte Folge \(format.lastEpisode)") }
        return parts.joined(separator: " · ")
    }
}

/// A small switch as a capsule: the accent when on, a quiet outline when off.
private struct SettingsFormatChip: View {
    let title: String
    let symbol: String
    let on: Bool
    let help: String
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .font(.caption.weight(.medium))
                .foregroundStyle(on ? Palette.accentText : Color.secondary)
                .padding(.horizontal, Space.s)
                .frame(height: 24)
                .background {
                    Capsule().fill(on ? Palette.accentSoft : Color.primary.opacity(hovering ? 0.08 : 0.04))
                }
                .overlay {
                    Capsule().strokeBorder(on ? Palette.accent.opacity(0.35) : Color.primary.opacity(0.12))
                }
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .opacity(isEnabled ? 1 : 0.4)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: on)
        .help(help)
        .accessibilityLabel(title)
        .accessibilityValue(on ? "an" : "aus")
        .accessibilityAddTraits(.isToggle)
    }
}
