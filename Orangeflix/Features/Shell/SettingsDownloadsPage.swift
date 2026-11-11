import AppKit
import SwiftUI

/// Downloads settings: target folder at the top, file quality & companion files,
/// concurrency, and a clean disclosure group for advanced rate/feed controls.
struct SettingsDownloadsPage: View {
    @Binding var settingsError: String?
    @Binding var advancedExpanded: Bool

    @Environment(AppModel.self) private var app

    private var isCustomFolder: Bool {
        app.downloadFolder.standardizedFileURL != FolderBookmarkStore.defaultFolder().standardizedFileURL
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsSection(
                "Speicherort",
                footer: "Alle heruntergeladenen Folgen und Begleitdateien werden in diesem Ordner abgelegt."
            ) {
                if isCustomFolder {
                    Button("Auf Standard zurücksetzen") {
                        app.resetDownloadFolder()
                    }
                    .controlSize(.small)
                }
            } content: {
                HStack(spacing: Space.m) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .fill(Palette.accentSoft)
                        Image(systemName: "folder.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(Palette.accentText)
                    }
                    .frame(width: 36, height: 36)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(app.downloadFolder.lastPathComponent)
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textPrimary)
                        Text(AppFormat.displayPath(app.downloadFolder))
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: Space.s)

                    HStack(spacing: Space.xs) {
                        Button("Im Finder zeigen", systemImage: "magnifyingglass") {
                            AppFormat.reveal(app.downloadFolder)
                        }
                        .controlSize(.small)

                        Button("Ändern …") {
                            chooseFolder()
                        }
                        .controlSize(.small)
                    }
                }
                .searchAnchor("storage.folder")
            }

            SettingsSection(
                "Dateien & Begleitdateien",
                footer: app.settings.layout == .flat
                    ? "„Flach“ legt alle Folgen eines Formats direkt zusammen in einen Format-Ordner."
                    : "„Kompatibel“ legt im Ordner des Formats für jede Folge einen eigenen Unterordner an."
            ) {
                EmptyView()
            } content: {
                SettingsRow("Download-Qualität", subtitle: "Auflösung der gespeicherten Videodatei") {
                    Picker("Qualität", selection: qualityBinding) {
                        ForEach(AppSettings.Quality.allCases, id: \.self) { quality in
                            Text(quality.shellTitle).tag(quality)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .searchAnchor("downloads.quality")

                Hairline()

                SettingsRow("Ordnerstruktur", subtitle: "Wie Dateien innerhalb des Zielordners sortiert werden") {
                    Picker("Ablage", selection: layoutBinding) {
                        ForEach(AppSettings.Layout.allCases, id: \.self) { layout in
                            Text(layout.shellTitle).tag(layout)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .searchAnchor("downloads.layout")

                Hairline()

                SettingsToggleRow(
                    title: "Vorschaubild speichern (.jpg)",
                    subtitle: "Speichert das Episoden-Cover neben der Videodatei",
                    isOn: thumbBinding
                )
                .searchAnchor("downloads.thumb")

                Hairline()

                SettingsToggleRow(
                    title: "Metadaten speichern (.json)",
                    subtitle: "Speichert Beschreibung, Datum und Kapitel als JSON-Datei",
                    isOn: metaBinding
                )
                .searchAnchor("downloads.meta")
            }

            SettingsSection(
                "Tempo & Erweitert",
                footer: "Ein Tempolimit von 0 KiB/s lädt mit voller Verbindungsgeschwindigkeit."
            ) {
                EmptyView()
            } content: {
                SettingsRow("Gleichzeitige Downloads", subtitle: "1 bis 8 parallele Übertragungen") {
                    HStack(spacing: Space.s) {
                        Text("\(app.settings.parallel)")
                            .font(AppFont.subheading.monospacedDigit())
                            .frame(minWidth: 18, alignment: .trailing)
                        Stepper("Gleichzeitig", value: parallelBinding, in: AppSettings.parallelRange)
                            .labelsHidden()
                    }
                }
                .searchAnchor("downloads.parallel")

                Hairline()

                DisclosureGroup("Erweiterte Optionen (Bandbreite, Pause & RSS-Feed)", isExpanded: $advancedExpanded) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        Hairline()
                            .padding(.top, Space.xs)

                        SettingsRow("Pause zwischen Downloads", subtitle: "Wartezeit vor dem nächsten Start (0–3600 s)") {
                            HStack(spacing: Space.xs) {
                                TextField("", value: delayBinding, format: SettingsFieldFormat.delay)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 72)
                                Text("Sek.")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .searchAnchor("downloads.delay")

                        Hairline()

                        SettingsRow("Bandbreitenlimit", subtitle: "Maximale Geschwindigkeit je Download (0 = unbegrenzt)") {
                            HStack(spacing: Space.xs) {
                                TextField("", value: limitBinding, format: SettingsFieldFormat.limit)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                                    .frame(width: 84)
                                Text("KiB/s")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        .searchAnchor("downloads.limit")

                        Hairline()

                        SettingsRow("RSS-Feed-Variante", subtitle: "Fallback-Feed-Nummer für ältere Schnittstellen (Standard: 1)") {
                            HStack(spacing: Space.s) {
                                Text("\(app.settings.submodule)")
                                    .font(AppFont.subheading.monospacedDigit())
                                Stepper("Feed-Variante", value: submoduleBinding, in: 1...100_000)
                                    .labelsHidden()
                            }
                        }
                        .searchAnchor("downloads.submodule")
                    }
                }
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
            }
        }
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

    private var qualityBinding: Binding<AppSettings.Quality> {
        Binding(get: { app.settings.quality }, set: { value in apply { $0.quality = value } })
    }

    private var layoutBinding: Binding<AppSettings.Layout> {
        Binding(get: { app.settings.layout }, set: { value in apply { $0.layout = value } })
    }

    private var submoduleBinding: Binding<Int> {
        Binding(get: { app.settings.submodule }, set: { value in apply { $0.submodule = value } })
    }

    private var parallelBinding: Binding<Int> {
        Binding(get: { app.settings.parallel }, set: { value in apply { $0.parallel = value } })
    }

    private var delayBinding: Binding<Double> {
        Binding(get: { app.settings.delay }, set: { value in apply { $0.delay = value } })
    }

    private var limitBinding: Binding<Int> {
        Binding(get: { app.settings.limitKiB }, set: { value in apply { $0.limitKiB = value } })
    }

    private var thumbBinding: Binding<Bool> {
        Binding(get: { app.settings.thumb }, set: { value in apply { $0.thumb = value } })
    }

    private var metaBinding: Binding<Bool> {
        Binding(get: { app.settings.meta }, set: { value in apply { $0.meta = value } })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
