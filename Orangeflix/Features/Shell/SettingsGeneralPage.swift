import AppKit
import Sparkle
import SwiftUI

/// Allgemein: software updates and background / login-item behavior.
struct SettingsGeneralPage: View {
    let updaterController: SPUStandardUpdaterController
    @Binding var automaticUpdateChecks: Bool
    @Binding var updateCheckInterval: TimeInterval
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app
    @Environment(BackgroundMode.self) private var background

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsSection(
                "Softwareupdate",
                footer: "Vor jeder Installation prüft Sparkle kryptografisch die Signatur des Updates und zeigt die Versionshinweise an."
            ) {
                BrandPill(text: "Version \(AccountModel.appVersion)", color: Palette.textSecondary, background: Palette.surfaceMuted)
            } content: {
                HStack(spacing: Space.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 40, height: 40)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Updates für Orangeflix for Mac")
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Neue Versionen mit Verbesserungen und Fehlerbehebungen abrufen.")
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }

                    Spacer(minLength: Space.m)

                    Button("Nach Updates suchen …") {
                        updaterController.checkForUpdates(nil)
                    }
                    .controlSize(.small)
                }
                .searchAnchor("about.updates")

                Hairline()

                SettingsToggleRow(
                    title: "Automatisch nach Updates suchen",
                    subtitle: "Prüft regelmäßig im Hintergrund, solange Orangeflix geöffnet ist",
                    isOn: automaticUpdateChecksBinding
                )
                .searchAnchor("about.automaticUpdates")

                Hairline()

                SettingsRow("Suchintervall", subtitle: "Wie häufig automatisch nach neuen Versionen gesucht wird") {
                    Picker("Suchintervall", selection: updateCheckIntervalBinding) {
                        Text("Täglich").tag(TimeInterval(86_400))
                        Text("Wöchentlich").tag(TimeInterval(604_800))
                        Text("Monatlich").tag(TimeInterval(2_592_000))
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(!automaticUpdateChecks)
                }
                .opacity(automaticUpdateChecks ? 1 : 0.48)
                .searchAnchor("about.updateInterval")
            }

            SettingsSection(
                "Hintergrund & Systemstart",
                footer: backgroundFooter
            ) {
                EmptyView()
            } content: {
                SettingsToggleRow(
                    title: "Im Hintergrund weiterlaufen",
                    subtitle: "Beim Schließen des Fensters wechselt Orangeflix aus dem Dock in die Menüleiste",
                    isOn: runsInBackgroundBinding
                )
                .searchAnchor("formats.background")

                Hairline()

                SettingsToggleRow(
                    title: "Bei der Anmeldung starten",
                    subtitle: "Startet Orangeflix automatisch nach dem Anmelden am Mac",
                    isOn: Binding(
                        get: { background.launchesAtLogin || background.needsApproval },
                        set: { background.setLaunchAtLogin($0) }
                    )
                )
                .searchAnchor("formats.login")

                if background.needsApproval {
                    Hairline()
                    HStack(spacing: Space.s) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Palette.warning)
                        Text("macOS wartet auf deine Bestätigung in den Anmeldeobjekten.")
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                        Spacer(minLength: Space.s)
                        Button("Anmeldeobjekte öffnen") {
                            background.openLoginItemSettings()
                        }
                        .controlSize(.small)
                    }
                }
            }
            .onAppear { background.refreshLoginItem() }
        }
    }

    private var backgroundFooter: String {
        if let error = background.loginError {
            return error
        }
        if app.settings.runsInBackground {
            return "Über das Menüleisten-Symbol siehst du jederzeit laufende Livestreams, Downloads und Mitteilungsschalter. Mit ⌘Q wird die App vollständig beendet."
        }
        return "Ist der Hintergrundmodus ausgeschaltet, bleibt Orangeflix im Dock sichtbar. Mit ⌘Q beendest du die App vollständig."
    }

    private var automaticUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: { automaticUpdateChecks },
            set: { value in
                automaticUpdateChecks = value
                updaterController.updater.automaticallyChecksForUpdates = value
            }
        )
    }

    private var updateCheckIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { updateCheckInterval },
            set: { value in
                updateCheckInterval = value
                updaterController.updater.updateCheckInterval = value
            }
        )
    }

    private var runsInBackgroundBinding: Binding<Bool> {
        Binding(
            get: { app.settings.runsInBackground },
            set: { value in
                SettingsWrite.apply(app, $settingsError) { $0.runsInBackground = value }
                background.updateDock()
            }
        )
    }
}
