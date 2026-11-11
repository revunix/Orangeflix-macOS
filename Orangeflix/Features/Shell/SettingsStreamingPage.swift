import SwiftUI

/// Streaming quality and Discord Rich Presence settings.
struct SettingsStreamingPage: View {
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app
    @Environment(PlaybackCenter.self) private var playback

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

        Section {
            Toggle("Aktuelle Wiedergabe in Discord anzeigen", isOn: discordEnabledBinding)
                .searchAnchor("streaming.discord")

            Toggle("Link-Button zur Folge oder zum Livestream zeigen", isOn: discordButtonBinding)
                .disabled(!app.settings.discordRPCEnabled)
                .searchAnchor("streaming.discordButton")

            LabeledContent("Status") {
                HStack(spacing: 6) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(playback.discord.status.label)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Discord Rich Presence")
        } footer: {
            Text("Zeigt wie bei Spotify an, was du gerade auf Orangeflix ansiehst – inklusive Cover, Live-Fortschrittsbalken, aktuellem Kapitel und Direktlink zur Folge oder zum Livestream.")
        }
        .task {
            playback.discord.probe(enabled: app.settings.discordRPCEnabled)
        }
    }

    private var statusColor: Color {
        switch playback.discord.status {
        case .connected: Palette.success
        case .idle: Palette.accent
        case .disabled: Palette.textTertiary
        case .waitingForDiscord: Palette.warning
        case .rejected: Palette.danger
        }
    }

    private var streamQualityBinding: Binding<AppSettings.Quality> {
        Binding(
            get: { app.settings.streamQuality },
            set: { value in apply { $0.streamQuality = value } })
    }

    private var discordEnabledBinding: Binding<Bool> {
        Binding(
            get: { app.settings.discordRPCEnabled },
            set: { value in
                apply { $0.discordRPCEnabled = value }
                playback.syncDiscordPresence(force: true)
            })
    }

    private var discordButtonBinding: Binding<Bool> {
        Binding(
            get: { app.settings.discordShowLinkButton },
            set: { value in
                apply { $0.discordShowLinkButton = value }
                playback.syncDiscordPresence(force: true)
            })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
