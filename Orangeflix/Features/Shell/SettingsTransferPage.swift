import SwiftUI

/// Backup, CLI config & local SQLite library import/export.
struct SettingsTransferPage: View {
    @Binding var transferMessage: String?
    @Binding var transferFailed: Bool
    @Binding var settingsError: String?
    @Binding var pendingLibrary: URL?
    @Binding var pendingBackup: AppSettings?
    @Binding var previousLibrary: Date?

    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let transferMessage {
                ProfileNotice(
                    symbol: transferFailed ? "xmark.octagon.fill" : "checkmark.circle.fill",
                    text: transferMessage,
                    tint: transferFailed ? Palette.danger : Palette.success,
                    background: transferFailed ? Palette.dangerSoft : Palette.successSoft
                )
            }

            SettingsSection(
                "App-Sicherung",
                footer: "Ideal für den Umzug auf einen zweiten Mac. Anmeldedaten und der lokale Download-Ordner werden aus Sicherheitsgründen nicht mitgesichert."
            ) {
                EmptyView()
            } content: {
                transferRow(
                    "Einstellungen & Themes",
                    detail: "Alle App-Optionen, importierten Themes und die Format-Auswahl als JSON-Datei",
                    symbol: "gearshape.2.fill",
                    export: ("transfer.backupExport", exportBackup),
                    import: ("transfer.backupImport", { chooseFile(prompt: "Importieren", then: importBackup) })
                )
            }

            SettingsSection(
                "Kommandozeilen-Werkzeug",
                footer: "Kompatibel mit ~/.config/orangeflix-dl/config. Ungültige Werte werden beim Import übersprungen."
            ) {
                EmptyView()
            } content: {
                transferRow(
                    "CLI-Konfiguration (config)",
                    detail: "Download-Qualität, Ordnerstruktur, Feed-Variante, Tempo und Begleitdateien",
                    symbol: "terminal.fill",
                    export: ("transfer.configExport", exportConfig),
                    import: ("transfer.configImport", { chooseFile(prompt: "Importieren", then: importConfig) })
                )
            }

            SettingsSection(
                "Lokale Bibliothek",
                footer: "Speichert abonnierte Formate sowie bekannte und geladene Folgen. Beim Import wird die bisherige Datenbank automatisch als Sicherung behalten."
            ) {
                EmptyView()
            } content: {
                transferRow(
                    "Datenbank (library.db)",
                    detail: libraryDetail,
                    symbol: "books.vertical.fill",
                    export: ("transfer.libraryExport", exportLibrary),
                    import: ("transfer.libraryImport", { chooseFile(prompt: "Importieren", then: stageLibrary) })
                )

                if let date = previousLibrary {
                    Hairline()
                    SettingsRow(
                        "Vorherige Bibliothek verfügbar",
                        subtitle: "Gesichert am \(date.formatted(date: .numeric, time: .shortened))"
                    ) {
                        Button("Wiederherstellen …", systemImage: "clock.arrow.circlepath") {
                            restorePreviousLibrary()
                        }
                        .controlSize(.small)
                        .searchAnchor("transfer.libraryRestore")
                    }
                }
            }
        }
        .task { await account.refreshLibrary(minimumInterval: 5) }
    }

    private var libraryDetail: String {
        let count = account.library.count
        return count == 1 ? "1 Format in der lokalen Bibliothek" : "\(count) Formate in der lokalen Bibliothek"
    }

    private func transferRow(
        _ title: String,
        detail: String,
        symbol: String,
        export: (anchor: String, action: () -> Void),
        import importing: (anchor: String, action: () -> Void)
    ) -> some View {
        HStack(spacing: Space.m) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Palette.accentSoft)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.accentText)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(AppFont.subheading)
                    .foregroundStyle(Palette.textPrimary)
                Text(detail)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Space.m)

            HStack(spacing: Space.xs) {
                Button("Exportieren …", systemImage: "square.and.arrow.up", action: export.action)
                    .controlSize(.small)
                    .searchAnchor(export.anchor)
                Button("Importieren …", systemImage: "square.and.arrow.down", action: importing.action)
                    .controlSize(.small)
                    .searchAnchor(importing.anchor)
            }
        }
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
            fail: { error in report(error) }
        )
    }

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
            fail: { error in report(error) }
        )
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
            fail: { error in report(error) }
        )
    }

    private func stageLibrary(_ url: URL) {
        do {
            pendingLibrary = try SettingsTransfer.stageLibrary(from: url)
        } catch {
            report(error)
        }
    }

    private func restorePreviousLibrary() {
        do {
            pendingLibrary = try SettingsTransfer.stageLibrary(from: SettingsTransfer.backupURL())
        } catch {
            report(error)
        }
    }
}
