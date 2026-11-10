import SwiftUI

/// What this Mac announces itself, and what the server sends to the account.
/// The two tests are named apart, so they are not one button.
struct SettingsNotificationsPage: View {
    @Binding var settingsError: String?
    @Binding var pendingDelete: SettingsDelete?
    /// Opens the format list, where the announced formats are chosen.
    var showFormats: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(NewEpisodeWatcher.self) private var watcher
    @Environment(NotificationSettingsModel.self) private var notifications
    @Environment(LiveModel.self) private var live

    var body: some View {
        Group {
            Section {
                Toggle("Neue Folgen melden", isOn: notificationsBinding)
                    .searchAnchor("general.newEpisodes")
                LabeledContent {
                    Button("Formate wählen …") { showFormats() }
                } label: {
                    Text("Gemeldete Formate")
                    Text(announcedFormatsText)
                }
                Toggle("Livestreams melden", isOn: liveNotificationsBinding)
                    .searchAnchor("general.liveNotifications")
                Toggle("Bei Erwähnungen und Reaktionen melden", isOn: chatNotificationsBinding)
                    .searchAnchor("general.chatNotifications")
                HStack {
                    Button("Testmitteilung dieses Macs") {
                        Task {
                            await watcher.sendTestNotification()
                            await watcher.check()
                        }
                    }
                    .searchAnchor("general.testNotifications")
                    if !watcher.isAllowed {
                        Button("In den Systemeinstellungen erlauben") {
                            watcher.openSystemSettings()
                        }
                        .searchAnchor("general.allowNotifications")
                    }
                }
            } header: {
                Text("Dieser Mac")
            } footer: {
                if let error = watcher.lastError {
                    Text(error)
                } else if watcher.isAllowed {
                    Text("Die App prüft alle 15 Minuten die neuesten Folgen und alle 2 Minuten, ob ein Livestream läuft. Mit den Chat-Mitteilungen bleibt der Live-Chat verbunden, auch wenn die Live-Seite geschlossen ist. Ein Klick auf eine Mitteilung öffnet das Format oder die Live-Seite.")
                } else {
                    Text("macOS hat die Mitteilungen für Orangeflix noch nicht erlaubt.")
                }
            }

            if !app.hasCredentials {
                Section {
                    Text("Nicht angemeldet")
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Server")
                } footer: {
                    Text("Die Anmeldung erfolgt im Hauptfenster. Die Mitteilungen dieses Macs oben gelten auch ohne Konto.")
                }
            } else {
                if let error = notifications.error {
                    Section {
                        ProfileNotice(symbol: "exclamationmark.triangle.fill", text: error,
                                      tint: Palette.danger, background: Palette.dangerSoft)
                    }
                }

                Section {
                    ForEach(notifications.channelNames, id: \.self) { channel in
                        Toggle(NotificationSettingsModel.channelName(channel), isOn: channelBinding(channel))
                    }
                    Button("Testmitteilung vom Server") {
                        Task { await notifications.sendTest() }
                    }
                    .searchAnchor("notifications.test")
                    Button("E-Mail-Versand wieder einschalten") {
                        Task { await notifications.resubscribeEmail() }
                    }
                    .searchAnchor("notifications.resubscribe")
                } header: {
                    Text("Kanäle")
                } footer: {
                    Text("Die Kanäle gelten für alle Ereignisse. Ein Abmelden vom E-Mail-Versand lässt sich nur hier zurücknehmen.")
                }

                Section {
                    if notifications.catalog.isEmpty {
                        // A failed load is not an empty catalog; the notice
                        // above says what went wrong.
                        Text(notifications.isLoading ? "Der Katalog wird geladen …"
                             : notifications.error != nil ? "Die Ereignisse konnten nicht geladen werden."
                             : "Der Server nennt keine Ereignisse.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(notifications.catalog) { event in
                        Toggle(event.label, isOn: eventBinding(event.key))
                            .disabled(!notifications.isConfigurable(event.key))
                    }
                } header: {
                    Text("Ereignisse")
                } footer: {
                    Text("Der Server schickt nur die Ereignisse, die hier eingeschaltet sind.")
                }

                Section {
                    if notifications.isLoading {
                        Text("Push-Geräte werden geladen …")
                            .foregroundStyle(.secondary)
                    } else if let error = notifications.devicesError {
                        Text("Push-Geräte konnten nicht geladen werden: \(error)")
                            .foregroundStyle(.secondary)
                    } else if !notifications.devicesLoaded {
                        Text("Push-Geräte wurden noch nicht geladen.")
                            .foregroundStyle(.secondary)
                    } else if notifications.devices.isEmpty {
                        Text("Keine Geräte für Server-Push registriert.")
                            .foregroundStyle(.secondary)
                    }
                    if !notifications.isLoading, notifications.devicesError == nil, notifications.devicesLoaded {
                        ForEach(notifications.devices) { device in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name.isEmpty ? device.deviceID : device.name)
                                        .font(AppFont.body)
                                    Text(device.platform)
                                        .font(AppFont.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                Spacer(minLength: 0)
                                Button("Abmelden") { pendingDelete = .pushDevice(device.deviceID) }
                            }
                        }
                    }
                    Button("Geräte aktualisieren") {
                        Task { await notifications.load() }
                    }
                    .disabled(notifications.isLoading)
                } header: {
                    Text("Push-Geräte")
                } footer: {
                    Text("Hier stehen Geräte, die für Push-Mitteilungen des Servers registriert sind, nicht die Mitteilungen, die diese App selbst anzeigt.")
                }
            }
        }
        .task(id: app.accountGeneration) {
            guard app.hasCredentials, notifications.needsLoad else { return }
            await notifications.load()
        }
    }

    /// How many formats are announced, for the Mitteilungen section.
    private var announcedFormatsText: String {
        switch announcedFormats.count {
        case 0: "Noch keins gewählt; ohne Auswahl meldet die App keine neuen Folgen."
        case 1: "1 Format"
        case let count: "\(count) Formate"
        }
    }

    /// The chosen formats the Mediathek shows; only those are announced.
    private var announcedFormats: Set<Int> {
        NewEpisodeLogic.announced(notified: app.settings.notifiedMagazines, hidden: app.settings.hiddenMagazines)
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.notificationsOn },
            set: { value in
                apply { $0.notificationsOn = value }
                if value { Task { await watcher.refreshPermission() } }
            })
    }

    private var liveNotificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.liveNotificationsOn },
            set: { value in
                apply { $0.liveNotificationsOn = value }
                if value { Task { await watcher.refreshPermission(); await watcher.checkLive() } }
            })
    }

    private var chatNotificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.chatNotificationsOn },
            set: { value in
                apply { $0.chatNotificationsOn = value }
                if value { Task { await watcher.refreshPermission() } }
                Task { await live.settingsChanged() }
            })
    }

    /// The state of one channel of the notifications.
    private func channelBinding(_ channel: String) -> Binding<Bool> {
        Binding(
            get: { notifications.isChannelOn(channel) },
            set: { value in Task { await notifications.setChannel(channel, enabled: value) } })
    }

    /// The state of one event of the catalog.
    private func eventBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { notifications.isEnabled(key) },
            set: { value in Task { await notifications.setEvent(key, enabled: value) } })
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
