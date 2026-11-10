import SwiftUI

/// The Live page: where the chat starts, how it reads and how the votings show.
struct SettingsLivePage: View {
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app

    var body: some View {
        Group {
            Section {
                Toggle("Beim Öffnen zeigen", isOn: liveChatOpenBinding)
                    .searchAnchor("live.chatStart")
                Picker("Position", selection: liveChatPositionBinding) {
                    Text("Auf der Live-Seite wählen").tag(AppSettings.LiveChatPosition.auto)
                    Text("Rechts neben dem Bild").tag(AppSettings.LiveChatPosition.side)
                    Text("Unter dem Bild").tag(AppSettings.LiveChatPosition.below)
                }
                .searchAnchor("live.chatPosition")
                Picker("Schriftgröße", selection: liveChatTextSizeBinding) {
                    Text("Klein").tag(AppSettings.LiveChatTextSize.small)
                    Text("Normal").tag(AppSettings.LiveChatTextSize.normal)
                    Text("Groß").tag(AppSettings.LiveChatTextSize.large)
                    Text("Sehr groß").tag(AppSettings.LiveChatTextSize.larger)
                }
                .searchAnchor("live.textSize")
                Toggle("Profilbilder zeigen", isOn: liveChatAvatarsBinding)
                    .searchAnchor("live.avatars")
                Toggle("Uhrzeit der Nachrichten zeigen", isOn: liveChatTimesBinding)
                    .searchAnchor("live.times")
            } header: {
                Text("Chat")
            } footer: {
                Text("Mit „Auf der Live-Seite wählen“ steht der Chat dort, wo du ihn auf der Live-Seite unter „Chat rechts“ oder „Chat unten“ hinstellst. Das Fenster wächst mit dem Bild wie ein Videoplayer.")
            }
            Section {
                Picker("Anzeigen", selection: livePollsBinding) {
                    Text("Aufgeklappt").tag(AppSettings.LivePolls.expanded)
                    Text("Eingeklappt").tag(AppSettings.LivePolls.collapsed)
                    Text("Nicht anzeigen").tag(AppSettings.LivePolls.hidden)
                }
                .searchAnchor("live.polls")
            } header: {
                Text("Abstimmungen")
            } footer: {
                Text("Abstimmungen erscheinen oben rechts über dem Bild. Eingeklappt bleibt nur eine kleine Pille, die sich mit einem Klick öffnet.")
            }
        }
    }

    private var liveChatOpenBinding: Binding<Bool> {
        Binding(get: { app.settings.liveChatOpen }, set: { value in apply { $0.liveChatOpen = value } })
    }

    private var liveChatPositionBinding: Binding<AppSettings.LiveChatPosition> {
        Binding(get: { app.settings.liveChatPosition }, set: { value in apply { $0.liveChatPosition = value } })
    }

    private var liveChatTextSizeBinding: Binding<AppSettings.LiveChatTextSize> {
        Binding(get: { app.settings.liveChatTextSize }, set: { value in apply { $0.liveChatTextSize = value } })
    }

    private var liveChatAvatarsBinding: Binding<Bool> {
        Binding(get: { app.settings.liveChatAvatars }, set: { value in apply { $0.liveChatAvatars = value } })
    }

    private var liveChatTimesBinding: Binding<Bool> {
        Binding(get: { app.settings.liveChatTimes }, set: { value in apply { $0.liveChatTimes = value } })
    }

    private var livePollsBinding: Binding<AppSettings.LivePolls> {
        Binding(get: { app.settings.livePolls }, set: { value in apply { $0.livePolls = value } })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
