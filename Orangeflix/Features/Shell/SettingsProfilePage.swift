import AppKit
import SwiftUI

/// The data of the account: the name, the address, the birthday, the
/// credits and the legal confirmations.
struct SettingsProfilePage: View {
    @Binding var pendingDelete: SettingsDelete?

    @Environment(AppModel.self) private var app
    @Environment(ProfileModel.self) private var profile
    @Environment(BrowseModel.self) private var browse

    /// The name the account shows.
    @State private var name = ""
    /// The name in the chat.
    @State private var chatname = ""
    /// The account the two fields were filled for; another account fills
    /// them again.
    @State private var namesAccount: Int?
    /// The sheet of the profile page; only one stands open at a time.
    @State private var profileSheet: ProfileSheet?

    /// The sheets of the profile page.
    private enum ProfileSheet: Identifiable {
        case address
        case birthday
        case credits

        var id: String {
            switch self {
            case .address: "address"
            case .birthday: "birthday"
            case .credits: "credits"
            }
        }
    }

    var body: some View {
        Group {
            if !app.hasCredentials {
                Section {
                    Text("Nicht angemeldet")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Die Anmeldung erfolgt im Hauptfenster.")
                }
            } else {
                if let error = profile.error {
                    Section {
                        ProfileNotice(symbol: "exclamationmark.triangle.fill", text: error,
                                      tint: Palette.danger, background: Palette.dangerSoft)
                    }
                }

                Section {
                    TextField("Anzeigename", text: $name)
                        .searchAnchor("profile.name")
                    TextField("Chatname", text: $chatname)
                        .searchAnchor("profile.chatname")
                    Picker("Stil des Feeds", selection: feedStyleBinding) {
                        ForEach(1...3, id: \.self) { style in
                            Text(ProfileModel.feedStyleName(style)).tag(style)
                        }
                    }
                    .searchAnchor("profile.feedStyle")
                    Button("Speichern") {
                        Task {
                            // Only what really changed goes to the server; the
                            // chatname has a cooldown of a day.
                            let trimmedName = name.trimmingCharacters(in: .whitespaces)
                            if !trimmedName.isEmpty, trimmedName != profile.savedName {
                                await profile.setName(trimmedName)
                            }
                            let trimmedChatname = chatname.trimmingCharacters(in: .whitespaces)
                            if !trimmedChatname.isEmpty, trimmedChatname != profile.savedChatname {
                                await profile.setChatname(trimmedChatname)
                            }
                        }
                    }
                    .disabled(profile.isSaving || !profileNamesChanged)
                    .searchAnchor("profile.save")
                } header: {
                    Text("Profil")
                } footer: {
                    Text("Der Chatname lässt sich nur alle 24 Stunden ändern und muss frei sein.")
                }

                Section {
                    ProfileCard(symbol: "shippingbox",
                                title: "Lieferadresse",
                                text: "Die Lieferadresse des Kontos für den Versand.",
                                state: profile.optionalInfo.addressCollected ? "hinterlegt" : "nicht hinterlegt",
                                isSet: profile.optionalInfo.addressCollected) {
                        HStack(spacing: Space.s) {
                            Button(profile.optionalInfo.addressCollected ? "Adresse ändern …" : "Adresse eintragen …") {
                                profileSheet = .address
                            }
                            if profile.optionalInfo.addressCollected {
                                Button("Löschen", role: .destructive) { pendingDelete = .address }
                            }
                        }
                        .disabled(profile.isSaving)
                    }
                    .searchAnchor("profile.address")

                    ProfileCard(symbol: "birthday.cake",
                                title: "Geburtsdatum",
                                text: "Tag und Monat genügen, das Jahr darf fehlen.",
                                state: profile.optionalInfo.birthdayCollected ? "hinterlegt" : "nicht hinterlegt",
                                isSet: profile.optionalInfo.birthdayCollected) {
                        HStack(spacing: Space.s) {
                            Button(profile.optionalInfo.birthdayCollected ? "Geburtsdatum ändern …" : "Geburtsdatum eintragen …") {
                                profileSheet = .birthday
                            }
                            if profile.optionalInfo.birthdayCollected {
                                Button("Löschen", role: .destructive) { pendingDelete = .birthday }
                            }
                        }
                        .disabled(profile.isSaving)
                    }
                    .searchAnchor("profile.birthday")

                    ProfileCard(symbol: "signature",
                                title: "Credits",
                                text: "So wird das Konto in den Credits genannt.",
                                state: profile.optionalInfo.creditsCollected ? "hinterlegt" : "nicht hinterlegt",
                                isSet: profile.optionalInfo.creditsCollected) {
                        HStack(spacing: Space.s) {
                            Button(profile.optionalInfo.creditsCollected ? "Eintrag ändern …" : "Eintrag schreiben …") {
                                profileSheet = .credits
                            }
                            if profile.optionalInfo.creditsCollected {
                                Button("Löschen", role: .destructive) { pendingDelete = .credits }
                            }
                        }
                        .disabled(profile.isSaving)
                    }
                    .searchAnchor("profile.credits")
                } header: {
                    Text("Optionale Angaben")
                } footer: {
                    Text("Die Werte selbst bleiben auf dem Server; die App erfährt nur, ob welche hinterlegt sind.")
                }

                Section {
                    if profile.needsLegalConfirmation {
                        ProfileNotice(symbol: "exclamationmark.circle.fill",
                                      text: profile.openActionTitles.isEmpty
                                          ? "Der Server verlangt noch eine Bestätigung."
                                          : "Der Server verlangt noch: \(profile.openActionTitles.joined(separator: ", ")).")
                    }
                    ProfileCard(symbol: "hand.raised",
                                title: "Datenschutzbestimmungen",
                                text: "Die Bestätigung gilt für die aktuelle Fassung des Textes.",
                                state: profile.privacyConfirmed ? "bestätigt" : "offen",
                                isSet: profile.privacyConfirmed) {
                        HStack(spacing: Space.s) {
                            Button(profile.privacyConfirmed ? "Erneut bestätigen" : "Jetzt bestätigen") {
                                Task { await profile.acceptPrivacy() }
                            }
                            .disabled(profile.isSaving)
                            .searchAnchor("profile.acceptPrivacy")
                            Button("Text lesen") {
                                NSWorkspace.shared.open(SettingsLegal.privacy)
                            }
                            .help("Öffnet die Datenschutzerklärung im Browser")
                        }
                    }
                    .searchAnchor("profile.privacy")

                    ProfileCard(symbol: "doc.text",
                                title: "Allgemeine Geschäftsbedingungen",
                                text: "Die Bestätigung gilt für die aktuelle Fassung der AGB.",
                                state: profile.agbConfirmed ? "bestätigt" : "offen",
                                isSet: profile.agbConfirmed) {
                        HStack(spacing: Space.s) {
                            Button(profile.agbConfirmed ? "Erneut bestätigen" : "Jetzt bestätigen") {
                                Task { await profile.acceptAGB() }
                            }
                            .disabled(profile.isSaving)
                            .searchAnchor("profile.acceptAGB")
                            Button("Text lesen") {
                                NSWorkspace.shared.open(SettingsLegal.terms)
                            }
                            .help("Öffnet die Allgemeinen Geschäftsbedingungen im Browser")
                        }
                    }
                    .searchAnchor("profile.agb")
                } header: {
                    Text("Rechtliches")
                } footer: {
                    Text("Die Version der Texte bestimmt der Server; die App bestätigt die aktuelle. Der Wortlaut steht auf orangeflix.de.")
                }

                Section {
                    LabeledContent("Feed zuletzt gesehen") {
                        Text(profile.marker?.date.map { AppFormat.dateTime($0) } ?? "—")
                    }
                    .searchAnchor("profile.feedSeen")
                    Button("Feed jetzt als gesehen markieren") {
                        Task { await profile.markFeedSeen() }
                    }
                    .searchAnchor("profile.markSeen")
                } header: {
                    Text("Feed")
                } footer: {
                    Text("Der Marker bleibt eine halbe Stunde stehen; danach zählt die App neu.")
                }

                Section {
                    if categoryFormats.isEmpty {
                        Text("Die Kategorien stehen bereit, sobald die App den Feed gelesen hat.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(categoryFormats) { format in
                        DisclosureGroup(format.title) {
                            ForEach(format.categories) { category in
                                Toggle(category.title, isOn: exclusionBinding(format.id, category.id))
                            }
                        }
                    }
                    if !profile.exclusionFilter.isEmpty {
                        Button("Filter leeren", role: .destructive) { pendingDelete = .feedFilter }
                    }
                } header: {
                    Text("Feed-Filter")
                } footer: {
                    Text("Die ausgeschalteten Kategorien bleiben im Haupt-Feed aus.")
                }
            }
        }
        .task(id: app.accountGeneration) {
            if app.hasCredentials, profile.needsLoad { await profile.load() }
            guard !Task.isCancelled else { return }
            // Another account brings its own names; what stood in the fields
            // for the last one goes.
            if namesAccount != app.accountGeneration {
                namesAccount = app.accountGeneration
                name = ""
                chatname = ""
            }
            if name.isEmpty { name = profile.savedName }
            if chatname.isEmpty { chatname = profile.savedChatname }
        }
        .sheet(item: $profileSheet) { item in
            switch item {
            case .address:
                AddressSheet { input in
                    Task { await profile.saveAddress(input) }
                }
            case .birthday:
                BirthdaySheet { input in
                    Task { await profile.saveBirthday(input) }
                }
            case .credits:
                CreditsSheet { input in
                    Task { await profile.saveCredits(input) }
                }
            }
        }
    }

    /// Whether Speichern has a name to send. An empty field and a name the
    /// server already stores do not.
    private var profileNamesChanged: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedChatname = chatname.trimmingCharacters(in: .whitespaces)
        let nameChanged = !trimmedName.isEmpty && trimmedName != profile.savedName
        let chatChanged = !trimmedChatname.isEmpty && trimmedChatname != profile.savedChatname
        return nameChanged || chatChanged
    }

