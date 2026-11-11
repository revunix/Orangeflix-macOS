import SwiftUI

/// Unified playback, Discord Rich Presence & livestream chat settings page,
/// complete with live interactive previews for Discord and the live chat.
struct SettingsPlaybackPage: View {
    @Binding var settingsError: String?

    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account
    @Environment(PlaybackCenter.self) private var playback

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsSection(
                "Wiedergabe",
                footer: "Gilt für Folgen und Rückblicke im Player. Livestreams wählen ihren Stream automatisch."
            ) {
                EmptyView()
            } content: {
                SettingsRow("Standard-Qualität", subtitle: "Bevorzugte Auflösung beim Start einer Folge") {
                    Picker("Qualität", selection: streamQualityBinding) {
                        ForEach(AppSettings.Quality.allCases, id: \.self) { quality in
                            Text(quality.shellTitle).tag(quality)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .searchAnchor("streaming.quality")
            }

            SettingsSection(
                "Discord Rich Presence",
                footer: "Zeigt auf deinem Discord-Profil in Echtzeit an, was du auf Orangeflix schaust – inklusive Cover, Zeitleiste und Kapitel."
            ) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(discordStatusColor)
                        .frame(width: 7, height: 7)
                    Text(playback.discord.status.label)
                        .font(AppFont.captionMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Palette.surfaceMuted, in: Capsule())
                .overlay { Capsule().strokeBorder(Palette.divider, lineWidth: 1) }
            } content: {
                HStack(alignment: .top, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        SettingsToggleRow(
                            title: "Aktuelle Wiedergabe zeigen",
                            subtitle: "Titel, Format, Kapitel & Live-Fortschritt",
                            isOn: discordEnabledBinding
                        )
                        .searchAnchor("streaming.discord")

                        Hairline()

                        SettingsToggleRow(
                            title: "Direktlink-Button zeigen",
                            subtitle: "Button „Folge öffnen“ bzw. „Livestream ansehen“",
                            isOn: discordButtonBinding
                        )
                        .disabled(!app.settings.discordRPCEnabled)
                        .opacity(app.settings.discordRPCEnabled ? 1 : 0.45)
                        .searchAnchor("streaming.discordButton")
                    }
                    .frame(maxWidth: .infinity)

                    discordPreviewCard
                        .frame(width: 248)
                        .opacity(app.settings.discordRPCEnabled ? 1 : 0.42)
                }
            }

            SettingsSection(
                "Livestream-Chat & Abstimmungen",
                footer: "Bei „Auf der Live-Seite wählen“ merkt sich Orangeflix deine letzte Einstellung direkt im Live-Fenster."
            ) {
                EmptyView()
            } content: {
                HStack(alignment: .top, spacing: Space.l) {
                    VStack(alignment: .leading, spacing: Space.m) {
                        SettingsToggleRow(
                            title: "Beim Öffnen einblenden",
                            isOn: liveChatOpenBinding
                        )
                        .searchAnchor("live.chatStart")

                        Hairline()

                        SettingsRow("Position") {
                            Picker("Position", selection: liveChatPositionBinding) {
                                Text("Auf der Live-Seite wählen").tag(AppSettings.LiveChatPosition.auto)
                                Text("Rechts neben dem Bild").tag(AppSettings.LiveChatPosition.side)
                                Text("Unter dem Bild").tag(AppSettings.LiveChatPosition.below)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .searchAnchor("live.chatPosition")

                        Hairline()

                        SettingsRow("Schriftgröße") {
                            Picker("Schriftgröße", selection: liveChatTextSizeBinding) {
                                Text("Klein").tag(AppSettings.LiveChatTextSize.small)
                                Text("Normal").tag(AppSettings.LiveChatTextSize.normal)
                                Text("Groß").tag(AppSettings.LiveChatTextSize.large)
                                Text("Sehr groß").tag(AppSettings.LiveChatTextSize.larger)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .searchAnchor("live.textSize")

                        Hairline()

                        SettingsToggleRow(
                            title: "Profilbilder zeigen",
                            isOn: liveChatAvatarsBinding
                        )
                        .searchAnchor("live.avatars")

                        Hairline()

                        SettingsToggleRow(
                            title: "Uhrzeit zeigen",
                            isOn: liveChatTimesBinding
                        )
                        .searchAnchor("live.times")

                        Hairline()

                        SettingsRow("Live-Abstimmungen") {
                            Picker("Anzeigen", selection: livePollsBinding) {
                                Text("Aufgeklappt").tag(AppSettings.LivePolls.expanded)
                                Text("Eingeklappt").tag(AppSettings.LivePolls.collapsed)
                                Text("Ausgeblendet").tag(AppSettings.LivePolls.hidden)
                            }
                            .labelsHidden()
                            .fixedSize()
                        }
                        .searchAnchor("live.polls")
                    }
                    .frame(maxWidth: .infinity)

                    liveChatPreviewCard
                        .frame(width: 248)
                }
            }
        }
        .task {
            playback.discord.probe(enabled: app.settings.discordRPCEnabled)
        }
    }

    // MARK: - Previews

    private var discordPreviewCard: some View {
        let current = playback.current
        let title = current?.title ?? "Aktuelle Folge"
        let subtitle = current?.detail ?? "Mediathek · Kapitel 2"
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("SCHAUT ORANGEFLIX")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Color(hex: "949BA4"))
                Spacer(minLength: 4)
                Text("Vorschau")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(Color(hex: "7FD69E"))
            }

            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Color(hex: "F19100"), Color(hex: "8A4500")],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    IrisColorMark()
                        .frame(width: 24, height: 24)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(Color(hex: "F2F3F5"))
                        .lineLimit(1)
                    Text(subtitle.isEmpty ? "Orangeflix for macOS" : subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Color(hex: "B5BAC1"))
                        .lineLimit(1)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color(hex: "2B2D31"))
                            Capsule()
                                .fill(.white)
                                .frame(width: geo.size.width * 0.42)
                        }
                    }
                    .frame(height: 3.5)
                    .padding(.top, 3)
                }
            }

            if app.settings.discordShowLinkButton {
                Text(current?.kind == .live ? "Livestream ansehen" : "Folge öffnen")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(hex: "F2F3F5"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(Color(hex: "2B2D31"), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .transition(.opacity.combined(with: .scale(scale: 0.96)))
            }
        }
        .padding(11)
        .background(Color(hex: "111214"), in: shape)
        .overlay { shape.strokeBorder(.white.opacity(0.09), lineWidth: 1) }
        .animation(.snappy(duration: 0.18), value: app.settings.discordShowLinkButton)
    }

    private var liveChatPreviewCard: some View {
        let scale = app.settings.liveChatTextSize.scale
        let showsAvatars = app.settings.liveChatAvatars
        let showsTimes = app.settings.liveChatTimes
        let polls = app.settings.livePolls
        let ownHandle = account.details?.chatname.isEmpty == false ? account.details!.chatname : "du"
        let shape = RoundedRectangle(cornerRadius: 11, style: .continuous)

        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text("LIVE-CHAT VORSCHAU")
                    .font(.system(size: 9.5, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(Palette.textTertiary)
                Spacer(minLength: 4)
                if polls == .collapsed {
                    BrandPill(text: "Abstimmung", color: Palette.accentText, background: Palette.accentSoft)
                }
            }

            if polls == .expanded {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Abstimmung · Beste Rubrik?")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Palette.textPrimary)
                    HStack(spacing: 6) {
                        Capsule()
                            .fill(Palette.accent.opacity(0.32))
                            .frame(height: 6)
                            .overlay(alignment: .leading) {
                                Capsule().fill(Palette.accent).frame(width: 88, height: 6)
                            }
                        Text("64 %")
                            .font(AppFont.micro.monospacedDigit())
                            .foregroundStyle(Palette.accentText)
                    }
                }
                .padding(8)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Palette.divider, lineWidth: 1)
                }
            }

            previewChatLine(
                initial: "M",
                author: "mara_k",
                text: "Ton und Bild sind heute gestochen scharf!",
                time: "20:15",
                scale: scale,
                showsAvatar: showsAvatars,
                showsTime: showsTimes,
                own: false
            )

            previewChatLine(
                initial: String(ownHandle.prefix(1)).uppercased(),
                author: ownHandle,
                text: "Direkt im PiP weitergeschaut.",
                time: "20:16",
                scale: scale,
                showsAvatar: showsAvatars,
                showsTime: showsTimes,
                own: true
            )
        }
        .padding(11)
        .background(Palette.surfaceMuted, in: shape)
        .overlay { shape.strokeBorder(Palette.divider, lineWidth: 1) }
        .animation(.snappy(duration: 0.18), value: app.settings.liveChatTextSize)
        .animation(.snappy(duration: 0.18), value: showsAvatars)
        .animation(.snappy(duration: 0.18), value: showsTimes)
        .animation(.snappy(duration: 0.18), value: polls)
    }

    private func previewChatLine(
        initial: String,
        author: String,
        text: String,
        time: String,
        scale: CGFloat,
        showsAvatar: Bool,
        showsTime: Bool,
        own: Bool
    ) -> some View {
        HStack(alignment: .top, spacing: 7) {
            if showsAvatar {
                Text(initial)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(own ? Palette.accentText : Palette.textSecondary)
                    .frame(width: 21, height: 21)
                    .background(own ? Palette.accentSoft : Palette.surface, in: Circle())
                    .overlay { Circle().strokeBorder(Palette.divider, lineWidth: 1) }
            }

            VStack(alignment: .leading, spacing: 1.5) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(author)
                        .font(.system(size: 11.5 * scale, weight: .semibold))
                        .foregroundStyle(own ? Palette.accentText : Palette.textPrimary)
                        .lineLimit(1)
                    if showsTime {
                        Text(time)
                            .font(.system(size: 10 * scale).monospacedDigit())
                            .foregroundStyle(Palette.textTertiary)
                    }
                }
                Text(text)
                    .font(.system(size: 12 * scale))
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Bindings

    private var discordStatusColor: Color {
        switch playback.discord.status {
        case .connected: Palette.success
        case .idle: Palette.accent
        case .disabled: Palette.textTertiary
        case .waitingForDiscord: Palette.warning
        case .rejected: Palette.danger
        }
    }

    private var streamQualityBinding: Binding<AppSettings.Quality> {
        Binding(get: { app.settings.streamQuality }, set: { value in apply { $0.streamQuality = value } })
    }

    private var discordEnabledBinding: Binding<Bool> {
        Binding(
            get: { app.settings.discordRPCEnabled },
            set: { value in
                apply { $0.discordRPCEnabled = value }
                playback.syncDiscordPresence(force: true)
            }
        )
    }

    private var discordButtonBinding: Binding<Bool> {
        Binding(
            get: { app.settings.discordShowLinkButton },
            set: { value in
                apply { $0.discordShowLinkButton = value }
                playback.syncDiscordPresence(force: true)
            }
        )
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
