import SwiftUI

/// The Konto page. Without a login it only says so; the login itself lives
/// in the main window.
struct SettingsAccountPage: View {
    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account
    @Environment(SessionModel.self) private var sessions

    var body: some View {
        if app.hasCredentials {
            signedIn
        } else {
            Section {
                Text("Nicht angemeldet")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Die Anmeldung erfolgt im Hauptfenster.")
            }
        }
    }

    private var signedIn: some View {
        let facts = account.details.map { AccountFacts(profile: $0, progress: account.progress) }
        return Group {
            Section {
                accountHeader(facts)
                LabeledContent("Benutzer") {
                    Text(app.username)
                        .textSelection(.enabled)
                }
                .searchAnchor("account.user")
                if let value = facts?.chatname { infoRow("Chatname", value, anchor: "account.chatname") }
                if let value = facts?.displayName { infoRow("Anzeigename", value, anchor: "account.displayName") }
                if let value = facts?.memberSince { infoRow("Mitglied seit", value, anchor: "account.created") }
                if let value = facts?.lastLogin { infoRow("Letzte Anmeldung", value, anchor: "account.lastLogin") }
                if let value = facts?.feedSeen { infoRow("Feed zuletzt gesehen", value, anchor: "account.feedSeen") }
                if let facts { infoRow("Zwei-Faktor-Anmeldung", facts.twoFactor, anchor: "account.totp") }
                Button("Abmelden …", role: .destructive) { account.confirmSignOut() }
                    .disabled(account.isSigningOut)
                    .searchAnchor("account.signOut")
            } header: {
                Text("Anmeldung")
            } footer: {
                Text("Abmelden beendet die Sitzung und entfernt E-Mail und Passwort von diesem Mac.")
            }

            if let recovery = app.sessionRecovery {
                Section {
                    if sessions.sessions.isEmpty {
                        Text(sessions.isLoading ? "Die Sitzungen werden geladen …" : "Die Sitzungen konnten nicht gelesen werden.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(sessions.sessions, id: \.id) { session in
                        sessionRow(session, recovery: recovery)
                    }
                    Button("Neu laden") {
                        Task { await sessions.load(recovery: recovery) }
                    }
                    .disabled(sessions.isLoading)
                } header: {
                    Text("Sitzungen")
                } footer: {
                    Text("Das Konto hat zu viele offene Sitzungen. Beende eine, um dich wieder anzumelden.")
                }
            }

            Section("Abo") {
                LabeledContent("Status") {
                    Text(statusText).foregroundStyle(statusColor)
                }
                .searchAnchor("account.status")
                if let facts { infoRow("Zugang", facts.hasAccess, anchor: "account.access") }
                if let value = facts?.accessType { infoRow("Zugangsart", value, anchor: "account.accessType") }
                if let value = facts?.plan { infoRow("Abo", value, anchor: "account.plan") }
                LabeledContent("Stufe") { Text(tierText) }
                    .searchAnchor("account.tier")
                LabeledContent("Läuft ab") { Text(expiryText) }
                    .searchAnchor("account.expiry")
                if let value = facts?.nextPayment { infoRow("Nächste Zahlung", value, anchor: "account.nextPayment") }
                if let value = facts?.amount { infoRow("Betrag", value, anchor: "account.amount") }
                if let value = facts?.computedAmount {
                    infoRow("Berechneter Betrag", value, anchor: "account.computedAmount")
                }
                Button(account.isLoading ? "Prüfe …" : "Neu prüfen") {
                    Task { await account.load() }
                }
                .disabled(account.isLoading)
                .searchAnchor("account.refresh")
            }

            if let facts {
                Section {
                    infoRow("Angefangene Folgen", facts.startedCount.map(String.init) ?? "—", anchor: "account.started")
                    infoRow("Zu Ende gesehen", facts.finishedCount.map(String.init) ?? "—", anchor: "account.finished")
                    if let value = facts.lastWatched { infoRow("Zuletzt gesehen", value, anchor: "account.lastWatched") }
                    infoRow("Formate in der Bibliothek", "\(account.library.count)", anchor: "account.library")
                    infoRow("Neue Folgen", "\(account.newEpisodeCount)", anchor: "account.newEpisodes")
                } header: {
                    Text("Nutzung")
                } footer: {
                    Text("„Zu Ende gesehen“ zählt Folgen ab 90 Prozent. Bibliothek und neue Folgen stammen aus der Bibliothek der App.")
                }
            }
        }
        .task {
            await account.refreshLibrary(minimumInterval: 30)
            if account.details == nil, !account.isLoading { await account.load() }
        }
    }

    /// The picture and the name of the account above its rows.
    private func accountHeader(_ facts: AccountFacts?) -> some View {
        HStack(spacing: Space.m) {
            Group {
                if let image = account.avatarImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill")
                        .resizable()
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(facts?.chatname ?? (app.username.isEmpty ? "nicht angemeldet" : app.username))
                    .font(AppFont.heading)
                Text(statusText)
                    .font(AppFont.caption)
                    .foregroundStyle(statusColor)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, Space.xxs)
    }

    /// A row of the Konto page: a label and a value that can be selected
    /// and copied.
    private func infoRow(_ label: String, _ value: String, anchor: String) -> some View {
        LabeledContent(label) {
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
        .searchAnchor(anchor)
    }

    /// One session of the account with the button that ends it.
    private func sessionRow(_ session: AccountSession, recovery: SessionRecovery) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.label)
                    .font(AppFont.body)
                Text(session.ip ?? session.client?.platform ?? "")
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: Space.s)
            if session.current {
                Text("diese Sitzung")
                    .font(AppFont.caption)
                    .foregroundStyle(.tertiary)
            } else {
                Button("Beenden") {
                    Task { await sessions.revoke(session.id, recovery: recovery) }
                }
            }
        }
    }

    /// The state of the subscription in one word; the tier and the date
    /// stand in the rows below.
    private var statusText: String {
        switch account.status {
        case .active: account.profile?.lifetime == true ? "unbegrenzt" : "aktiv"
        case .expired: "abgelaufen"
        case .totpRequired: "2FA-Code nötig"
        case .failed: "Anmeldung fehlgeschlagen"
        case .loading: "wird geprüft …"
        case .unknown: "unbekannt"
        }
    }

    private var statusColor: Color {
        switch account.status {
        case .active: Palette.success
        case .expired, .failed, .totpRequired: Palette.danger
        case .loading, .unknown: Palette.textSecondary
        }
    }

    private var tierText: String {
        guard let profile = account.profile, profile.tier > 0 else { return "—" }
        return "Stufe \(profile.tier)"
    }

    private var expiryText: String {
        guard let profile = account.profile else { return "—" }
        if profile.lifetime { return "unbegrenzt" }
        guard let date = profile.expiresAt else { return "unbekannt" }
        return AppFormat.day(date)
    }
}
