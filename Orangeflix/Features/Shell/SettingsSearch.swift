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
    /// Optional sub-tab on the unified Konto & Profil page.
    var accountTab: AccountSubTab? = nil
    /// Whether jumping here should expand the advanced group on Downloads.
    var expandsDownloadsAdvanced: Bool = false

    /// True when every word of the query occurs in the control.
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
        // Konto & Profil — Übersicht
        .init(id: "account.user", pane: .account, title: "Benutzer & Anmeldung", section: "Konto · Übersicht",
              keywords: "konto e-mail email name angemeldet letzte anmeldung mitglied seit", accountTab: .overview),
        .init(id: "account.signOut", pane: .account, title: "Abmelden …", section: "Konto · Übersicht",
              keywords: "logout ausloggen konto wechseln passwort e-mail login", accountTab: .overview),
        .init(id: "account.totp", pane: .account, title: "Zwei-Faktor-Anmeldung", section: "Konto · Übersicht",
              keywords: "2fa totp sicherheit code", accountTab: .overview),
        .init(id: "account.status", pane: .account, title: "Abo & Mitgliedschaft", section: "Konto · Übersicht",
              keywords: "abonnement aktiv abgelaufen stufe tier ablauf datum nächste zahlung betrag preis kosten euro", accountTab: .overview),
        .init(id: "account.refresh", pane: .account, title: "Status neu prüfen", section: "Konto · Übersicht",
              keywords: "abonnement aktualisieren laden", accountTab: .overview),
        .init(id: "account.usage", pane: .account, title: "Nutzung & Bibliothek", section: "Konto · Übersicht",
              keywords: "fortschritt gesehen angefangene folgen statistik bibliothek neue folgen", accountTab: .overview),

        // Konto & Profil — Angaben & Feed
        .init(id: "profile.name", pane: .account, title: "Anzeigename", section: "Konto · Angaben & Feed",
              keywords: "name anzeige profil", accountTab: .details),
        .init(id: "profile.chatname", pane: .account, title: "Chatname", section: "Konto · Angaben & Feed",
              keywords: "name chat nutzername profil", accountTab: .details),
        .init(id: "profile.feedStyle", pane: .account, title: "Stil des Feeds", section: "Konto · Angaben & Feed",
              keywords: "feed layout kompakt mittel groß stil", accountTab: .details),
        .init(id: "profile.save", pane: .account, title: "Namen speichern", section: "Konto · Angaben & Feed",
              keywords: "name chatname speichern", accountTab: .details),
        .init(id: "profile.markSeen", pane: .account, title: "Feed als gesehen markieren", section: "Konto · Angaben & Feed",
              keywords: "feed zuletzt gesehen marker neu", accountTab: .details),
        .init(id: "profile.address", pane: .account, title: "Lieferadresse", section: "Konto · Angaben & Feed",
              keywords: "adresse lieferadresse versand", accountTab: .details),
        .init(id: "profile.birthday", pane: .account, title: "Geburtsdatum", section: "Konto · Angaben & Feed",
              keywords: "geburtstag datum", accountTab: .details),
        .init(id: "profile.credits", pane: .account, title: "Credits-Nennung", section: "Konto · Angaben & Feed",
              keywords: "credits abspann nennung", accountTab: .details),
        .init(id: "profile.privacy", pane: .account, title: "Datenschutzbestimmungen", section: "Konto · Angaben & Feed",
              keywords: "datenschutz privacy bestätigen rechtliches", accountTab: .details),
        .init(id: "profile.agb", pane: .account, title: "Allgemeine Geschäftsbedingungen", section: "Konto · Angaben & Feed",
              keywords: "agb nutzungsbedingungen bestätigen rechtliches", accountTab: .details),
        .init(id: "profile.feedFilter", pane: .account, title: "Feed-Filter", section: "Konto · Angaben & Feed",
              keywords: "kategorien ausblenden filter haupt-feed", accountTab: .details),

        // Konto & Profil — Sharing-Links
        .init(id: "sharing.quota", pane: .account, title: "Sharing-Kontingent", section: "Konto · Sharing-Links",
              keywords: "links monat limit stufe kontingent teilen weitergeben", accountTab: .sharing),
        .init(id: "sharing.reload", pane: .account, title: "Links neu laden", section: "Konto · Sharing-Links",
              keywords: "links aktualisieren laden", accountTab: .sharing),
        .init(id: "sharing.check", pane: .account, title: "Link-Code prüfen", section: "Konto · Sharing-Links",
              keywords: "code prüfen link testen freigabe", accountTab: .sharing),

        // Allgemein
        .init(id: "about.updates", pane: .general, title: "Nach Updates suchen …",
              section: "Softwareupdate", keywords: "aktualisierung neue version changelog änderungen updater sparkle"),
        .init(id: "about.automaticUpdates", pane: .general, title: "Automatisch nach Updates suchen",
              section: "Softwareupdate", keywords: "automatisch prüfung einschalten ausschalten aktivieren deaktivieren"),
        .init(id: "about.updateInterval", pane: .general, title: "Suchintervall", section: "Softwareupdate",
              keywords: "täglich wöchentlich monatlich häufigkeit wann turnus"),
        .init(id: "formats.background", pane: .general, title: "Im Hintergrund weiterlaufen", section: "Hintergrund & Systemstart",
              keywords: "menüleiste dock hintergrund geschlossen mitteilung"),
        .init(id: "formats.login", pane: .general, title: "Bei der Anmeldung starten", section: "Hintergrund & Systemstart",
              keywords: "autostart anmeldeobjekt login start"),

        // Darstellung
        .init(id: "appearance.mode", pane: .appearance, title: "Farbschema", section: "Erscheinungsbild",
              keywords: "modus design automatisch hell dunkel auto light dark"),
        .init(id: "appearance.style", pane: .appearance, title: "Oberflächenstil", section: "Oberflächenstil",
              keywords: "glas glass klassisch classic liquid glass oberfläche"),
        .init(id: "appearance.tint", pane: .appearance, title: "Mit Theme einfärben", section: "Farbwelt & Themes",
              keywords: "akzent farbe theme tint einfärben"),
        .init(id: "appearance.glass", pane: .appearance, title: "Glas für Flächen", section: "Oberflächenstil",
              keywords: "glas glass panels flächen material"),
        .init(id: "appearance.appIcon", pane: .appearance, title: "App-Symbol", section: "App-Symbol im Dock",
              keywords: "icon app icon symbol dock leuchtend dämmerung twilight bright"),
        .init(id: "appearance.extended", pane: .appearance, title: "Erweiterte Theme-Palette verwenden",
              section: "Farbwelt & Themes", keywords: "theme farben flächen texte akzent"),
        .init(id: "appearance.import", pane: .appearance, title: "Ghostty- oder iTerm-Theme importieren …", section: "Farbwelt & Themes",
              keywords: "theme ghostty iterm itermcolors datei importieren"),

        // Mitteilungen
        .init(id: "general.newEpisodes", pane: .notifications, title: "Neue Folgen melden", section: "Dieser Mac",
              keywords: "benachrichtigung hinweis mitteilung"),
        .init(id: "general.liveNotifications", pane: .notifications, title: "Livestreams melden", section: "Dieser Mac",
              keywords: "live stream benachrichtigung mitteilung"),
        .init(id: "general.chatNotifications", pane: .notifications,
              title: "Bei Erwähnungen und Reaktionen melden", section: "Dieser Mac",
              keywords: "chat erwähnung mention reaktion benachrichtigung mitteilung live"),
        .init(id: "general.testNotifications", pane: .notifications, title: "Testmitteilung dieses Macs",
              section: "Dieser Mac", keywords: "benachrichtigung test lokal"),
        .init(id: "general.allowNotifications", pane: .notifications, title: "In den Systemeinstellungen erlauben",
              section: "Dieser Mac", keywords: "benachrichtigung erlaubnis"),
        .init(id: "notifications.test", pane: .notifications, title: "Testmitteilung vom Server",
              section: "Server-Kanäle", keywords: "benachrichtigung test server push"),
        .init(id: "notifications.resubscribe", pane: .notifications,
              title: "E-Mail-Versand wieder einschalten", section: "Server-Kanäle",
              keywords: "email abmelden wieder anmelden"),

        // Wiedergabe & Live
        .init(id: "streaming.quality", pane: .playback, title: "Standard-Qualität", section: "Wiedergabe",
              keywords: "stream player auflösung beste hd sd mobil audio"),
        .init(id: "streaming.discord", pane: .playback, title: "Aktuelle Wiedergabe in Discord anzeigen",
              section: "Discord Rich Presence", keywords: "discord rich presence spotify status aktivität schaut"),
        .init(id: "streaming.discordButton", pane: .playback, title: "Link-Button zur Folge oder zum Livestream zeigen",
              section: "Discord Rich Presence", keywords: "discord link button folge livestream url"),
        .init(id: "live.chatStart", pane: .playback, title: "Chat beim Öffnen zeigen", section: "Livestream-Chat",
              keywords: "chat start einblenden ausgeblendet seite"),
        .init(id: "live.chatPosition", pane: .playback, title: "Chat-Position", section: "Livestream-Chat",
              keywords: "chat position automatisch rechts unten seite layout responsiv"),
        .init(id: "live.textSize", pane: .playback, title: "Schriftgröße im Chat", section: "Livestream-Chat",
              keywords: "chat schrift text größe lesbarkeit"),
        .init(id: "live.avatars", pane: .playback, title: "Profilbilder zeigen", section: "Livestream-Chat",
              keywords: "chat avatar bild"),
        .init(id: "live.times", pane: .playback, title: "Uhrzeit der Nachrichten zeigen", section: "Livestream-Chat",
              keywords: "chat zeit zeitstempel"),
        .init(id: "live.polls", pane: .playback, title: "Live-Abstimmungen", section: "Livestream-Chat",
              keywords: "umfrage abstimmung voting einklappen ausblenden"),

        // Downloads (inkl. Speicherort)
        .init(id: "storage.folder", pane: .downloads, title: "Speicherort (Zielordner)", section: "Speicherort",
              keywords: "pfad download speicherort ordner ändern im finder zeigen zurücksetzen"),
        .init(id: "downloads.quality", pane: .downloads, title: "Download-Qualität", section: "Dateien & Begleitdateien",
              keywords: "auflösung beste hd sd mobil audio"),
        .init(id: "downloads.layout", pane: .downloads, title: "Ordnerstruktur (Ablage)", section: "Dateien & Begleitdateien",
              keywords: "layout ordner struktur kompatibel flach"),
        .init(id: "downloads.thumb", pane: .downloads, title: "Vorschaubild speichern", section: "Dateien & Begleitdateien",
              keywords: "thumbnail bild begleitdateien"),
        .init(id: "downloads.meta", pane: .downloads, title: "Metadaten speichern", section: "Dateien & Begleitdateien",
              keywords: "json angaben begleitdateien"),
        .init(id: "downloads.parallel", pane: .downloads, title: "Gleichzeitige Downloads", section: "Tempo & Erweitert",
              keywords: "parallel anzahl gleichzeitig"),
        .init(id: "downloads.delay", pane: .downloads, title: "Pause zwischen Downloads", section: "Tempo & Erweitert",
              keywords: "wartezeit sekunden verzögerung pause", expandsDownloadsAdvanced: true),
        .init(id: "downloads.limit", pane: .downloads, title: "Tempolimit (Bandbreite)", section: "Tempo & Erweitert",
              keywords: "geschwindigkeit bandbreite kib limit drosseln", expandsDownloadsAdvanced: true),
        .init(id: "downloads.submodule", pane: .downloads, title: "Feed-Variante", section: "Tempo & Erweitert",
              keywords: "rss feed submodule variante", expandsDownloadsAdvanced: true),

        // Formate
        .init(id: "formats.showAll", pane: .formats, title: "Alle Formate anzeigen", section: "Formate",
              keywords: "formate einblenden"),
        .init(id: "formats.hideAll", pane: .formats, title: "Alle Formate ausblenden", section: "Formate",
              keywords: "formate verstecken"),
        .init(id: "formats.notifyAll", pane: .formats, title: "Alle Formate melden", section: "Formate",
              keywords: "benachrichtigung formate"),
        .init(id: "formats.notifyNone", pane: .formats, title: "Keine Formate melden", section: "Formate",
              keywords: "benachrichtigung formate"),

        // Sicherung & Daten
        .init(id: "transfer.backupExport", pane: .transfer, title: "Sicherung exportieren …", section: "App-Sicherung",
              keywords: "einstellungen backup speichern themes zweiter mac json"),
        .init(id: "transfer.backupImport", pane: .transfer, title: "Sicherung importieren …", section: "App-Sicherung",
              keywords: "einstellungen backup laden wiederherstellen themes json"),
        .init(id: "transfer.configExport", pane: .transfer, title: "config exportieren …",
              section: "Kommandozeilen-Werkzeug", keywords: "cli konfiguration datei orangeflix-dl speichern"),
        .init(id: "transfer.configImport", pane: .transfer, title: "config importieren …",
              section: "Kommandozeilen-Werkzeug", keywords: "cli konfiguration datei orangeflix-dl laden"),
        .init(id: "transfer.libraryExport", pane: .transfer, title: "library.db exportieren …", section: "Lokale Bibliothek",
              keywords: "cli datenbank sqlite speichern sicherung"),
        .init(id: "transfer.libraryImport", pane: .transfer, title: "library.db importieren …", section: "Lokale Bibliothek",
              keywords: "cli datenbank sqlite laden ersetzen"),
        .init(id: "transfer.libraryRestore", pane: .transfer, title: "Vorherige Bibliothek wiederherstellen …",
              section: "Lokale Bibliothek", keywords: "sicherung zurück datenbank rückgängig"),

        // Über Orangeflix
        .init(id: "about.independence", pane: .about, title: "Unabhängiges Projekt",
              section: "Rechtliches & Lizenz", keywords: "unabhängig inoffiziell disclaimer keine verbindung orangeflix.de plattform rechtliches"),
        .init(id: "about.license", pane: .about, title: "MIT-Lizenz & Bestandteile", section: "Rechtliches & Lizenz",
              keywords: "mit quelltext urheberrecht copyright sparkle libmpv mpv player entwickler"),
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
                RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                    .fill(Palette.accent.opacity(highlight == id ? 0.18 : 0))
                    .overlay {
                        if highlight == id {
                            RoundedRectangle(cornerRadius: Radius.m, style: .continuous)
                                .strokeBorder(Palette.accent.opacity(0.55), lineWidth: 1)
                        }
                    }
                    .padding(-6)
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
