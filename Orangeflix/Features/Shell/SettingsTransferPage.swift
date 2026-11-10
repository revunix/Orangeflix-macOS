import SwiftUI

/// Import and export: the backup of the app, the settings file of the
/// command line tool and the library. Replacing the library or the settings
/// waits for a confirmation the window itself asks for.
struct SettingsTransferPage: View {
    @Binding var transferMessage: String?
    @Binding var transferFailed: Bool
    @Binding var settingsError: String?
    @Binding var pendingLibrary: URL?
    @Binding var pendingBackup: AppSettings?
    @Binding var previousLibrary: Date?

    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let transferMessage {
                Section {
                    Label {
                        Text(transferMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: transferFailed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            .foregroundStyle(transferFailed ? Palette.danger : Palette.success)
                    }
                    .textSelection(.enabled)
                }
            }

            Section {
                transferRow(
                    "Sicherung", detail: "Alle Einstellungen, Themes und die Auswahl der Formate",
                    symbol: "gearshape.2",
                    export: ("transfer.backupExport", exportBackup),
                    import: ("transfer.backupImport", { chooseFile(prompt: "Importieren", then: importBackup) }))
            } header: {
                Text("Orangeflix")
            } footer: {
                Text("Für einen zweiten Mac oder als Sicherung. Anmeldung und Speicherort bleiben auf diesem Mac.")
            }

            Section {
                transferRow(
                    "config", detail: "Qualität, Ablage, Feed-Variante, Tempo und Begleitdateien",
                    symbol: "terminal",
                    export: ("transfer.configExport", exportConfig),
                    import: ("transfer.configImport", { chooseFile(prompt: "Importieren", then: importConfig) }))
            } header: {
                Text("Kommandozeilen-Werkzeug")
            } footer: {
                Text("Das Werkzeug liest die Datei unter ~/.config/orangeflix-dl/config. Beim Import bleiben ungültige Werte außen vor.")
            }

            Section {
                transferRow(
                    "library.db", detail: libraryDetail,
                    symbol: "books.vertical",
                    export: ("transfer.libraryExport", exportLibrary),
                    import: ("transfer.libraryImport", { chooseFile(prompt: "Importieren", then: stageLibrary) }))
                if let date = previousLibrary {
                    LabeledContent {
                        Button("Wiederherstellen …", systemImage: "clock.arrow.circlepath") { restorePreviousLibrary() }
                            .searchAnchor("transfer.libraryRestore")
                    } label: {
                        Text("Vorherige Bibliothek")
                        Text("Gesichert am \(date.formatted(date: .numeric, time: .shortened))")
                    }
                }
            } header: {
                Text("Bibliothek")
            } footer: {
                Text("Die Bibliothek merkt sich Formate, bekannte und geladene Folgen; das Werkzeug benutzt dieselbe Datei. Ein Import ersetzt sie, die bisherige bleibt als Sicherung. Danach die App neu starten.")
            }
        }
        .task { await account.refreshLibrary(minimumInterval: 5) }
    }

    private var libraryDetail: String {
        let count = account.library.count
        return count == 1 ? "1 Format in der Bibliothek" : "\(count) Formate in der Bibliothek"
    }

    /// A file the page exports and imports: what it is, then the two buttons.
    private func transferRow(_ title: String, detail: String, symbol: String,
                             export: (anchor: String, action: () -> Void),
                             import importing: (anchor: String, action: () -> Void)) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(themeColor(.accent))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.subheading)
                Text(detail).font(AppFont.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.m)
            Button("Exportieren …", systemImage: "square.and.arrow.up", action: export.action)
                .searchAnchor(export.anchor)
            Button("Importieren …", systemImage: "square.and.arrow.down", action: importing.action)
                .searchAnchor(importing.anchor)
        }
        .padding(.vertical, Space.xxs)
    }

    private func report(_ message: String, failed: Bool = false) {
        transferMessage = message
        transferFailed = failed
    }

    private func report(_ error: any Error) {
        report(error.localizedDescription, failed: true)
        app.show(error)
    }

    private func chooseFile(prompt: String, then handle: @escaping (URL) -> Void) {
        SettingsPanels.chooseFile(prompt: prompt, then: handle)
    }

    private func exportBackup() {
        SettingsPanels.chooseTarget(
            name: SettingsTransfer.backupFileName,
            write: { url in
                try SettingsTransfer.exportBackup(app.settings, to: url)
                return "Die Sicherung wurde als „\(url.lastPathComponent)“ gespeichert."
            },
            report: { message in report(message) },
            fail: { error in report(error) })
    }

    /// Reads the backup; the settings change when the user confirms.
    private func importBackup(_ url: URL) {
        do {
            pendingBackup = try SettingsTransfer.readBackup(from: url)
        } catch {
            report(error)
        }
    }

    private func exportConfig() {
        SettingsPanels.chooseTarget(
            name: "config",
            write: { url in
                try SettingsTransfer.exportConfig(app.settings, to: url)
                return "Die config wurde als „\(url.lastPathComponent)“ gespeichert."
            },
            report: { message in report(message) },
            fail: { error in report(error) })
    }

    private func importConfig(_ url: URL) {
        do {
            let result = try SettingsTransfer.applyConfig(ConfigFile.load(from: url), to: app)
            report(result.summary)
            settingsError = nil
            app.show("Die Einstellungen wurden importiert.")
        } catch {
            report(error)
        }
    }

    private func exportLibrary() {
        SettingsPanels.chooseTarget(
            name: "library.db",
            write: { url in
                try await app.services.store.exportDatabase(to: url)
                return "Die Bibliothek wurde als „\(url.lastPathComponent)“ gespeichert."
            },
            report: { message in report(message) },
            fail: { error in report(error) })
    }

    private func stageLibrary(_ url: URL) {
        do {
            pendingLibrary = try SettingsTransfer.stageLibrary(from: url)
        } catch {
            report(error)
        }
    }

    /// Puts the library back that the last import replaced; the current one
    /// becomes the backup in turn.
    private func restorePreviousLibrary() {
        do {
            pendingLibrary = try SettingsTransfer.stageLibrary(from: SettingsTransfer.backupURL())
        } catch {
            report(error)
        }
    }

    private func themeColor(_ token: ThemeToken) -> Color {
        Color(hex: ThemeRuntime.shared.hex(token, dark: colorScheme == .dark))
    }
}
