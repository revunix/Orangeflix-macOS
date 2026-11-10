import SwiftUI

/// How downloaded files are named, paced and accompanied.
struct SettingsDownloadsPage: View {
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            Section {
                Picker("Qualität", selection: qualityBinding) {
                    ForEach(AppSettings.Quality.allCases, id: \.self) { quality in
                        Text(quality.shellTitle).tag(quality)
                    }
                }
                .searchAnchor("downloads.quality")
                Picker("Ablage", selection: layoutBinding) {
                    ForEach(AppSettings.Layout.allCases, id: \.self) { layout in
                        Text(layout.shellTitle).tag(layout)
                    }
                }
                .searchAnchor("downloads.layout")
                LabeledContent("Feed-Variante") {
                    HStack(spacing: Space.s) {
                        Text("\(app.settings.submodule)")
                            .monospacedDigit()
                        Stepper("Feed-Variante", value: submoduleBinding, in: 1...100_000)
                            .labelsHidden()
                    }
                }
                .searchAnchor("downloads.submodule")
            } header: {
                Text("Dateien")
            } footer: {
                Text("Die Qualität der Datei, die auf die Platte geht. "
                     + (app.settings.layout == .flat
                        ? "„Flach“ legt alle Folgen eines Formats in einen Ordner."
                        : "„Kompatibel“ legt im Ordner des Formats einen Ordner je Folge an.")
                     + " Die Feed-Variante ist die Nummer des RSS-Feeds, falls die Folgen nicht über die neuere Schnittstelle kommen. 1 ist der übliche Wert.")
            }

            Section {
                LabeledContent("Gleichzeitig") {
                    HStack(spacing: Space.s) {
                        Text("\(app.settings.parallel)")
                            .monospacedDigit()
                        Stepper("Gleichzeitig", value: parallelBinding, in: AppSettings.parallelRange)
                            .labelsHidden()
                    }
                }
                .searchAnchor("downloads.parallel")
                LabeledContent("Pause") {
                    HStack(spacing: Space.xs) {
                        TextField("", value: delayBinding, format: SettingsFieldFormat.delay)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("Sekunden")
                            .foregroundStyle(.secondary)
                    }
                }
                .searchAnchor("downloads.delay")
                LabeledContent("Tempolimit") {
                    HStack(spacing: Space.xs) {
                        TextField("", value: limitBinding, format: SettingsFieldFormat.limit)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 72)
                        Text("KiB/s")
                            .foregroundStyle(.secondary)
                    }
                }
                .searchAnchor("downloads.limit")
            } header: {
                Text("Tempo")
            } footer: {
                Text("Gleichzeitige Downloads 1–8, Pause 0–3600 Sekunden, Tempolimit in KiB pro Sekunde (0 heißt ohne Limit).")
            }

            Section {
                Toggle("Vorschaubild speichern", isOn: thumbBinding)
                    .searchAnchor("downloads.thumb")
                Toggle("Metadaten speichern", isOn: metaBinding)
                    .searchAnchor("downloads.meta")
            } header: {
                Text("Begleitdateien")
            } footer: {
                Text("Vorschaubild und Angaben als JSON landen neben dem Video.")
            }
        }
    }

    private var qualityBinding: Binding<AppSettings.Quality> {
        Binding(
            get: { app.settings.quality },
            set: { value in apply { $0.quality = value } })
    }

    private var layoutBinding: Binding<AppSettings.Layout> {
        Binding(
            get: { app.settings.layout },
            set: { value in apply { $0.layout = value } })
    }

    private var submoduleBinding: Binding<Int> {
        Binding(
            get: { app.settings.submodule },
            set: { value in apply { $0.submodule = value } })
    }

    private var parallelBinding: Binding<Int> {
        Binding(
            get: { app.settings.parallel },
            set: { value in apply { $0.parallel = value } })
    }

    private var delayBinding: Binding<Double> {
        Binding(
            get: { app.settings.delay },
            set: { value in apply { $0.delay = value } })
    }

    private var limitBinding: Binding<Int> {
        Binding(
            get: { app.settings.limitKiB },
            set: { value in apply { $0.limitKiB = value } })
    }

    private var thumbBinding: Binding<Bool> {
        Binding(
            get: { app.settings.thumb },
            set: { value in apply { $0.thumb = value } })
    }

    private var metaBinding: Binding<Bool> {
        Binding(
            get: { app.settings.meta },
            set: { value in apply { $0.meta = value } })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
