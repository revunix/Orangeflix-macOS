import SwiftUI

/// Notifications settings: local macOS notifications at the top, followed by
/// server-side channels, events & registered push devices.
struct SettingsNotificationsPage: View {
    @Binding var settingsError: String?
    @Binding var pendingDelete: SettingsDelete?
    var showFormats: () -> Void

    @Environment(AppModel.self) private var app
    @Environment(NewEpisodeWatcher.self) private var watcher
    @Environment(NotificationSettingsModel.self) private var notifications
    @Environment(LiveModel.self) private var live

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if !watcher.isAllowed {
                HStack(alignment: .center, spacing: Space.m) {
                    Image(systemName: "bell.slash.fill")
                        .foregroundStyle(Palette.warning)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("System-Mitteilungen noch nicht erlaubt")
                            .font(AppFont.subheading)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Erlaube Mitteilungen für Orangeflix in den macOS-Systemeinstellungen.")
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: Space.s)
                    Button("Systemeinstellungen öffnen") {
                        watcher.openSystemSettings()
                    }
                    .controlSize(.small)
                    .searchAnchor("general.allowNotifications")
                }
                .padding(Space.m)
                .background(Palette.warningSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.warning.opacity(0.35), lineWidth: 1)
                }
            }

            SettingsSection(
                "Dieser Mac",
                footer: watcher.lastError ?? "Prüft alle 15 Minuten auf neue Folgen und alle 2 Minuten auf laufende Livestreams. Ein Klick auf eine Mitteilung öffnet direkt das Format oder den Stream."
            ) {
                Button("Testmitteilung senden") {
                    Task {
                        await watcher.sendTestNotification()
                        await watcher.check()
                    }
                }
                .controlSize(.small)
                .searchAnchor("general.testNotifications")
            } content: {
                SettingsToggleRow(
                    title: "Neue Folgen melden",
                    subtitle: "Schickt einen Hinweis, sobald eines deiner gewählten Formate erscheint",
                    isOn: notificationsBinding
                )
                .searchAnchor("general.newEpisodes")

                Hairline()

                SettingsRow("Gemeldete Formate", subtitle: announcedFormatsText) {
                    Button("Formate wählen …") { showFormats() }
                        .controlSize(.small)
                }

                Hairline()

                SettingsToggleRow(
                    title: "Livestreams melden",
                    subtitle: "Informiert dich, sobald auf Orangeflix ein Stream startet",
                    isOn: liveNotificationsBinding
                )
                .searchAnchor("general.liveNotifications")

                Hairline()

                SettingsToggleRow(
                    title: "Erwähnungen & Reaktionen im Live-Chat",
                    subtitle: "Hält den Live-Chat verbunden, auch wenn das Live-Fenster geschlossen ist",
                    isOn: chatNotificationsBinding
                )
                .searchAnchor("general.chatNotifications")
            }

            if !app.hasCredentials {
                SettingsSection(
                    "Server-Mitteilungen",
                    footer: "Melde dich im Hauptfenster an, um E-Mail- und Push-Kanäle deines Kontos zu verwalten."
                ) {
                    EmptyView()
                } content: {
                    Text("Nicht angemeldet — die lokalen Mac-Mitteilungen oben funktionieren auch ohne Konto.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
            } else {
                if let error = notifications.error {
                    ProfileNotice(symbol: "exclamationmark.triangle.fill", text: error,
                                  tint: Palette.danger, background: Palette.dangerSoft)
                }

                SettingsSection(
                    "Server-Kanäle",
                    footer: "Die Kanäle gelten für alle unten aktivierten Server-Ereignisse."
                ) {
                    Button("Server-Test senden") {
                        Task { await notifications.sendTest() }
                    }
                    .controlSize(.small)
                    .searchAnchor("notifications.test")
                } content: {
                    ForEach(Array(notifications.channelNames.enumerated()), id: \.element) { index, channel in
                        if index > 0 { Hairline() }
                        SettingsToggleRow(
                            title: NotificationSettingsModel.channelName(channel),
                            isOn: channelBinding(channel)
                        )
                    }

                    if !notifications.channelNames.isEmpty { Hairline() }

                    SettingsRow("E-Mail-Abmeldung aufheben", subtitle: "Aktiviert den E-Mail-Versand nach einem Abmeldelink wieder") {
                        Button("Wieder einschalten") {
                            Task { await notifications.resubscribeEmail() }
                        }
                        .controlSize(.small)
                    }
                    .searchAnchor("notifications.resubscribe")
                }

                SettingsSection(
                    "Server-Ereignisse",
                    footer: "Der Server verschickt nur Benachrichtigungen für eingeschaltete Ereignisse."
                ) {
                    EmptyView()
                } content: {
                    if notifications.catalog.isEmpty {
                        Text(notifications.isLoading ? "Der Katalog wird geladen …"
                             : notifications.error != nil ? "Die Ereignisse konnten nicht geladen werden."
                             : "Der Server nennt derzeit keine Ereignisse.")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(Array(notifications.catalog.enumerated()), id: \.element.id) { index, event in
                            if index > 0 { Hairline() }
                            SettingsToggleRow(
                                title: event.label,
                                isOn: eventBinding(event.key)
                            )
                            .disabled(!notifications.isConfigurable(event.key))
                            .opacity(notifications.isConfigurable(event.key) ? 1 : 0.5)
                        }
                    }
                }

                SettingsSection(
                    "Registrierte Push-Geräte",
                    footer: "Geräte, die auf dem Server für mobile Push-Mitteilungen hinterlegt sind."
                ) {
                    Button("Aktualisieren") {
                        Task { await notifications.load() }
                    }
                    .controlSize(.small)
                    .disabled(notifications.isLoading)
                } content: {
                    if notifications.isLoading {
                        Text("Push-Geräte werden geladen …")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    } else if let error = notifications.devicesError {
                        Text("Push-Geräte konnten nicht geladen werden: \(error)")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    } else if !notifications.devicesLoaded {
                        Text("Push-Geräte wurden noch nicht geladen.")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    } else if notifications.devices.isEmpty {
                        Text("Keine Geräte für Server-Push registriert.")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    } else {
                        ForEach(Array(notifications.devices.enumerated()), id: \.element.id) { index, device in
                            if index > 0 { Hairline() }
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(device.name.isEmpty ? device.deviceID : device.name)
                                        .font(AppFont.subheading)
                                        .foregroundStyle(Palette.textPrimary)
                                    Text(device.platform)
                                        .font(AppFont.caption)
                                        .foregroundStyle(Palette.textTertiary)
                                }
                                Spacer(minLength: Space.s)
                                Button("Abmelden", role: .destructive) {
                                    pendingDelete = .pushDevice(device.deviceID)
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
        .task(id: app.accountGeneration) {
            guard app.hasCredentials, notifications.needsLoad else { return }
            await notifications.load()
        }
    }

    private var announcedFormatsText: String {
        switch announcedFormats.count {
        case 0: "Noch keins gewählt — ohne Auswahl werden keine neuen Folgen gemeldet"
        case 1: "1 Format aktiv"
        case let count: "\(count) Formate aktiv"
        }
    }

    private var announcedFormats: Set<Int> {
        NewEpisodeLogic.announced(notified: app.settings.notifiedMagazines, hidden: app.settings.hiddenMagazines)
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.notificationsOn },
            set: { value in
                apply { $0.notificationsOn = value }
                if value { Task { await watcher.refreshPermission() } }
            }
        )
    }

    private var liveNotificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.liveNotificationsOn },
            set: { value in
                apply { $0.liveNotificationsOn = value }
                if value { Task { await watcher.refreshPermission(); await watcher.checkLive() } }
            }
        )
    }

    private var chatNotificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.chatNotificationsOn },
            set: { value in
                apply { $0.chatNotificationsOn = value }
                if value { Task { await watcher.refreshPermission() } }
                Task { await live.settingsChanged() }
            }
        )
    }

    private func channelBinding(_ channel: String) -> Binding<Bool> {
        Binding(
            get: { notifications.isChannelOn(channel) },
            set: { value in Task { await notifications.setChannel(channel, enabled: value) } }
        )
    }

    private func eventBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { notifications.isEnabled(key) },
            set: { value in Task { await notifications.setEvent(key, enabled: value) } }
        )
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
