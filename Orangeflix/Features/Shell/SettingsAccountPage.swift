import AppKit
import SwiftUI

/// Unified Konto, Profil & Sharing page with three sub-tabs:
/// 1. Übersicht — Hero card, membership & usage tiles, active sessions
/// 2. Angaben & Feed — Display/chat name, feed style, shipping/birthday/credits, legal & feed filter
/// 3. Sharing-Links — Monthly quota, generated links & public code inspector
struct SettingsAccountPage: View {
    @Binding var subTab: AccountSubTab
    @Binding var pendingDelete: SettingsDelete?

    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account
    @Environment(ProfileModel.self) private var profile
    @Environment(SharingModel.self) private var sharing
    @Environment(SessionModel.self) private var sessions
    @Environment(BrowseModel.self) private var browse

    @State private var name = ""
    @State private var chatname = ""
    @State private var namesAccount: Int?
    @State private var profileSheet: ProfileSheet?
    @State private var shareCode = ""
    @State private var shareCheck: String?

    private enum ProfileSheet: Identifiable {
        case address, birthday, credits
        var id: String {
            switch self {
            case .address: "address"
            case .birthday: "birthday"
            case .credits: "credits"
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if !app.hasCredentials {
                signedOutView
            } else {
                switch subTab {
                case .overview:
                    overviewTab
                case .details:
                    detailsTab
                case .sharing:
                    sharingTab
                }
            }
        }
        .task(id: app.accountGeneration) {
            guard app.hasCredentials else { return }
            await account.refreshLibrary(minimumInterval: 30)
            if account.details == nil, !account.isLoading { await account.load() }
            if profile.needsLoad { await profile.load() }
            if sharing.needsLoad { await sharing.load() }
            syncNameFields()
        }
        .onChange(of: profile.savedName) { _, _ in syncNameFields() }
        .onChange(of: profile.savedChatname) { _, _ in syncNameFields() }
        .sheet(item: $profileSheet) { item in
            switch item {
            case .address:
                AddressSheet { input in Task { await profile.saveAddress(input) } }
            case .birthday:
                BirthdaySheet { input in Task { await profile.saveBirthday(input) } }
            case .credits:
                CreditsSheet { input in Task { await profile.saveCredits(input) } }
            }
        }
    }

    // MARK: - Signed out

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            SettingsSection(
                "Anmeldung",
                footer: "Melde dich im Hauptfenster von Orangeflix an, um Mitgliedschaft, Profilangaben und eigene Sharing-Links zu verwalten."
            ) {
                HStack(spacing: Space.m) {
                    ZStack {
                        Circle().fill(Palette.surfaceMuted)
                        Image(systemName: "person.crop.circle.badge.exclamationmark")
                            .font(.system(size: 22))
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .frame(width: 48, height: 48)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Nicht angemeldet")
                            .font(AppFont.heading)
                            .foregroundStyle(Palette.textPrimary)
                        Text("Einen fremden Sharing-Code kannst du auch ohne Anmeldung unten prüfen.")
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }

            codeInspectorSection
        }
    }

    // MARK: - Tab 1: Übersicht

    private var overviewTab: some View {
        let facts = account.details.map { AccountFacts(profile: $0, progress: account.progress) }
        return VStack(alignment: .leading, spacing: Space.xl) {
            heroAccountCard(facts)

            if let warning = account.profile?.expiryWarning(), !warning.isEmpty {
                ProfileNotice(symbol: "clock.badge.exclamationmark", text: warning)
            }

            if let recovery = app.sessionRecovery {
                sessionsSection(recovery: recovery)
            }

            HStack(alignment: .top, spacing: Space.l) {
                membershipCard(facts)
                usageCard(facts)
            }
        }
    }

