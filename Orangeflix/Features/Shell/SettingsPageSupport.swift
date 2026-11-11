import AppKit
import SwiftUI

/// The privacy policy and the terms, as published on orangeflix.de.
enum SettingsLegal {
    static let privacy = URL(string: "https://orangeflix.de/datenschutz")!
    static let terms = URL(string: "https://orangeflix.de/agb")!
}

/// Sub-tabs inside the unified Konto & Profil settings pane.
enum AccountSubTab: String, CaseIterable, Identifiable, Hashable {
    case overview
    case details
    case sharing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Übersicht"
        case .details: "Angaben & Feed"
        case .sharing: "Sharing-Links"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "person.crop.circle"
        case .details: "slider.horizontal.3"
        case .sharing: "link"
        }
    }
}

/// A delete that is only carried out after the confirmation.
enum SettingsDelete: Identifiable {
    case address
    case birthday
    case credits
    case feedFilter
    /// The code of the sharing link.
    case sharingLink(String)
    /// The id of the push device.
    case pushDevice(String)
    /// The id of an imported theme.
    case theme(String)

    var id: String {
        switch self {
        case .address: "address"
        case .birthday: "birthday"
        case .credits: "credits"
        case .feedFilter: "filter"
        case .sharingLink(let code): "link-\(code)"
        case .pushDevice(let device): "device-\(device)"
        case .theme(let theme): "theme-\(theme)"
        }
    }
}

/// Number formats shared by the settings pages.
enum SettingsFieldFormat {
    static let german = Locale(identifier: "de_DE")
    static let delay: FloatingPointFormatStyle<Double> =
        .number.precision(.fractionLength(0...2)).locale(german)
    static let limit: IntegerFormatStyle<Int> = .number.locale(german)

    static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }
}

/// Writes a setting and shows the validation error of the store.
@MainActor
enum SettingsWrite {
    static func apply(_ app: AppModel, _ settingsError: Binding<String?>, _ change: (inout AppSettings) -> Void) {
        do {
            try app.updateSettings(change)
            settingsError.wrappedValue = nil
        } catch {
            settingsError.wrappedValue = error.localizedDescription
            app.show(error)
        }
    }
}

/// Open and save panels as a sheet of the settings window.
@MainActor
enum SettingsPanels {
    /// Shows an open or save panel as a sheet of this window.
    static func present(_ panel: NSSavePanel, handle: @escaping (URL) -> Void) {
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in handle(url) }
        }
        if let window = NSApp.keyWindow ?? NSApp.mainWindow {
            panel.beginSheetModal(for: window, completionHandler: finish)
        } else {
            panel.begin(completionHandler: finish)
        }
    }

    /// Lets the user pick a file and hands it on with access to it.
    static func chooseFile(prompt: String, then handle: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = prompt
        present(panel) { url in
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            handle(url)
        }
    }

    /// Lets the user pick where a file goes. The security scope stays for
    /// the whole write, which finishes after the panel has closed.
    static func chooseTarget(
        name: String,
        write: @escaping (URL) async throws -> String,
        report: @escaping (String) -> Void,
        fail: @escaping (any Error) -> Void
    ) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        panel.prompt = "Exportieren"
        present(panel) { url in
            Task {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    report(try await write(url))
                } catch {
                    fail(error)
                }
            }
        }
    }
}

/// Hides the system-blue selection of the sidebar table. The rows paint their
/// own quiet capsule highlight; the table selection stays so arrow keys work.
struct SidebarSelectionChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Probe)?.clearSelectionHighlight()
    }

    final class Probe: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            clearSelectionHighlight()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearSelectionHighlight()
        }

        func clearSelectionHighlight() {
            guard let table = enclosingScrollView?.documentView as? NSTableView else { return }
            if table.selectionHighlightStyle != .none {
                table.selectionHighlightStyle = .none
            }
            if table.focusRingType != .none {
                table.focusRingType = .none
            }
        }
    }
}

// MARK: - Studio Settings Building Blocks

/// A macOS System-Settings-style squircle icon badge with top-down gradient and subtle inner rim.
struct SettingsSquircleBadge: View {
    let symbol: String
    let top: Color
    let bottom: Color
    var size: CGFloat = 22
    var symbolSize: CGFloat = 11.5

    var body: some View {
        let radius = (size * 0.27).rounded(.toNearestOrEven)
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            shape.fill(
                LinearGradient(colors: [top, bottom], startPoint: .top, endPoint: .bottom)
            )
            shape.strokeBorder(
                LinearGradient(
                    colors: [.white.opacity(0.32), .white.opacity(0.06)],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.75
            )
            Image(systemName: symbol)
                .font(.system(size: symbolSize, weight: .semibold))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.16), radius: 1, y: 0.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A themed card section on a settings page with optional title, trailing header content and footer note.
struct SettingsSection<Trailing: View, Content: View>: View {
    var title: String?
    var subtitle: String?
    var footer: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content

    init(
        _ title: String? = nil,
        subtitle: String? = nil,
        footer: String? = nil,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() },
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.footer = footer
        self.trailing = trailing()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if title != nil || !(Trailing.self == EmptyView.self) {
                HStack(alignment: .center, spacing: Space.s) {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title {
                            SectionLabel(text: title)
                        }
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(AppFont.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    Spacer(minLength: Space.s)
                    trailing
                }
                .padding(.horizontal, 2)
            }

            VStack(alignment: .leading, spacing: Space.m) {
                content
            }
            .padding(Space.l)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentCard()

            if let footer, !footer.isEmpty {
                Text(footer)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }
}

/// A horizontal row inside a `SettingsSection` with title, optional hint and trailing control.
struct SettingsRow<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .center, spacing: Space.m) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.body)
                    .foregroundStyle(Palette.textPrimary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: Space.m)
            trailing
        }
    }
}

/// A switch row inside a `SettingsSection`.
struct SettingsToggleRow: View {
    let title: String
    var subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title, subtitle: subtitle) {
            Toggle(title, isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
        }
    }
}

/// A capsule segmented control matching Orangeflix's accent & glass tokens.
struct SettingsSegmentedTabs<Option: Hashable & Identifiable>: View {
    let options: [Option]
    @Binding var selection: Option
    var title: (Option) -> String
    var symbol: ((Option) -> String?)? = nil
    var badgeDot: ((Option) -> Bool)? = nil

    var body: some View {
        HStack(spacing: 3) {
            ForEach(options) { option in
                let chosen = selection == option
                Button {
                    withAnimation(.snappy(duration: 0.18)) { selection = option }
                } label: {
                    HStack(spacing: 5) {
                        if let icon = symbol?(option) {
                            Image(systemName: icon)
                                .font(.system(size: 11, weight: .semibold))
                        }
                        Text(title(option))
                        if badgeDot?(option) == true {
                            Circle()
                                .fill(Palette.accent)
                                .frame(width: 6, height: 6)
                        }
                    }
                    .font(AppFont.captionMedium)
                    .foregroundStyle(chosen ? Palette.accentText : Palette.textSecondary)
                    .padding(.horizontal, Space.m)
                    .frame(height: 26)
                    .background {
                        if chosen {
                            Capsule()
                                .fill(Palette.accentSoft)
                                .overlay {
                                    Capsule().strokeBorder(Palette.accent.opacity(0.42), lineWidth: 1)
                                }
                        }
                    }
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(chosen ? .isSelected : [])
            }
        }
        .padding(3)
        .background(Palette.surfaceMuted, in: Capsule())
        .overlay {
            Capsule().strokeBorder(Palette.divider, lineWidth: 1)
        }
    }
}
