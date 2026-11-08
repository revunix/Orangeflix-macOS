import SwiftUI

/// One control of the settings the search can find: a switch, a picker, a
/// button or a value.
struct SettingsSearchEntry: Identifiable, Hashable {
    /// Also the anchor of the control on its page (`searchAnchor`).
    let id: String
    let pane: SettingsScreen.Pane
    let title: String
    /// The heading of the group the control stands in.
    let section: String
    /// Further words the search finds the control by.
    var keywords: String = ""

    /// True when every word of the query occurs in the control. The name of
    /// the area is left out, so "downloads" finds the area, not each control.
    func matches(_ words: [String]) -> Bool {
        let text = SettingsSearch.fold("\(title) \(section) \(keywords)")
        return words.allSatisfy { text.contains($0) }
    }
}

/// An area of the settings with the controls the search found in it.
struct SettingsSearchGroup: Identifiable {
    let pane: SettingsScreen.Pane
    let entries: [SettingsSearchEntry]

    var id: SettingsScreen.Pane { pane }
}

enum SettingsSearch {
    private static let german = Locale(identifier: "de_DE")

    /// Lower case, without accents, so "hell" also finds "Hell" and
    /// "qualitat" finds "Qualität".
    static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: german)
    }

    /// The words of a query; empty for a blank one.
    static func words(_ query: String) -> [String] {
        fold(query).split(whereSeparator: \.isWhitespace).map(String.init)
    }

    /// The controls that are always there. Themes and formats come from the
    /// data and are added by the settings screen.
    static let entries: [SettingsSearchEntry] = [
        // Konto
        .init(id: "account.user", pane: .account, title: "Benutzer", section: "Anmeldung",
              keywords: "konto e-mail email name angemeldet"),
        .init(id: "account.signOut", pane: .account, title: "Abmelden …", section: "Anmeldung",
              keywords: "logout ausloggen konto wechseln passwort e-mail login"),
        .init(id: "account.status", pane: .account, title: "Status", section: "Abo",
              keywords: "abonnement aktiv abgelaufen"),
        .init(id: "account.tier", pane: .account, title: "Stufe", section: "Abo", keywords: "abonnement tier"),
        .init(id: "account.expiry", pane: .account, title: "Läuft ab", section: "Abo",
              keywords: "abonnement ablauf datum ende"),
        .init(id: "account.refresh", pane: .account, title: "Neu prüfen", section: "Abo",
              keywords: "abonnement aktualisieren laden"),
        .init(id: "account.chatname", pane: .account, title: "Chatname", section: "Anmeldung",
              keywords: "name chat nutzername"),
        .init(id: "account.displayName", pane: .account, title: "Anzeigename", section: "Anmeldung",
              keywords: "name anzeige profil"),
        .init(id: "account.created", pane: .account, title: "Mitglied seit", section: "Anmeldung",
              keywords: "registriert erstellt beitritt datum"),
        .init(id: "account.lastLogin", pane: .account, title: "Letzte Anmeldung", section: "Anmeldung",
              keywords: "login zuletzt datum"),
        .init(id: "account.feedSeen", pane: .account, title: "Feed zuletzt gesehen", section: "Anmeldung",
              keywords: "neuigkeiten datum"),
        .init(id: "account.totp", pane: .account, title: "Zwei-Faktor-Anmeldung", section: "Anmeldung",
              keywords: "2fa totp sicherheit code"),
        .init(id: "account.access", pane: .account, title: "Zugang", section: "Abo", keywords: "abonnement premium"),
        .init(id: "account.accessType", pane: .account, title: "Zugangsart", section: "Abo",
              keywords: "abonnement typ art"),
        .init(id: "account.plan", pane: .account, title: "Abo", section: "Abo", keywords: "abonnement tarif paket"),
        .init(id: "account.nextPayment", pane: .account, title: "Nächste Zahlung", section: "Abo",
              keywords: "abonnement abbuchung rechnung datum"),
        .init(id: "account.amount", pane: .account, title: "Betrag", section: "Abo",
              keywords: "abonnement preis kosten euro"),
        .init(id: "account.computedAmount", pane: .account, title: "Berechneter Betrag", section: "Abo",
              keywords: "abonnement preis kosten"),
        .init(id: "account.started", pane: .account, title: "Angefangene Folgen", section: "Nutzung",
              keywords: "fortschritt gesehen statistik"),
        .init(id: "account.finished", pane: .account, title: "Zu Ende gesehen", section: "Nutzung",
              keywords: "fortschritt fertig statistik"),
        .init(id: "account.lastWatched", pane: .account, title: "Zuletzt gesehen", section: "Nutzung",
              keywords: "fortschritt datum"),
        .init(id: "account.library", pane: .account, title: "Formate in der Bibliothek", section: "Nutzung",
              keywords: "statistik anzahl"),
        .init(id: "account.newEpisodes", pane: .account, title: "Neue Folgen", section: "Nutzung",
              keywords: "statistik anzahl"),

        // Profil
        .init(id: "profile.name", pane: .profile, title: "Anzeigename", section: "Profil",
              keywords: "name anzeige profil"),
        .init(id: "profile.chatname", pane: .profile, title: "Chatname", section: "Profil",
              keywords: "name chat nutzername profil"),
        .init(id: "profile.feedStyle", pane: .profile, title: "Stil des Feeds", section: "Profil",
              keywords: "feed layout kompakt mittel groß stil"),
        .init(id: "profile.save", pane: .profile, title: "Speichern", section: "Profil",
              keywords: "name chatname speichern"),
        .init(id: "profile.address", pane: .profile, title: "Adresse", section: "Optionale Angaben",
              keywords: "lieferadresse versand"),
        .init(id: "profile.birthday", pane: .profile, title: "Geburtsdatum", section: "Optionale Angaben",
              keywords: "geburtstag datum"),
        .init(id: "profile.credits", pane: .profile, title: "Credits", section: "Optionale Angaben",
              keywords: "abspann nennung"),
        .init(id: "profile.privacy", pane: .profile, title: "Datenschutz", section: "Rechtliches",
              keywords: "datenschutz privacy bestätigen"),
        .init(id: "profile.agb", pane: .profile, title: "AGB", section: "Rechtliches",
              keywords: "agb nutzungsbedingungen bestätigen"),
        .init(id: "profile.acceptPrivacy", pane: .profile, title: "Datenschutzbestimmungen bestätigen",
              section: "Rechtliches", keywords: "datenschutz privacy bestätigen"),
        .init(id: "profile.acceptAGB", pane: .profile, title: "AGB bestätigen", section: "Rechtliches",
              keywords: "agb nutzungsbedingungen bestätigen"),
        .init(id: "profile.feedSeen", pane: .profile, title: "Feed zuletzt gesehen", section: "Feed",
              keywords: "marker neu datum"),
        .init(id: "profile.markSeen", pane: .profile, title: "Feed jetzt als gesehen markieren",
              section: "Feed", keywords: "marker neu"),

        // Sharing
        .init(id: "sharing.quota", pane: .sharing, title: "Kontingent", section: "Kontingent",
              keywords: "links monat limit stufe kontingent"),
        .init(id: "sharing.reload", pane: .sharing, title: "Neu laden", section: "Kontingent",
              keywords: "links aktualisieren laden"),
        .init(id: "sharing.check", pane: .sharing, title: "Code prüfen", section: "Code prüfen",
              keywords: "code prüfen link testen"),

        // Mitteilungen
        .init(id: "notifications.test", pane: .notifications, title: "Testmitteilung senden",
              section: "Kanäle", keywords: "benachrichtigung test"),
        .init(id: "notifications.resubscribe", pane: .notifications,
              title: "E-Mail-Versand wieder einschalten", section: "Kanäle",
              keywords: "email abmelden wieder anmelden"),

        // Darstellung
        .init(id: "appearance.mode", pane: .appearance, title: "Farbschema", section: "Farbschema",
              keywords: "modus design automatisch hell dunkel auto light dark"),
        .init(id: "appearance.style", pane: .appearance, title: "Oberflächenstil", section: "Oberflächenstil",
              keywords: "glas glass klassisch classic liquid glass oberfläche"),
        .init(id: "appearance.tint", pane: .appearance, title: "Mit Theme einfärben", section: "Oberflächenstil",
              keywords: "akzent farbe theme tint einfärben"),
        .init(id: "appearance.glass", pane: .appearance, title: "Glas für Flächen", section: "Oberflächenstil",
              keywords: "glas glass panels flächen material"),
        .init(id: "appearance.appIcon", pane: .appearance, title: "App-Symbol", section: "App-Symbol",
              keywords: "icon app icon symbol dock leuchtend dämmerung twilight bright"),        .init(id: "appearance.lightExtended", pane: .appearance, title: "Erweiterte Theme-Palette verwenden",
              section: "Heller Modus", keywords: "theme farben flächen texte akzent"),
        .init(id: "appearance.darkExtended", pane: .appearance, title: "Erweiterte Theme-Palette verwenden",
              section: "Dunkler Modus", keywords: "theme farben flächen texte akzent"),
        .init(id: "appearance.import", pane: .appearance, title: "Importieren …", section: "Theme importieren",
              keywords: "theme ghostty iterm itermcolors datei"),

        // Downloads
        .init(id: "downloads.quality", pane: .downloads, title: "Qualität", section: "Dateien",
              keywords: "auflösung beste hd sd mobil audio"),
        .init(id: "downloads.layout", pane: .downloads, title: "Ablage", section: "Dateien",
              keywords: "layout ordner struktur kompatibel flach"),
        .init(id: "downloads.parallel", pane: .downloads, title: "Gleichzeitig", section: "Tempo",
              keywords: "parallel anzahl"),
        .init(id: "downloads.delay", pane: .downloads, title: "Pause", section: "Tempo",
              keywords: "wartezeit sekunden verzögerung"),
        .init(id: "downloads.limit", pane: .downloads, title: "Tempolimit", section: "Tempo",
              keywords: "geschwindigkeit bandbreite kib limit drosseln"),
        .init(id: "downloads.thumb", pane: .downloads, title: "Vorschaubild speichern", section: "Begleitdateien",
              keywords: "thumbnail bild"),
        .init(id: "downloads.meta", pane: .downloads, title: "Metadaten speichern", section: "Begleitdateien",
              keywords: "json angaben"),

        // Streaming
        .init(id: "streaming.quality", pane: .streaming, title: "Qualität", section: "Wiedergabe",
              keywords: "stream player auflösung"),

        // Live
        .init(id: "live.chatStart", pane: .live, title: "Beim Öffnen zeigen", section: "Chat",
              keywords: "chat start einblenden ausgeblendet seite"),
        .init(id: "live.chatPosition", pane: .live, title: "Position", section: "Chat",
              keywords: "chat position automatisch rechts unten seite layout responsiv"),
        .init(id: "live.textSize", pane: .live, title: "Schriftgröße", section: "Chat",
              keywords: "chat schrift text größe lesbarkeit"),
        .init(id: "live.avatars", pane: .live, title: "Profilbilder zeigen", section: "Chat",
              keywords: "chat avatar bild"),
        .init(id: "live.times", pane: .live, title: "Uhrzeit der Nachrichten zeigen", section: "Chat",
              keywords: "chat zeit zeitstempel"),
        .init(id: "live.polls", pane: .live, title: "Anzeigen", section: "Abstimmungen",
              keywords: "umfrage abstimmung voting einklappen ausblenden"),

        // Formate
        .init(id: "formats.notifications", pane: .formats, title: "Neue Folgen melden", section: "Mitteilungen",
              keywords: "benachrichtigung hinweis"),
        .init(id: "formats.test", pane: .formats, title: "Testmitteilung senden", section: "Mitteilungen",
              keywords: "benachrichtigung test"),
        .init(id: "formats.allow", pane: .formats, title: "Mitteilungen in den Systemeinstellungen erlauben",
              section: "Mitteilungen", keywords: "benachrichtigung erlaubnis"),
        .init(id: "formats.showAll", pane: .formats, title: "Alle anzeigen", section: "Mediathek",
              keywords: "formate einblenden"),
        .init(id: "formats.hideAll", pane: .formats, title: "Alle ausblenden", section: "Mediathek",
              keywords: "formate verstecken"),
        .init(id: "formats.notifyAll", pane: .formats, title: "Alle melden", section: "Mitteilungen je Format",
              keywords: "benachrichtigung formate"),
        .init(id: "formats.notifyNone", pane: .formats, title: "Keine melden", section: "Mitteilungen je Format",
              keywords: "benachrichtigung formate"),

        // Speicherort
        .init(id: "storage.folder", pane: .storage, title: "Ordner", section: "Zielordner",
              keywords: "pfad download speicherort"),
        .init(id: "storage.change", pane: .storage, title: "Ordner ändern …", section: "Zielordner",
              keywords: "pfad download auswählen"),
        .init(id: "storage.reveal", pane: .storage, title: "Im Finder zeigen", section: "Zielordner",
              keywords: "öffnen"),
        .init(id: "storage.reset", pane: .storage, title: "Auf ~/Downloads/Orangeflix zurücksetzen",
              section: "Zielordner", keywords: "standard"),

        // Import & Export
        .init(id: "transfer.backupExport", pane: .transfer, title: "Sicherung exportieren …", section: "Orangeflix",
              keywords: "einstellungen backup speichern themes zweiter mac json"),
        .init(id: "transfer.backupImport", pane: .transfer, title: "Sicherung importieren …", section: "Orangeflix",
              keywords: "einstellungen backup laden wiederherstellen themes json"),
        .init(id: "transfer.configExport", pane: .transfer, title: "config exportieren …",
              section: "Kommandozeilen-Werkzeug", keywords: "cli konfiguration datei orangeflix-dl speichern"),
        .init(id: "transfer.configImport", pane: .transfer, title: "config importieren …",
              section: "Kommandozeilen-Werkzeug", keywords: "cli konfiguration datei orangeflix-dl laden"),
        .init(id: "transfer.libraryExport", pane: .transfer, title: "library.db exportieren …", section: "Bibliothek",
              keywords: "cli datenbank sqlite speichern sicherung"),
        .init(id: "transfer.libraryImport", pane: .transfer, title: "library.db importieren …", section: "Bibliothek",
              keywords: "cli datenbank sqlite laden ersetzen"),
        .init(id: "transfer.libraryRestore", pane: .transfer, title: "Vorherige Bibliothek wiederherstellen …",
              section: "Bibliothek", keywords: "sicherung zurück datenbank rückgängig"),

        // Über
        .init(id: "about.independence", pane: .about, title: "Keine Verbindung zur Plattform",
              section: "Unabhängigkeit", keywords: "unabhängig inoffiziell disclaimer keine verbindung orangeflix.de plattform rechtliches"),
        .init(id: "about.license", pane: .about, title: "Lizenz", section: "Lizenz",
              keywords: "mit quelltext urheberrecht copyright bedingungen"),
    ]
}

// MARK: - Highlight

private struct SettingsHighlightKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The control the search jumped to; it lights up for a moment.
    var settingsHighlight: String? {
        get { self[SettingsHighlightKey.self] }
        set { self[SettingsHighlightKey.self] = newValue }
    }
}

/// Makes a control a target of the search: the page scrolls to it and it
/// lights up in the accent.
private struct SearchAnchor: ViewModifier {
    let id: String
    @Environment(\.settingsHighlight) private var highlight

    func body(content: Content) -> some View {
        content
            .background {
                RoundedRectangle(cornerRadius: Radius.s, style: .continuous)
                    .fill(.tint.opacity(highlight == id ? 0.22 : 0))
                    .padding(-5)
                    .animation(.easeOut(duration: 0.3), value: highlight == id)
            }
            .id(id)
    }
}

extension View {
    /// See `SearchAnchor`; `id` is the id of a `SettingsSearchEntry`.
    func searchAnchor(_ id: String) -> some View {
        modifier(SearchAnchor(id: id))
    }
}