    private func heroAccountCard(_ facts: AccountFacts?) -> some View {
        let shape = RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        let primaryName = facts?.displayName ?? facts?.chatname ?? (app.username.isEmpty ? "Angemeldet" : app.username)
        return VStack(alignment: .leading, spacing: Space.m) {
            HStack(alignment: .center, spacing: Space.l) {
                Group {
                    if let image = account.avatarImage {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack {
                            Circle().fill(Palette.accentSoft)
                            Image(systemName: "person.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(Palette.accentText)
                        }
                    }
                }
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay {
                    Circle().strokeBorder(Palette.accent.opacity(0.5), lineWidth: 1.5)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: Space.s) {
                        Text(primaryName)
                            .font(AppFont.displaySmall)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        if let facts {
                            BrandPill(
                                text: facts.profile.hasTotp ? "2FA aktiv" : "Ohne 2FA",
                                color: facts.profile.hasTotp ? Palette.success : Palette.textSecondary,
                                background: facts.profile.hasTotp ? Palette.successSoft : Palette.surfaceMuted
                            )
                            .searchAnchor("account.totp")
                        }
                    }

                    Text(heroSubtitle(facts))
                        .font(AppFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                        .lineLimit(2)
                }

                Spacer(minLength: Space.s)

                HStack(spacing: Space.s) {
                    Button("Namen ändern …") {
                        withAnimation(.snappy(duration: 0.18)) { subTab = .details }
                    }
                    .controlSize(.small)

                    Button("Abmelden …", role: .destructive) {
                        account.confirmSignOut()
                    }
                    .controlSize(.small)
                    .disabled(account.isSigningOut)
                    .searchAnchor("account.signOut")
                }
            }
            .searchAnchor("account.user")

            if let created = facts?.memberSince, let login = facts?.lastLogin {
                Hairline()
                HStack(spacing: Space.l) {
                    Label("Mitglied seit \(created)", systemImage: "calendar")
                    Label("Letzte Anmeldung \(login)", systemImage: "clock")
                    Spacer(minLength: 0)
                }
                .font(AppFont.caption)
                .foregroundStyle(Palette.textSecondary)
            }
        }
        .padding(Space.l)
        .background {
            shape.fill(
                LinearGradient(
                    colors: [Palette.accentSoft.opacity(0.65), Palette.surface],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        .overlay {
            shape.strokeBorder(Palette.accent.opacity(0.28), lineWidth: 1)
        }
    }

    private func heroSubtitle(_ facts: AccountFacts?) -> String {
        var parts: [String] = []
        if let chat = facts?.chatname { parts.append("@\(chat)") }
        if !app.username.isEmpty { parts.append(app.username) }
        return parts.joined(separator: " · ")
    }

    private func membershipCard(_ facts: AccountFacts?) -> some View {
        SettingsSection("Mitgliedschaft") {
            BrandPill(text: statusText, color: statusColor, background: statusBackground)
        } content: {
            VStack(spacing: Space.s) {
                kvRow("Tarif", tariffSummary(facts))
                if let amount = facts?.amount {
                    kvRow("Betrag", amount)
                }
                if let computed = facts?.computedAmount {
                    kvRow("Berechnet", computed)
                }
                if let next = facts?.nextPayment {
                    kvRow("Nächste Zahlung", next)
                }
                kvRow("Gültig bis", expiryText)
            }
            .searchAnchor("account.status")

            Hairline()

            HStack {
                Text("Abmelden entfernt die Zugangsdaten von diesem Mac.")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(2)
                Spacer(minLength: Space.s)
                Button(account.isLoading ? "Prüfe …" : "Neu prüfen") {
                    Task { await account.load() }
                }
                .controlSize(.small)
                .disabled(account.isLoading)
                .searchAnchor("account.refresh")
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func tariffSummary(_ facts: AccountFacts?) -> String {
        var parts: [String] = []
        if tierText != "—" { parts.append(tierText) }
        if let plan = facts?.plan {
            parts.append(plan)
        } else if let accessType = facts?.accessType {
            parts.append(accessType)
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }

    private func usageCard(_ facts: AccountFacts?) -> some View {
        SettingsSection("Nutzung & Bibliothek", footer: "Folgen ab 90 % Fortschritt zählen als zu Ende gesehen.") {
            EmptyView()
        } content: {
            HStack(spacing: Space.s) {
                statTile(value: facts?.finishedCount.map(String.init) ?? "—", label: "Gesehen")
                statTile(value: facts?.startedCount.map(String.init) ?? "—", label: "Angefangen")
                statTile(value: "\(account.library.count)", label: "Bibliothek")
            }
            .searchAnchor("account.usage")

            Hairline()

            VStack(spacing: Space.s) {
                kvRow("Neue Folgen", "\(account.newEpisodeCount)")
                if let last = facts?.lastWatched {
                    kvRow("Zuletzt geschaut", last)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private func statTile(value: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.system(size: 19, weight: .semibold).monospacedDigit())
                .foregroundStyle(Palette.textPrimary)
                .lineLimit(1)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(Palette.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(Palette.divider, lineWidth: 1)
        }
    }

    private func kvRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(label)
                .font(AppFont.bodySmall)
                .foregroundStyle(Palette.textSecondary)
            Spacer(minLength: Space.s)
            Text(value)
                .font(AppFont.bodySmall.monospacedDigit())
                .fontWeight(.medium)
                .foregroundStyle(Palette.textPrimary)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }

    private func sessionsSection(recovery: SessionRecovery) -> some View {
        SettingsSection(
            "Offene Sitzungen",
            footer: "Das Konto hat zu viele offene Sitzungen. Beende eine Sitzung, um dich wieder anzumelden."
        ) {
            Button("Neu laden") {
                Task { await sessions.load(recovery: recovery) }
            }
            .controlSize(.small)
            .disabled(sessions.isLoading)
        } content: {
            if sessions.sessions.isEmpty {
                Text(sessions.isLoading ? "Die Sitzungen werden geladen …" : "Die Sitzungen konnten nicht gelesen werden.")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
            } else {
                ForEach(Array(sessions.sessions.enumerated()), id: \.element.id) { index, session in
                    if index > 0 { Hairline() }
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.label)
                                .font(AppFont.body)
                            Text(session.ip ?? session.client?.platform ?? "")
                                .font(AppFont.caption)
                                .foregroundStyle(Palette.textTertiary)
                        }
                        Spacer(minLength: Space.s)
                        if session.current {
                            BrandPill(text: "Diese Sitzung", color: Palette.success, background: Palette.successSoft)
                        } else {
                            Button("Beenden") {
                                Task { await sessions.revoke(session.id, recovery: recovery) }
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Tab 2: Angaben & Feed

    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let error = profile.error {
                ProfileNotice(symbol: "exclamationmark.triangle.fill", text: error,
                              tint: Palette.danger, background: Palette.dangerSoft)
            }

            if profile.needsLegalConfirmation {
                ProfileNotice(
                    symbol: "exclamationmark.circle.fill",
                    text: profile.openActionTitles.isEmpty
                        ? "Der Server verlangt noch eine rechtliche Bestätigung."
                        : "Der Server verlangt noch: \(profile.openActionTitles.joined(separator: ", "))."
                )
            }

            SettingsSection(
                "Namen & Feed-Darstellung",
                footer: "Der Chatname lässt sich nur alle 24 Stunden ändern und muss frei sein."
            ) {
                Button("Änderungen speichern") {
                    Task { await saveProfileNames() }
                }
                .controlSize(.small)
                .disabled(profile.isSaving || !profileNamesChanged)
                .searchAnchor("profile.save")
            } content: {
                SettingsRow("Anzeigename", subtitle: "Öffentlicher Name im Konto") {
                    TextField("Anzeigename", text: $name)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                .searchAnchor("profile.name")

                Hairline()

                SettingsRow("Chatname", subtitle: "Nutzername im Livestream-Chat") {
                    TextField("Chatname", text: $chatname)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 220)
                }
                .searchAnchor("profile.chatname")

                Hairline()

                SettingsRow("Stil des Feeds", subtitle: "Darstellungsgröße auf orangeflix.de") {
                    Picker("Stil des Feeds", selection: feedStyleBinding) {
                        ForEach(1...3, id: \.self) { style in
                            Text(ProfileModel.feedStyleName(style)).tag(style)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                .searchAnchor("profile.feedStyle")

                Hairline()

                SettingsRow(
                    "Feed-Lesestand",
                    subtitle: profile.marker?.date.map { "Zuletzt gesehen am \(AppFormat.dateTime($0))" } ?? "Noch kein Zeitstempel"
                ) {
                    Button("Jetzt als gesehen markieren") {
                        Task { await profile.markFeedSeen() }
                    }
                    .controlSize(.small)
                }
                .searchAnchor("profile.markSeen")
            }

            SettingsSection(
                "Hinterlegte Angaben & Rechtliches",
                footer: "Persönliche Angaben bleiben auf dem Server gespeichert; die App sieht nur, ob sie hinterlegt sind."
            ) {
                EmptyView()
            } content: {
                optionalEntryRow(
                    symbol: "shippingbox",
                    title: "Lieferadresse",
                    subtitle: "Für Versandaktionen des Kontos",
                    state: profile.optionalInfo.addressCollected ? "Hinterlegt" : "Offen",
                    isSet: profile.optionalInfo.addressCollected,
                    primaryTitle: profile.optionalInfo.addressCollected ? "Ändern …" : "Eintragen …",
                    onPrimary: { profileSheet = .address },
                    onDelete: profile.optionalInfo.addressCollected ? { pendingDelete = .address } : nil
                )
                .searchAnchor("profile.address")

                Hairline()

                optionalEntryRow(
                    symbol: "birthday.cake",
                    title: "Geburtsdatum",
                    subtitle: "Tag und Monat genügen, das Jahr ist optional",
                    state: profile.optionalInfo.birthdayCollected ? "Hinterlegt" : "Offen",
                    isSet: profile.optionalInfo.birthdayCollected,
                    primaryTitle: profile.optionalInfo.birthdayCollected ? "Ändern …" : "Eintragen …",
                    onPrimary: { profileSheet = .birthday },
                    onDelete: profile.optionalInfo.birthdayCollected ? { pendingDelete = .birthday } : nil
                )
                .searchAnchor("profile.birthday")

                Hairline()

                optionalEntryRow(
                    symbol: "signature",
                    title: "Credits-Nennung",
                    subtitle: "Name und Format für den Abspann",
                    state: profile.optionalInfo.creditsCollected ? "Hinterlegt" : "Offen",
                    isSet: profile.optionalInfo.creditsCollected,
                    primaryTitle: profile.optionalInfo.creditsCollected ? "Ändern …" : "Eintragen …",
                    onPrimary: { profileSheet = .credits },
                    onDelete: profile.optionalInfo.creditsCollected ? { pendingDelete = .credits } : nil
                )
                .searchAnchor("profile.credits")

                Hairline()

                legalEntryRow(
                    symbol: "hand.raised",
                    title: "Datenschutzbestimmungen",
                    confirmed: profile.privacyConfirmed,
                    onConfirm: { Task { await profile.acceptPrivacy() } },
                    url: SettingsLegal.privacy
                )
                .searchAnchor("profile.privacy")

                Hairline()

                legalEntryRow(
                    symbol: "doc.text",
                    title: "Allgemeine Geschäftsbedingungen",
                    confirmed: profile.agbConfirmed,
                    onConfirm: { Task { await profile.acceptAGB() } },
                    url: SettingsLegal.terms
                )
                .searchAnchor("profile.agb")
            }

            SettingsSection(
                "Feed-Filter",
                footer: "Ausgeschaltete Kategorien werden im Haupt-Feed ausgeblendet."
            ) {
                if !profile.exclusionFilter.isEmpty {
                    Button("Filter leeren", role: .destructive) { pendingDelete = .feedFilter }
                        .controlSize(.small)
                }
            } content: {
                if categoryFormats.isEmpty {
                    Text("Die Kategorien stehen bereit, sobald die Mediathek geladen wurde.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(Array(categoryFormats.enumerated()), id: \.element.id) { index, format in
                        if index > 0 { Hairline() }
                        DisclosureGroup(format.title) {
                            VStack(alignment: .leading, spacing: Space.s) {
                                ForEach(format.categories) { category in
                                    SettingsToggleRow(
                                        title: category.title,
                                        isOn: exclusionBinding(format.id, category.id)
                                    )
                                }
                            }
                            .padding(.top, Space.s)
                        }
                    }
                }
            }
            .searchAnchor("profile.feedFilter")
        }
    }

    private func optionalEntryRow(
        symbol: String,
        title: String,
        subtitle: String,
        state: String,
        isSet: Bool,
        primaryTitle: String,
        onPrimary: @escaping () -> Void,
        onDelete: (() -> Void)?
    ) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isSet ? Palette.success : Palette.textSecondary)
                .frame(width: 28, height: 28)
                .background(isSet ? Palette.successSoft : Palette.surfaceMuted, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(title)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                    BrandPill(
                        text: state,
                        color: isSet ? Palette.success : Palette.textSecondary,
                        background: isSet ? Palette.successSoft : Palette.surfaceMuted
                    )
                }
                Text(subtitle)
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Space.s)

            HStack(spacing: Space.xs) {
                Button(primaryTitle, action: onPrimary)
                    .controlSize(.small)
                if let onDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .controlSize(.small)
                    .help("Hinterlegten Wert löschen")
                }
            }
            .disabled(profile.isSaving)
        }
    }

    private func legalEntryRow(
        symbol: String,
        title: String,
        confirmed: Bool,
        onConfirm: @escaping () -> Void,
        url: URL
    ) -> some View {
        HStack(alignment: .center, spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(confirmed ? Palette.success : Palette.warning)
                .frame(width: 28, height: 28)
                .background(confirmed ? Palette.successSoft : Palette.warningSoft, in: Circle())

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Space.xs) {
                    Text(title)
                        .font(AppFont.subheading)
                        .foregroundStyle(Palette.textPrimary)
                    BrandPill(
                        text: confirmed ? "Bestätigt" : "Offen",
                        color: confirmed ? Palette.success : Palette.warning,
                        background: confirmed ? Palette.successSoft : Palette.warningSoft
                    )
                }
                Text("Aktuelle Fassung auf orangeflix.de")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }

            Spacer(minLength: Space.s)

            HStack(spacing: Space.xs) {
                Button(confirmed ? "Erneut bestätigen" : "Bestätigen", action: onConfirm)
                    .controlSize(.small)
                    .disabled(profile.isSaving)
                Button {
                    NSWorkspace.shared.open(url)
                } label: {
                    Label("Lesen", systemImage: "arrow.up.right")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Tab 3: Sharing-Links

    private var sharingTab: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let error = sharing.error {
                ProfileNotice(symbol: "exclamationmark.triangle.fill", text: error,
                              tint: Palette.danger, background: Palette.dangerSoft)
            }

            if let link = sharing.freshLink {
                SettingsSection("Neu erstellter Link", footer: "Begrenzt auf \(link.accessLimit) Aufrufe.") {
                    Button("Ausblenden") { sharing.dismissFreshLink() }
                        .controlSize(.small)
                } content: {
                    HStack(spacing: Space.m) {
                        Text(link.url.isEmpty ? link.code : link.url)
                            .font(AppFont.bodySmall.monospaced())
                            .foregroundStyle(Palette.textPrimary)
                            .textSelection(.enabled)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: Space.s)
                        Button("Kopieren", systemImage: "doc.on.doc") {
                            AppFormat.copy(link.url.isEmpty ? link.code : link.url)
                        }
                        .controlSize(.small)
                    }
                }
            }

            SettingsSection(
                "Aktive Sharing-Links",
                footer: "Jeder Link erlaubt eine begrenzte Zahl von Aufrufen. Bereits genutzte Links lassen sich nicht mehr beenden."
            ) {
                HStack(spacing: Space.s) {
                    BrandPill(text: sharing.quotaText, color: Palette.accentText, background: Palette.accentSoft)
                        .searchAnchor("sharing.quota")
                    Button("Neu laden") { Task { await sharing.load() } }
                        .controlSize(.small)
                        .disabled(sharing.isLoading)
                        .searchAnchor("sharing.reload")
                }
            } content: {
                if sharing.links.isEmpty {
                    Text(sharing.isLoading ? "Die Links werden geladen …"
                         : sharing.error != nil ? "Die Links konnten nicht geladen werden."
                         : "Noch keine Sharing-Links erstellt. Du kannst Folgen über das Teilen-Menü einer Episode freigeben.")
                        .font(AppFont.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                } else {
                    ForEach(Array(sharing.links.enumerated()), id: \.element.code) { index, link in
                        if index > 0 { Hairline() }
                        HStack(alignment: .center, spacing: Space.m) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: Space.xs) {
                                    Text("Folge \(link.clipId)")
                                        .font(AppFont.subheading)
                                        .foregroundStyle(Palette.textPrimary)
                                    BrandPill(
                                        text: link.unlimited ? "Unbegrenzt" : (link.remaining.map { "\($0) übrig" } ?? "—"),
                                        color: Palette.textSecondary,
                                        background: Palette.surfaceMuted
                                    )
                                }
                                Text(link.createdDate.map { "Angelegt am \(AppFormat.day($0))" } ?? "Unbenutzter Link")
                                    .font(AppFont.caption)
                                    .foregroundStyle(Palette.textTertiary)
                            }
                            Spacer(minLength: Space.s)
                            HStack(spacing: Space.xs) {
                                Button("Code kopieren") { AppFormat.copy(link.code) }
                                    .controlSize(.small)
                                Button("Beenden", role: .destructive) { pendingDelete = .sharingLink(link.code) }
                                    .controlSize(.small)
                                    .disabled(!link.isRevocable)
                            }
                        }
                    }
                }
            }

            codeInspectorSection
        }
    }

    private var codeInspectorSection: some View {
        SettingsSection(
            "Link-Code prüfen",
            footer: "Prüft die Gültigkeit und verbleibenden Aufrufe eines Sharing-Codes."
        ) {
            EmptyView()
        } content: {
            HStack(spacing: Space.s) {
                TextField("Code", text: $shareCode, prompt: Text("Sharing-Code eingeben …"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        guard !shareCode.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                        Task { shareCheck = await sharing.inspect(code: shareCode) }
                    }
                Button("Code prüfen") {
                    Task { shareCheck = await sharing.inspect(code: shareCode) }
                }
                .disabled(shareCode.trimmingCharacters(in: .whitespaces).isEmpty)
                .searchAnchor("sharing.check")
            }
            if let shareCheck {
                Text(shareCheck)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Helpers

    private func syncNameFields() {
        if namesAccount != app.accountGeneration {
            namesAccount = app.accountGeneration
            name = ""
            chatname = ""
        }
        if name.isEmpty { name = profile.savedName }
        if chatname.isEmpty { chatname = profile.savedChatname }
    }

    private func saveProfileNames() async {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        if !trimmedName.isEmpty, trimmedName != profile.savedName {
            await profile.setName(trimmedName)
        }
        let trimmedChatname = chatname.trimmingCharacters(in: .whitespaces)
        if !trimmedChatname.isEmpty, trimmedChatname != profile.savedChatname {
            await profile.setChatname(trimmedChatname)
        }
    }

    private var profileNamesChanged: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedChatname = chatname.trimmingCharacters(in: .whitespaces)
        let nameChanged = !trimmedName.isEmpty && trimmedName != profile.savedName
        let chatChanged = !trimmedChatname.isEmpty && trimmedChatname != profile.savedChatname
        return nameChanged || chatChanged
    }

    private var feedStyleBinding: Binding<Int> {
        Binding(
            get: { profile.preferences?.feedStyle ?? 1 },
            set: { value in Task { await profile.setFeedStyle(value) } }
        )
    }

    private struct CategoryFormat: Identifiable {
        let id: Int
        let title: String
        let categories: [Category]
    }

    private struct Category: Identifiable {
        let id: Int
        let title: String
    }

    private var categoryFormats: [CategoryFormat] {
        browse.knownCategories
            .map { pid, categories in
                CategoryFormat(
                    id: pid,
                    title: browse.formats.first { $0.pid == pid }?.title ?? "Format \(pid)",
                    categories: categories
                        .sorted { $0.key < $1.key }
                        .map { Category(id: $0.key, title: $0.value) }
                )
            }
            .filter { !$0.categories.isEmpty }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    private func exclusionBinding(_ pid: Int, _ subpid: Int) -> Binding<Bool> {
        Binding(
            get: { profile.exclusionFilter[pid]?.contains(subpid) ?? false },
            set: { value in Task { await profile.setCategory(subpid, of: pid, excluded: value) } }
        )
    }

    private var statusText: String {
        switch account.status {
        case .active: account.profile?.lifetime == true ? "Dauerzugang" : "Aktiv"
        case .expired: "Abgelaufen"
        case .totpRequired: "2FA-Code nötig"
        case .failed: "Fehlgeschlagen"
        case .loading: "Wird geprüft …"
        case .unknown: "Unbekannt"
        }
    }

    private var statusColor: Color {
        switch account.status {
        case .active: Palette.success
        case .expired, .failed, .totpRequired: Palette.danger
        case .loading, .unknown: Palette.textSecondary
        }
    }

    private var statusBackground: Color {
        switch account.status {
        case .active: Palette.successSoft
        case .expired, .failed, .totpRequired: Palette.dangerSoft
        case .loading, .unknown: Palette.surfaceMuted
        }
    }

    private var tierText: String {
        guard let profile = account.profile, profile.tier > 0 else { return "—" }
        return "Stufe \(profile.tier)"
    }

    private var expiryText: String {
        guard let profile = account.profile else { return "—" }
        if profile.lifetime { return "Unbegrenzt" }
        guard let date = profile.expiresAt else { return "Unbekannt" }
        return AppFormat.day(date)
    }
}
