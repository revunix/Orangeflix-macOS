import SwiftUI

/// The quality used when a video is played instead of saved.
struct SettingsStreamingPage: View {
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app

    var body: some View {
        Section {
            Picker("Qualität", selection: streamQualityBinding) {
                ForEach(AppSettings.Quality.allCases, id: \.self) { quality in
                    Text(quality.shellTitle).tag(quality)
                }
            }
            .searchAnchor("streaming.quality")
        } header: {
            Text("Wiedergabe")
        } footer: {
            Text("Gilt für Folgen und Rückblicke. Live läuft als Stream.")
        }
    }

    private var streamQualityBinding: Binding<AppSettings.Quality> {
        Binding(
            get: { app.settings.streamQuality },
            set: { value in apply { $0.streamQuality = value } })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