    /// The style of the main feed, 1…3.
    private var feedStyleBinding: Binding<Int> {
        Binding(
            get: { profile.preferences?.feedStyle ?? 1 },
            set: { value in Task { await profile.setFeedStyle(value) } })
    }

    /// One format with the categories the app has seen.
    private struct CategoryFormat: Identifiable {
        let id: Int
        let title: String
        let categories: [Category]
    }

    /// One category of a format.
    private struct Category: Identifiable {
        let id: Int
        let title: String
    }

    /// The formats with the categories the feed has shown.
    private var categoryFormats: [CategoryFormat] {
        browse.knownCategories
            .map { pid, categories in
                CategoryFormat(
                    id: pid,
                    title: browse.formats.first { $0.pid == pid }?.title ?? "Format \(pid)",
                    categories: categories
                        .sorted { $0.key < $1.key }
                        .map { Category(id: $0.key, title: $0.value) })
            }
            .filter { !$0.categories.isEmpty }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    /// Whether one category of a format stays out of the main feed. The
    /// model keeps the choice while it is on its way, so quick clicks on
    /// several switches all count.
    private func exclusionBinding(_ pid: Int, _ subpid: Int) -> Binding<Bool> {
        Binding(
            get: { profile.exclusionFilter[pid]?.contains(subpid) ?? false },
            set: { value in Task { await profile.setCategory(subpid, of: pid, excluded: value) } })
    }
}
