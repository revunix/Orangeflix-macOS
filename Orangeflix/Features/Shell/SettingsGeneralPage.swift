import AppKit
import Sparkle
import SwiftUI

/// Allgemein: software update, the download folder and running in the background.
struct SettingsGeneralPage: View {
    let updaterController: SPUStandardUpdaterController
    @Binding var automaticUpdateChecks: Bool
    @Binding var updateCheckInterval: TimeInterval
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app
    @Environment(BackgroundMode.self) private var background
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Updates für Orangeflix for Mac")
                        Text("Neue Versionen mit Änderungen und Fehlerbehebungen abrufen.")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                    }
                    Spacer(minLength: Space.m)
                    Button("Nach Updates suchen …") {
                        updaterController.checkForUpdates(nil)
                    }
                }
                .searchAnchor("about.updates")

                Toggle("Automatisch nach Updates suchen", isOn: automaticUpdateChecksBinding)
                    .searchAnchor("about.automaticUpdates")
                Picker("Suchintervall", selection: updateCheckIntervalBinding) {
                    Text("Täglich").tag(TimeInterval(86_400))
                    Text("Wöchentlich").tag(TimeInterval(604_800))
                    Text("Monatlich").tag(TimeInterval(2_592_000))
                }
                .disabled(!automaticUpdateChecks)
                .searchAnchor("about.updateInterval")
            } header: {
                Text("Softwareupdate")
            } footer: {
                Text("Automatische Suchen erfolgen im gewählten Intervall, solange Orangeflix läuft. Vor der Installation prüft der Updater die Signatur des Downloads; die Versionshinweise erscheinen im Update-Fenster.")
            }

            Section {
                LabeledContent("Ordner") {
                    Text(AppFormat.displayPath(app.downloadFolder))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .searchAnchor("storage.folder")
                Button("Ordner ändern …") { chooseFolder() }
                    .searchAnchor("storage.change")
                Button("Im Finder zeigen") { AppFormat.reveal(app.downloadFolder) }
                    .searchAnchor("storage.reveal")
                Button("Auf ~/Downloads/Orangeflix zurücksetzen") { resetFolder() }
                    .searchAnchor("storage.reset")
            } header: { Text("Speicherort") } footer: { Text("Wohin die Downloads geschrieben werden.") }

            backgroundSection
        }
    }

    /// Keeps the checks running after the window closes, and after a login.
    private var backgroundSection: some View {
        Section {
            Toggle("Im Hintergrund weiterlaufen", isOn: runsInBackgroundBinding)
                .searchAnchor("formats.background")
            Toggle("Bei der Anmeldung starten", isOn: Binding(
                get: { background.launchesAtLogin || background.needsApproval },
                set: { background.setLaunchAtLogin($0) }))
                .searchAnchor("formats.login")
            if background.needsApproval {
                Button("In den Anmeldeobjekten erlauben") { background.openLoginItemSettings() }
            }
        } header: {
            Text("Im Hintergrund")
        } footer: {
            if let error = background.loginError {
                Text(error)
            } else if background.needsApproval {
                Text("macOS wartet auf deine Erlaubnis unter Systemeinstellungen › Allgemein › Anmeldeobjekte.")
            } else if app.settings.runsInBackground {
                Text("Schließt du das Fenster, verschwindet Orangeflix aus dem Dock und bleibt als Symbol in der Menüleiste, damit Mitteilungen weiter ankommen. Beim Start nach der Anmeldung öffnet sich kein Fenster. Mit ⌘Q beendet, meldet die App nichts mehr.")
            } else {
                Text("Eingeschaltet verschwindet Orangeflix beim Schließen des Fensters aus dem Dock und bleibt als Symbol in der Menüleiste. Ausgeschaltet bleibt die App im Dock und meldet von dort weiter. Mit ⌘Q beendet, meldet sie nichts mehr.")
            }
        }
        .onAppear { background.refreshLoginItem() }
    }

    private var automaticUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: { automaticUpdateChecks },
            set: { value in
                automaticUpdateChecks = value
                updaterController.updater.automaticallyChecksForUpdates = value
            })
    }

    private var updateCheckIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { updateCheckInterval },
            set: { value in
                updateCheckInterval = value
                updaterController.updater.updateCheckInterval = value
            })
    }

    private var runsInBackgroundBinding: Binding<Bool> {
        Binding(
            get: { app.settings.runsInBackground },
            set: { value in
                apply { $0.runsInBackground = value }
                background.updateDock()
            })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.directoryURL = app.downloadFolder
        SettingsPanels.present(panel) { url in
            do {
                try app.chooseDownloadFolder(url)
            } catch {
                app.show(error)
            }
        }
    }

    private func resetFolder() {
        app.resetDownloadFolder()
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }

    private func themeColor(_ token: ThemeToken) -> Color {
        Color(hex: ThemeRuntime.shared.hex(token, dark: colorScheme == .dark))
    }
}
