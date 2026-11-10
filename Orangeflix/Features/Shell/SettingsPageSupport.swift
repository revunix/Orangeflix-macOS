import AppKit
import SwiftUI

/// The privacy policy and the terms, as published on orangeflix.de.
enum SettingsLegal {
    static let privacy = URL(string: "https://orangeflix.de/datenschutz")!
    static let terms = URL(string: "https://orangeflix.de/agb")!
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

/// Hides the system-blue selection of the sidebar table. The rows paint the
/// theme accent themselves; the selection stays, so the arrow keys still
/// move it.
struct SidebarSelectionChrome: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { Probe() }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? Probe)?.clearSelectionHighlight()
    }

    final class Probe: NSView {
        /// The chrome sits in the row only to reach the table. Clicks belong
        /// to the row.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func layout() {
            super.layout()
            clearSelectionHighlight()
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            clearSelectionHighlight()
        }

        /// The sidebar's own table. Walking from this row stays inside that
        /// scroll view, so the form — another table — keeps its highlight.
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
