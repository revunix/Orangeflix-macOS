import AppKit
import SwiftUI
import Sparkle

/// The window of the settings. It is built from the native building blocks
/// of the Mac: a sidebar list, a grouped form and the system chrome — no
/// own rows, cards or titlebar.
struct SettingsScreen: View {
    let updaterController: SPUStandardUpdaterController
    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account
    @Environment(BrowseModel.self) private var browse
    @Environment(NewEpisodeWatcher.self) private var watcher
    @Environment(SharingModel.self) private var sharing
    @Environment(NotificationSettingsModel.self) private var notifications
    @Environment(BackgroundMode.self) private var background
    @Environment(ProfileModel.self) private var profile
    @Environment(SessionModel.self) private var sessions
    @Environment(\.colorScheme) private var colorScheme

    /// Sparkle persists both values in the app's user defaults.
    @State private var automaticUpdateChecks: Bool
    @State private var updateCheckInterval: TimeInterval

    init(updaterController: SPUStandardUpdaterController) {
        self.updaterController = updaterController
        _automaticUpdateChecks = State(initialValue: updaterController.updater.automaticallyChecksForUpdates)
        _updateCheckInterval = State(initialValue: updaterController.updater.updateCheckInterval)
    }

    /// The areas of the sidebar.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case general, account, profile, sharing, appearance, downloads, streaming, live, formats, transfer, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "Allgemein"
            case .account: "Konto"
            case .profile: "Profil"
            case .sharing: "Sharing"
            case .appearance: "Darstellung"
            case .downloads: "Downloads"
            case .streaming: "Streaming"
            case .live: "Live"
            case .formats: "Formate"
            case .transfer: "Import & Export"
            case .about: "Über"
            }
        }

        var icon: String {
            switch self {
            case .general: "gearshape"
            case .account: "person.crop.circle"
            case .profile: "person.text.rectangle"
            case .sharing: "link.circle"
            case .appearance: "paintpalette"
            case .downloads: "arrow.down.circle"
            case .streaming: "play.rectangle"
            case .live: "dot.radiowaves.left.and.right"
            case .formats: "rectangle.stack"
            case .transfer: "arrow.up.arrow.down.circle"
            case .about: "info.circle"
            }
        }

        /// Words the search finds besides the title.
        var keywords: String {
            switch self {
            case .profile: "name chatname adresse geburtstag credits abo datenschutz legal"
            case .sharing: "link teilen weitergeben freigabe code"
            case .general: "mitteilungen benachrichtigung push email ereignis gerät updates aktualisierung updater automatisch prüfintervall speicherort ordner download hintergrund anmeldung starten autostart"
            case .appearance: "themes design erscheinungsbild hell dunkel automatisch farben"
            case .live: "livestream chat umfrage abstimmung voting schrift schriftgröße profilbild avatar uhrzeit"
            case .transfer: "import export sicherung backup wiederherstellen config bibliothek library datenbank"
            case .about: "version lizenz mit lizenz text rechtliches impressum disclaimer unabhängig inoffiziell projekt danke"
            default: ""
            }
        }
    }

    @State private var pane: Pane = .general
    /// The areas visited, so the arrows in the bar can walk them.
    @State private var history: [Pane] = [.general]
    @State private var historyIndex = 0
    /// The text of the search in the sidebar.
    @State private var search = ""
    /// The search and the filter of the format list.
    @State private var formatQuery = ""
    @State private var formatFilter = SettingsFormatFilter.all
    /// The control the search jumped to; it lights up for a moment.
    @State private var highlight: String?
    /// Counts the jumps of the search, so a second jump to the same control
    /// scrolls again.
    @State private var jumps = 0
    /// The message of the last failed change.
    @State private var settingsError: String?
    /// The result of the last import or export.
    @State private var transferMessage: String?
    /// Whether the last import or export failed.
    @State private var transferFailed = false
    /// The library that waits for the confirmation of the user.
    @State private var pendingLibrary: URL?
    /// The name the account shows; the field of the profile page.
    @State private var name = ""
    /// The name in the chat; the field of the profile page.
    @State private var chatname = ""
    /// The sheet of the profile page; only one stands open at a time.
    @State private var profileSheet: ProfileSheet?
    /// The code of a sharing link that is checked.
    @State private var shareCode = ""
    /// The result of the check of a sharing code.
    @State private var shareCheck: String?

    /// The sheets of the profile page.
    private enum ProfileSheet: Identifiable {
        /// The shipping address of the account.
        case address
        /// The birthday of the account.
        case birthday
        /// The mention of the account in the credits.
        case credits

        var id: String {
            switch self {
            case .address: "address"
            case .birthday: "birthday"
            case .credits: "credits"
            }
        }
    }

    /// The size the window opens with; the scene in `MyApp` names the same,
    /// so the first frame is already this size.
    static let windowSize = CGSize(width: 740, height: 770)

    private static let german = Locale(identifier: "de_DE")
    private static let delayFormat: FloatingPointFormatStyle<Double> =
        .number.precision(.fractionLength(0...2)).locale(german)
    private static let limitFormat: IntegerFormatStyle<Int> = .number.locale(german)

    var body: some View {
        // The native split view of macOS: a floating Liquid Glass sidebar
        // with the search, the arrows and the title in the toolbar, like the
        // System Settings. No titlebar tricks; macOS draws the chrome.
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 215, max: 260)
                // The sidebar of the settings always shows.
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(pane.title)
                .toolbar {
                    if #available(macOS 26, *) {
                        // The capsule draws its own glass, so the gap before it
                        // can sit outside it: the toolbar's shared glass would
                        // grow around any padding, and an empty item before it
                        // moves it by a fixed, too large amount.
                        ToolbarItem(placement: .navigation) {
                            historyArrows
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .padding(.leading, Self.arrowsInset)
                                // Room between the capsule and the title.
                                .padding(.trailing, Self.titleGap)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    } else {
                        ToolbarItem(placement: .navigation) {
                            historyArrows
                                .padding(.leading, Self.arrowsInset)
                                .padding(.trailing, Self.titleGap)
                        }
                    }
                }
        }
        .searchable(text: $search, placement: .sidebar, prompt: "Durchsuchen")
        .onSubmit(of: .search) {
            let words = SettingsSearch.words(search)
            guard !words.isEmpty, let group = searchGroups(words).first else { return }
            if let entry = group.entries.first {
                open(entry)
            } else {
                select(group.pane)
            }
        }
        .frame(minWidth: Self.windowSize.width, idealWidth: Self.windowSize.width,
               minHeight: 560, idealHeight: Self.windowSize.height)
        .tint(themeColor(.accent))
        .environment(\.interfaceStyle, app.settings.interfaceStyle)
        .environment(\.glassPanels, app.settings.glassPanels)
        .background { WindowContentSize(width: Self.windowSize.width, height: Self.windowSize.height) }
        .background { WindowAppearance(theme: app.settings.theme) }
        .background { UnifiedWindowToolbar() }
        .confirmationDialog(
            "Die Bibliothek der App wird ersetzt. Bitte die App danach neu starten.",
            isPresented: Binding(get: { pendingLibrary != nil }, set: { if !$0 { pendingLibrary = nil } }),
            titleVisibility: .visible
        ) {
            Button("Bibliothek ersetzen", role: .destructive) { activateLibrary() }
            Button("Abbrechen", role: .cancel) { pendingLibrary = nil }
        } message: {
            Text("Die bisherige Bibliothek wird als Sicherung aufbewahrt und lässt sich hier wiederherstellen.")
        }
        .onReceive(NotificationCenter.default.publisher(for: .openAboutPane)) { _ in
            select(.about)
        }
    }

    /// The room between the edge of the sidebar and the arrows.
    private static let arrowsInset: CGFloat = 20
    /// The room between the arrows and the title of the area.
    private static let titleGap: CGFloat = 10

    /// Back and forth through the visited areas.
    private var historyArrows: some View {
        ControlGroup {
            Button { step(-1) } label: { Label("Zurück", systemImage: "chevron.left") }
                .disabled(historyIndex == 0)
                .keyboardShortcut("[", modifiers: .command)
                .help("Zurück (⌘[)")
            Button { step(1) } label: { Label("Vor", systemImage: "chevron.right") }
                .disabled(historyIndex >= history.count - 1)
                .keyboardShortcut("]", modifiers: .command)
                .help("Vor (⌘])")
        }
        .controlGroupStyle(.navigation)
    }

    /// The areas on the left: the system sidebar list. While searching it
    /// shows the matching areas with the controls found in them.
    private var sidebar: some View {
        // No list selection: macOS would draw it in the system accent (blue
        // by default). The rows draw the chosen one in the theme's accent.
        List {
            let words = SettingsSearch.words(search)
            if words.isEmpty {
                ForEach(Pane.allCases) { item in
                    sidebarRow(item)
                }
            } else {
                let groups = searchGroups(words)
                if groups.isEmpty {
                    Text("Keine Treffer")
                        .foregroundStyle(.secondary)
                }
                ForEach(groups) { group in
                    sidebarRow(group.pane)
                    ForEach(group.entries) { entry in
                        resultRow(entry)
                    }
                }
            }
        }
        .listStyle(.sidebar)
    }

    /// One area of the sidebar; the chosen one stands on the accent.
    private func sidebarRow(_ item: Pane) -> some View {
        let chosen = item == pane
        return Button {
            select(item)
        } label: {
            Label {
                Text(item.title)
                    .foregroundStyle(chosen ? onAccent : Color.primary)
            } icon: {
                Image(systemName: item.icon)
                    .foregroundStyle(chosen ? onAccent : themeColor(.accent))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chosen ? themeColor(.accent) : .clear)
                .padding(.horizontal, 10))
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    /// The text on the accent: dark on a bright accent, white on a deep one.
    private var onAccent: Color {
        let accent = ThemeRGB(hex: ThemeRuntime.shared.hex(.accent, dark: colorScheme == .dark)) ?? .black
        return accent.luminance > 0.4 ? Color.black.opacity(0.85) : .white
    }

    /// A control the search found; it opens its area and lights it up.
    private func resultRow(_ entry: SettingsSearchEntry) -> some View {
        Button {
            open(entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .lineLimit(1)
                Text(entry.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(entry.id == highlight
                           ? RoundedRectangle(cornerRadius: 6).fill(themeColor(.accentSoft)) : nil)
    }

    /// Shows the area of `entry`, scrolls to the control and lights it up.
    private func open(_ entry: SettingsSearchEntry) {
        if entry.id.hasPrefix("formats.visible.") || entry.id.hasPrefix("formats.notify.") {
            formatQuery = ""
            formatFilter = .all
        }
        select(entry.pane)
        highlight = entry.id
        jumps += 1
    }

    /// The page of the area; the toolbar above it holds the arrows and the
    /// name of the area.
    private var detail: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                Form {
                    if let settingsError {
                        Section {
                            Text(settingsError)
                                .foregroundStyle(.red)
                        }
                    }
                    page
                    Section {
                    } footer: {
                        Text("Orangeflix for Mac · Version \(AccountModel.appVersion)")
                            .font(.footnote)
                    }
                }
                .formStyle(.grouped)
                // Every button of the pages is a Liquid Glass button; cards
                // and rows with their own style keep it.
                .glassButtonStyle()
                .scrollContentBackground(.hidden)
                .environment(\.settingsHighlight, highlight)
                .task(id: jumps) {
                    guard jumps > 0, let target = highlight else { return }
                    // The page of another area needs a moment to appear.
                    try? await Task.sleep(for: .milliseconds(80))
                    guard !Task.isCancelled, highlight == target else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    highlight = nil
                }
            }
        }
        .background(themeColor(.background))
    }

    /// Shows `next` and remembers the way there.
    private func select(_ next: Pane) {
        guard next != pane else { return }
        highlight = nil
        history = Array(history.prefix(historyIndex + 1))
        history.append(next)
        historyIndex = history.count - 1
        pane = next
    }

    /// Walks the visited areas.
    private func step(_ direction: Int) {
        let next = historyIndex + direction
        guard history.indices.contains(next) else { return }
        highlight = nil
        historyIndex = next
        pane = history[next]
    }

    /// The areas and controls that match the search, in the order of the
    /// sidebar. An area stays when its name matches or one of its controls.
    private func searchGroups(_ words: [String]) -> [SettingsSearchGroup] {
        let found = searchEntries.filter { $0.matches(words) }
        return Pane.allCases.compactMap { item in
            let entries = found.filter { $0.pane == item }
            let name = SettingsSearch.fold("\(item.title) \(item.keywords)")
            guard !entries.isEmpty || words.allSatisfy({ name.contains($0) }) else { return nil }
            return SettingsSearchGroup(pane: item, entries: entries)
        }
    }

    /// Every control the search knows: the fixed ones, the themes and the
    /// formats of the catalog.
    private var searchEntries: [SettingsSearchEntry] {
        let settings = app.settings
        let themes = [false, true].flatMap { dark in
            ([AppTheme.standard(dark: dark)] + AppTheme.builtIn(dark: dark)
                + settings.importedThemes.filter { $0.isDark == dark })
                .map { theme in
                    SettingsSearchEntry(id: "appearance.theme.\(theme.id)", pane: .appearance, title: theme.name,
                                        section: dark ? "Dunkler Modus" : "Heller Modus", keywords: "theme farben")
                }
        }
        let formats = browse.formats.flatMap { format in
            [
                SettingsSearchEntry(id: "formats.visible.\(format.pid)", pane: .formats, title: format.title,
                                    section: "Formate · Mediathek", keywords: "format anzeigen mediathek ausblenden"),
                SettingsSearchEntry(id: "formats.notify.\(format.pid)", pane: .formats, title: format.title,
                                    section: "Formate · Mitteilungen", keywords: "format melden benachrichtigung mitteilung"),
            ]
        }
        let all = SettingsSearch.entries + themes + formats
        // Signed out, the pages of the account have no rows to jump to.
        let accountPages: Set<Pane> = [.account, .profile, .sharing]
        return app.hasCredentials ? all : all.filter { !accountPages.contains($0.pane) }
    }

    // MARK: Seiten

    @ViewBuilder private var page: some View {
        switch pane {
        case .general: generalPage
        case .account: accountPage
        case .profile: profilePage
        case .sharing: sharingPage
        case .appearance: appearancePage
        case .downloads: downloadsPage
        case .streaming: streamingPage
        case .live: livePage
        case .formats: formatsPage
        case .transfer: transferPage
        case .about: aboutPage
        }
    }

    /// The Konto page; without a login it only says so, the login itself
    /// lives in the main window.
    @ViewBuilder private var accountPage: some View {
        if app.hasCredentials {
            signedInAccountPage
        } else {
            Section {
                Text("Nicht angemeldet")
                    .foregroundStyle(.secondary)
            } footer: {
                Text("Die Anmeldung erfolgt im Hauptfenster.")
            }
        }
    }

    private var signedInAccountPage: some View {
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
                if let data = account.avatar, let image = NSImage(data: data) {
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
        let formatter = DateFormatter()
        formatter.locale = Self.german
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: date)
    }

    // MARK: Profil, Sharing und Mitteilungen

    /// The data of the account: the name, the address, the birthday, the
    /// credits and the legal confirmations.
    private var profilePage: some View {
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
                    TextField("Anzeigename", text: nameBinding)
                        .searchAnchor("profile.name")
                    TextField("Chatname", text: chatnameBinding)
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
                            if !trimmedChatname.isEmpty,
                               trimmedChatname != profile.savedChatname,
                               trimmedChatname != account.details?.chatname {
                                await profile.setChatname(trimmedChatname)
                            }
                        }
                    }
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
                                Button("Löschen", role: .destructive) {
                                    Task { await profile.deleteAddress() }
                                }
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
                                Button("Löschen", role: .destructive) {
                                    Task { await profile.deleteBirthday() }
                                }
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
                                Button("Löschen", role: .destructive) {
                                    Task { await profile.deleteCredits() }
                                }
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
                        Button(profile.privacyConfirmed ? "Erneut bestätigen" : "Jetzt bestätigen") {
                            Task { await profile.acceptPrivacy() }
                        }
                        .disabled(profile.isSaving)
                        .searchAnchor("profile.acceptPrivacy")
                    }
                    .searchAnchor("profile.privacy")

                    ProfileCard(symbol: "doc.text",
                                title: "Allgemeine Geschäftsbedingungen",
                                text: "Die Bestätigung gilt für die aktuelle Fassung der AGB.",
                                state: profile.agbConfirmed ? "bestätigt" : "offen",
                                isSet: profile.agbConfirmed) {
                        Button(profile.agbConfirmed ? "Erneut bestätigen" : "Jetzt bestätigen") {
                            Task { await profile.acceptAGB() }
                        }
                        .disabled(profile.isSaving)
                        .searchAnchor("profile.acceptAGB")
                    }
                    .searchAnchor("profile.agb")
                } header: {
                    Text("Rechtliches")
                } footer: {
                    Text("Die Version der Texte bestimmt der Server; die App bestätigt die aktuelle.")
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
                    if !exclusionFilter.isEmpty {
                        Button("Filter leeren", role: .destructive) {
                            Task { await profile.clearExclusionFilter() }
                        }
                    }
                } header: {
                    Text("Feed-Filter")
                } footer: {
                    Text("Die ausgeschalteten Kategorien bleiben im Haupt-Feed aus.")
                }
            }
        }
        .task {
            if app.hasCredentials, profile.preferences == nil { await profile.load() }
            if name.isEmpty {
                let known = profile.savedName.isEmpty ? (account.details?.name ?? "") : profile.savedName
                name = known
            }
            if chatname.isEmpty {
                chatname = profile.savedChatname.isEmpty ? (account.details?.chatname ?? "") : profile.savedChatname
            }
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

    /// The sharing links of the account: the quota of the month and the
    /// links that exist.
    private var sharingPage: some View {
        Group {
            Section {
                LabeledContent("Kontingent") { Text(sharing.quotaText) }
                    .searchAnchor("sharing.quota")
                Button("Neu laden") { Task { await sharing.load() } }
                    .disabled(sharing.isLoading)
                    .searchAnchor("sharing.reload")
            } header: {
                Text("Kontingent")
            } footer: {
                Text("Jeder Link erlaubt eine begrenzte Zahl von Aufrufen. Ein Link, der schon benutzt wurde, lässt sich nicht mehr beenden.")
            }

            if let link = sharing.freshLink {
                Section {
                    LabeledContent("Link") {
                        Text(link.url.isEmpty ? link.code : link.url)
                            .textSelection(.enabled)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Button("Link kopieren") {
                            AppFormat.copy(link.url.isEmpty ? link.code : link.url)
                        }
                        Button("Fertig") { sharing.dismissFreshLink() }
                    }
                } header: {
                    Text("Neuer Link")
                } footer: {
                    Text("Der Link ist auf \(link.accessLimit) Aufrufe begrenzt.")
                }
            }

            Section {
                if sharing.links.isEmpty {
                    Text(sharing.isLoading ? "Die Links werden geladen …" : "Es gibt noch keine Sharing-Links.")
                        .foregroundStyle(.secondary)
                }
                ForEach(sharing.links, id: \.code) { link in
                    sharingRow(link)
                }
            } header: {
                Text("Links")
            }

            Section {
                TextField("Code", text: $shareCode, prompt: Text("Code eines Links"))
                Button("Code prüfen") {
                    Task { shareCheck = await sharing.inspect(code: shareCode) }
                }
                .searchAnchor("sharing.check")
                if let shareCheck {
                    Text(shareCheck)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } header: {
                Text("Code prüfen")
            } footer: {
                Text("Prüft einen Link, ohne angemeldet zu sein.")
            }
        }
        .task {
            if sharing.links.isEmpty, !sharing.isLoading { await sharing.load() }
        }
    }

    /// One sharing link with its state and the buttons that act on it.
    private func sharingRow(_ link: SharingLinkEntry) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            LabeledContent(link.clipId) {
                Text(link.unlimited ? "unbegrenzt" : (link.remaining.map { "\($0) übrig" } ?? "—"))
                    .foregroundStyle(.secondary)
            }
            Text(link.createdDate.map { "Angelegt am \(AppFormat.day($0))" } ?? "Unbenutzter Link")
                .font(AppFont.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Button("Code kopieren") { AppFormat.copy(link.code) }
                Button("Beenden") { Task { await sharing.revoke(link.code) } }
                    .disabled(!link.isRevocable)
            }
        }
    }

    /// App-wide preferences that were previously split across several panes.
    private var generalPage: some View {
        Group {
            Section {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Updates für Orangeflix for Mac")
                        Text("Neue Versionen mit Änderungen und Fehlerbehebungen abrufen.")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                    }
                    Spacer(minLength: Space.m)
                    Button("Nach Updates suchen …") {
                        updaterController.checkForUpdates(nil)
                    }
                }
                .searchAnchor("about.updates")

                Toggle("Automatisch nach Updates suchen", isOn: automaticUpdateChecksBinding)
                    .searchAnchor("about.automaticUpdates")
                Picker("Suchintervall", selection: updateCheckIntervalBinding) {
                    Text("Täglich").tag(TimeInterval(86_400))
                    Text("Wöchentlich").tag(TimeInterval(604_800))
                    Text("Monatlich").tag(TimeInterval(2_592_000))
                }
                .disabled(!automaticUpdateChecks)
                .searchAnchor("about.updateInterval")
            } header: {
                Text("Softwareupdate")
            } footer: {
                Text("Automatische Suchen erfolgen im gewählten Intervall, solange Orangeflix läuft. Vor der Installation prüft der Updater die Signatur des Downloads; die Versionshinweise erscheinen im Update-Fenster.")
            }

            Section {
                LabeledContent("Ordner") {
                    Text(AppFormat.displayPath(app.downloadFolder))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .searchAnchor("storage.folder")
                Button("Ordner ändern …") { chooseFolder() }
                    .searchAnchor("storage.change")
                Button("Im Finder zeigen") { AppFormat.reveal(app.downloadFolder) }
                    .searchAnchor("storage.reveal")
                Button("Auf ~/Downloads/Orangeflix zurücksetzen") { resetFolder() }
                    .searchAnchor("storage.reset")
            } header: { Text("Speicherort") } footer: { Text("Wohin die Downloads geschrieben werden.") }

            Section {
                Toggle("Neue Folgen melden", isOn: notificationsBinding)
                    .searchAnchor("general.newEpisodes")
                Toggle("Livestreams melden", isOn: liveNotificationsBinding)
                    .searchAnchor("general.liveNotifications")
                HStack {
                    Button("Testmitteilung senden") {
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
                Text("Mitteilungen")
            } footer: {
                if let error = watcher.lastError {
                    Text(error)
                } else if watcher.isAllowed {
                    Text("Die App prüft alle 15 Minuten die neuesten Folgen und alle 2 Minuten, ob ein Livestream läuft. Ein Klick auf eine Mitteilung öffnet das Format oder die Live-Seite.")
                } else {
                    Text("macOS hat die Mitteilungen für Orangeflix noch nicht erlaubt.")
                }
            }

            notificationsPage
            backgroundSection
        }
    }

    /// The notifications of the account: the events of the catalog, the
    /// channels and the devices.
    private var notificationsPage: some View {
        Group {
            if !app.hasCredentials {
                Section {
                    Text("Nicht angemeldet")
                        .foregroundStyle(.secondary)
                } footer: {
                    Text("Die Anmeldung erfolgt im Hauptfenster.")
                }
            } else {
                Section {
                    ForEach(notifications.channelNames, id: \.self) { channel in
                        Toggle(NotificationSettingsModel.channelName(channel), isOn: channelBinding(channel))
                    }
                    Button("Testmitteilung senden") {
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
                        Text(notifications.isLoading ? "Der Katalog wird geladen …" : "Der Server nennt keine Ereignisse.")
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
                                Button("Abmelden") {
                                    Task { await notifications.removeDevice(device.deviceID) }
                                }
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
                    Text("Hier stehen Geräte, die für Push-Mitteilungen des Servers registriert sind – nicht alle angemeldeten Sitzungen. Die Mitteilungen dieser Mac-App werden separat unter „Mitteilungen“ eingerichtet.")
                }
            }
        }
        .task(id: app.hasCredentials) {
            if app.hasCredentials { await notifications.load() }
        }
    }

    /// The look of the app on one page: the color scheme, the interface
    /// style, the theme of each mode, the import of terminal themes and the
    /// symbol in the Dock.
    private var appearancePage: some View {
        Group {
            Section {
                HStack(alignment: .top, spacing: Space.m) {
                    ForEach([AppSettings.Theme.auto, .light, .dark], id: \.self) { theme in
                        SettingsChoiceCard(
                            title: Self.capitalized(theme.label),
                            isSelected: app.settings.theme == theme,
                            action: { themeBinding.wrappedValue = theme }
                        ) {
                            ModePreview(theme: theme)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .searchAnchor("appearance.mode")
            } header: {
                Text("Farbschema")
            } footer: {
                Text("Gilt für alle Fenster der App. „Automatisch“ folgt der Einstellung des Macs.")
            }

            Section {
                HStack(alignment: .top, spacing: Space.m) {
                    ForEach(AppSettings.InterfaceStyle.allCases, id: \.self) { style in
                        SettingsChoiceCard(
                            title: style.shellTitle,
                            isSelected: app.settings.interfaceStyle == style,
                            action: { apply { $0.interfaceStyle = style } }
                        ) {
                            InterfaceStylePreview(style: style)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .searchAnchor("appearance.style")
                Toggle("Mit Theme einfärben", isOn: tintWithThemeBinding)
                    .searchAnchor("appearance.tint")
                Toggle("Glas für Flächen", isOn: glassPanelsBinding)
                    .disabled(app.settings.interfaceStyle == .classic)
                    .searchAnchor("appearance.glass")
            } header: {
                Text("Oberflächenstil")
            } footer: {
                Text("Klassisch füllt Leisten und Panels mit einer ruhigen Fläche, Glas zeichnet sie durchscheinend. Ohne „Mit Theme einfärben“ bleiben die Flächen des Themes, der Akzent bleibt das Orangeflix-Orange.")
            }

            themeSection("Heller Modus", dark: false)
            themeSection("Dunkler Modus", dark: true)

            Section {
                LabeledContent("Ghostty- oder iTerm-Themedatei") {
                    Button("Importieren …") { chooseThemeFile() }
                        .searchAnchor("appearance.import")
                }
            } header: {
                Text("Theme importieren")
            } footer: {
                Text("Themes werden anhand ihrer Hintergrundfarbe einem Erscheinungsbild zugeordnet.")
            }

            Section {
                HStack(alignment: .top, spacing: Space.m) {
                    ForEach(AppSettings.AppIcon.allCases, id: \.self) { icon in
                        SettingsChoiceCard(
                            title: icon.shellTitle,
                            isSelected: app.settings.appIcon == icon,
                            action: { apply { $0.appIcon = icon } }
                        ) {
                            AppIconArt(style: icon, dark: colorScheme == .dark)
                                .frame(width: 62, height: 62)
                                .frame(width: 118, height: 70)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .searchAnchor("appearance.appIcon")
            } header: {
                Text("App-Symbol")
            } footer: {
                Text("Das Symbol im Dock wechselt sofort; „Standard“ folgt dabei dem hellen und dem dunklen Erscheinungsbild. Im Finder behält die App das Symbol ihres Pakets.")
            }
        }
    }

    /// A color of the active theme, as a new value whenever the theme
    /// changes, so the window repaints.
    private func themeColor(_ token: ThemeToken) -> Color {
        Color(hex: ThemeRuntime.shared.hex(token, dark: colorScheme == .dark))
    }

    private func themeSection(_ title: String, dark: Bool) -> some View {
        let settings = app.settings
        let selected = AppTheme.resolve(
            id: dark ? settings.darkThemeID : settings.lightThemeID, dark: dark,
            imported: settings.importedThemes).id
        let others = AppTheme.builtIn(dark: dark) + settings.importedThemes.filter { $0.isDark == dark }
        return Section {
            HStack(alignment: .top, spacing: Space.m) {
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Standard").font(.caption).foregroundStyle(.secondary)
                    ThemeCard(theme: AppTheme.standard(dark: dark), isSelected: selected == AppTheme.standard(dark: dark).id) {
                        chooseTheme(AppTheme.standard(dark: dark).id, dark: dark)
                    }
                    .searchAnchor("appearance.theme.\(AppTheme.standard(dark: dark).id)")
                }
                Divider().frame(height: 100)
                VStack(alignment: .leading, spacing: Space.xs) {
                    Text("Integriert").font(.caption).foregroundStyle(.secondary)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.m) {
                            ForEach(others) { theme in
                                ThemeCard(theme: theme, isSelected: selected == theme.id) {
                                    chooseTheme(theme.id, dark: dark)
                                }
                                .contextMenu {
                                    if theme.id.hasPrefix("import-") {
                                        Button("Theme entfernen", role: .destructive) { removeTheme(theme) }
                                    }
                                }
                                .searchAnchor("appearance.theme.\(theme.id)")
                            }
                        }
                    }
                }
            }
            .padding(.vertical, Space.xs)
            Toggle("Erweiterte Theme-Palette verwenden", isOn: extendedBinding(dark: dark))
                .searchAnchor(dark ? "appearance.darkExtended" : "appearance.lightExtended")
        } header: {
            HStack(spacing: Space.xs) {
                Text(title)
                if (colorScheme == .dark) == dark {
                    Text("— Aktiv").foregroundStyle(.secondary)
                }
            }
        } footer: {
            if !(dark ? settings.darkExtendedPalette : settings.lightExtendedPalette) {
                if settings.tintWithTheme {
                    Text("Aus: Nur die Akzentfarbe des Themes wird übernommen, Flächen und Texte bleiben beim Standard.")
                } else {
                    Text("Aus: Flächen und Texte bleiben beim Standard, der Akzent bleibt Orangeflix-Orange.")
                }
            }
        }
    }

    private func extendedBinding(dark: Bool) -> Binding<Bool> {
        Binding(
            get: { dark ? app.settings.darkExtendedPalette : app.settings.lightExtendedPalette },
            set: { value in
                apply { if dark { $0.darkExtendedPalette = value } else { $0.lightExtendedPalette = value } }
            })
    }

    private func chooseTheme(_ id: String, dark: Bool) {
        apply { if dark { $0.darkThemeID = id } else { $0.lightThemeID = id } }
    }

    private func removeTheme(_ theme: AppTheme) {
        apply { settings in
            settings.importedThemes.removeAll { $0.id == theme.id }
            if settings.lightThemeID == theme.id { settings.lightThemeID = AppTheme.orangeflixLight.id }
            if settings.darkThemeID == theme.id { settings.darkThemeID = AppTheme.orangeflixDark.id }
        }
    }

    private func chooseThemeFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Importieren"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in importTheme(url) }
        }
    }

    private func importTheme(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let theme = try ThemeImporter.theme(from: data, name: url.deletingPathExtension().lastPathComponent)
            apply { settings in
                settings.importedThemes.removeAll { $0.id == theme.id }
                settings.importedThemes.append(theme)
                if theme.isDark { settings.darkThemeID = theme.id } else { settings.lightThemeID = theme.id }
            }
            app.show("Theme „\(theme.name)“ für den \(theme.isDark ? "dunklen" : "hellen") Modus importiert")
        } catch {
            settingsError = error.localizedDescription
            app.show(error)
        }
    }

    private var downloadsPage: some View {
        Group {
            Section {
                Picker("Qualität", selection: qualityBinding) {
                    ForEach(AppSettings.Quality.allCases, id: \.self) { quality in
                        Text(quality.shellTitle).tag(quality)
                    }
                }
                .searchAnchor("downloads.quality")
                Picker("Ablage", selection: layoutBinding) {
                    ForEach(AppSettings.Layout.allCases, id: \.self) { layout in
                        Text(layout.shellTitle).tag(layout)
                    }
                }
                .searchAnchor("downloads.layout")
            } header: {
                Text("Dateien")
            } footer: {
                Text("Die Qualität der Datei, die auf die Platte geht. Die Ablage legt einen Ordner je Folge an.")
            }

            Section {
                LabeledContent("Gleichzeitig") {
                    HStack(spacing: Space.s) {
                        Text("\(app.settings.parallel)")
                            .monospacedDigit()
                        Stepper("Gleichzeitig", value: parallelBinding, in: AppSettings.parallelRange)
                            .labelsHidden()
                    }
                }
                .searchAnchor("downloads.parallel")
                LabeledContent("Pause") {
                    TextField("", value: delayBinding, format: Self.delayFormat)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                .searchAnchor("downloads.delay")
                LabeledContent("Tempolimit") {
                    TextField("", value: limitBinding, format: Self.limitFormat)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                .searchAnchor("downloads.limit")
            } header: {
                Text("Tempo")
            } footer: {
                Text("Gleichzeitige Downloads 1–8, Pause 0–3600 Sekunden, Tempolimit in KiB pro Sekunde (0 heißt ohne Limit).")
            }

            Section {
                Toggle("Vorschaubild speichern", isOn: thumbBinding)
                    .searchAnchor("downloads.thumb")
                Toggle("Metadaten speichern", isOn: metaBinding)
                    .searchAnchor("downloads.meta")
            } header: {
                Text("Begleitdateien")
            } footer: {
                Text("Vorschaubild und Angaben als JSON landen neben dem Video.")
            }
        }
    }

    private var streamingPage: some View {
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
    }

    /// The Live page: where the chat starts, how it reads and how the
    /// votings show.
    private var livePage: some View {
        Group {
            Section {
                Toggle("Beim Öffnen zeigen", isOn: liveChatOpenBinding)
                    .searchAnchor("live.chatStart")
                Picker("Position", selection: liveChatPositionBinding) {
                    Text("Im Größen-Menü wählen").tag(AppSettings.LiveChatPosition.auto)
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
                Text("Automatisch: Der Chat steht dort, wo du ihn auf der Live-Seite im Größen-Menü wählst. Das Live-Fenster hat feste Größen, die genau zu Video und Chat passen.")
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

    /// The catalog: what the Mediathek lists and what may send a message.
    /// One list with a search and a filter; every row switches both.
    private var formatsPage: some View {
        Group {



            Section {
                SettingsFormatSearch(query: $formatQuery, filter: $formatFilter, counts: formatFilterCounts)
                let shown = filteredFormats
                if browse.formats.isEmpty {
                    Text("Der Katalog wird geladen …")
                        .foregroundStyle(.secondary)
                } else if shown.isEmpty {
                    Text(formatQuery.isEmpty ? "Kein Format in dieser Auswahl." : "Kein Format passt zu „\(formatQuery)“.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, Space.s)
                } else {
                    ForEach(shown, id: \.pid) { format in
                        SettingsFormatRow(
                            format: format,
                            visible: visibleBinding(format.pid),
                            notify: notifyBinding(format.pid),
                            notificationsOn: app.settings.notificationsOn)
                    }
                }
            } header: {
                HStack(alignment: .firstTextBaseline) {
                    Text("Formate")
                    Spacer()
                    Text(formatSummary)
                        .font(.caption)
                        .lineLimit(1)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            } footer: {
                formatBulkActions
            }
        }
    }

    /// Keeps the checks running after the window closes, and after a login.
    private var backgroundSection: some View {
        Section {
            Toggle("Im Hintergrund weiterlaufen", isOn: runsInBackgroundBinding)
                .searchAnchor("formats.background")
            Toggle("Bei der Anmeldung starten", isOn: Binding(
                get: { background.launchesAtLogin || background.needsApproval },
                set: { background.setLaunchAtLogin($0) }))
                .searchAnchor("formats.login")
            if background.needsApproval {
                Button("In den Anmeldeobjekten erlauben") { background.openLoginItemSettings() }
            }
        } header: {
            Text("Im Hintergrund")
        } footer: {
            if let error = background.loginError {
                Text(error)
            } else if background.needsApproval {
                Text("macOS wartet auf deine Erlaubnis unter Systemeinstellungen › Allgemein › Anmeldeobjekte.")
            } else {
                Text("Schließt du das Fenster, verschwindet Orangeflix aus dem Dock und bleibt als Symbol in der Menüleiste, damit Mitteilungen weiter ankommen. Beim Start nach der Anmeldung öffnet sich kein Fenster. Mit ⌘Q beendet, meldet die App nichts mehr.")
            }
        }
        .onAppear { background.refreshLoginItem() }
    }

    /// "38 von 40 in der Mediathek · 5 gemeldet"
    private var formatSummary: String {
        let all = browse.formats
        guard !all.isEmpty else { return "" }
        let hidden = Set(app.settings.hiddenMagazines)
        let visible = all.filter { !hidden.contains($0.pid) }.count
        let notified = all.filter { app.settings.notifiedMagazines.contains($0.pid) }.count
        return "\(visible)/\(all.count) sichtbar · \(notified) gemeldet"
    }

    private func matches(_ format: Format, _ filter: SettingsFormatFilter) -> Bool {
        switch filter {
        case .all: true
        case .visible: !app.settings.hiddenMagazines.contains(format.pid)
        case .hidden: app.settings.hiddenMagazines.contains(format.pid)
        case .notified: app.settings.notifiedMagazines.contains(format.pid)
        }
    }

    /// The formats matching the search text, before the filter.
    private var searchedFormats: [Format] {
        let query = formatQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        let sorted = browse.formats.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        guard !query.isEmpty else { return sorted }
        return sorted.filter {
            $0.title.localizedStandardContains(query) || $0.slug.localizedStandardContains(query)
                || $0.handle.localizedStandardContains(query)
        }
    }

    private var filteredFormats: [Format] {
        searchedFormats.filter { matches($0, formatFilter) }
    }

    private var formatFilterCounts: [SettingsFormatFilter: Int] {
        let searched = searchedFormats
        var counts: [SettingsFormatFilter: Int] = [:]
        for filter in SettingsFormatFilter.allCases {
            counts[filter] = searched.filter { matches($0, filter) }.count
        }
        return counts
    }

    /// Acts on the rows that show now: everything, or only the hits.
    private var formatBulkActions: some View {
        let shown = filteredFormats.map(\.pid)
        let narrowed = !formatQuery.isEmpty || formatFilter != .all
        let scope = narrowed ? "Treffer" : "Alle"
        let hidden = Set(app.settings.hiddenMagazines)
        let notified = Set(app.settings.notifiedMagazines)
        return VStack(alignment: .leading, spacing: Space.s) {
            FlowLayout(spacing: Space.s) {
                Button("\(scope) anzeigen") {
                    apply { $0.hiddenMagazines.removeAll { shown.contains($0) } }
                }
                .disabled(shown.allSatisfy { !hidden.contains($0) })
                .searchAnchor("formats.showAll")
                Button("\(scope) ausblenden") {
                    apply { settings in
                        for pid in shown where !settings.hiddenMagazines.contains(pid) { settings.hiddenMagazines.append(pid) }
                        settings.notifiedMagazines.removeAll { shown.contains($0) }
                    }
                }
                .disabled(shown.allSatisfy { hidden.contains($0) })
                .searchAnchor("formats.hideAll")
                Button("\(scope) melden") {
                    apply { settings in
                        for pid in shown where !settings.notifiedMagazines.contains(pid) && !settings.hiddenMagazines.contains(pid) {
                            settings.notifiedMagazines.append(pid)
                        }
                        settings.notificationsOn = true
                    }
                    Task { await watcher.refreshPermission() }
                }
                .disabled(shown.allSatisfy { notified.contains($0) || hidden.contains($0) })
                .searchAnchor("formats.notifyAll")
                Button(narrowed ? "Treffer nicht melden" : "Keine melden") {
                    apply { $0.notifiedMagazines.removeAll { shown.contains($0) } }
                }
                .disabled(shown.allSatisfy { !notified.contains($0) })
                .searchAnchor("formats.notifyNone")
            }
            .controlSize(.small)
            Text("„Mediathek“ zeigt ein Format in der Mediathek; die Bibliothek bleibt. „Melden“ schickt eine Mitteilung, sobald eine neue Folge erscheint. Ausgeblendete Formate werden nicht gemeldet.")
        }
    }

    /// Import and export: the backup of the app, the settings file of the
    /// command line tool and the library.
    private var transferPage: some View {
        Group {
            if let transferMessage {
                Section {
                    Label {
                        Text(transferMessage)
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: transferFailed ? "xmark.octagon.fill" : "checkmark.circle.fill")
                            .foregroundStyle(transferFailed ? Palette.danger : Palette.success)
                    }
                    .textSelection(.enabled)
                }
            }

            Section {
                transferRow(
                    "Sicherung", detail: "Alle Einstellungen, Themes und die Auswahl der Formate",
                    symbol: "gearshape.2",
                    export: ("transfer.backupExport", exportBackup),
                    import: ("transfer.backupImport", { chooseFile(prompt: "Importieren", then: importBackup) }))
            } header: {
                Text("Orangeflix")
            } footer: {
                Text("Für einen zweiten Mac oder als Sicherung. Anmeldung und Speicherort bleiben auf diesem Mac.")
            }

            Section {
                transferRow(
                    "config", detail: "Qualität, Ablage, Feed-Variante, Tempo und Begleitdateien",
                    symbol: "terminal",
                    export: ("transfer.configExport", exportConfig),
                    import: ("transfer.configImport", { chooseFile(prompt: "Importieren", then: importConfig) }))
            } header: {
                Text("Kommandozeilen-Werkzeug")
            } footer: {
                Text("Das Werkzeug liest die Datei unter ~/.config/orangeflix-dl/config. Beim Import bleiben ungültige Werte außen vor.")
            }

            Section {
                transferRow(
                    "library.db", detail: libraryDetail,
                    symbol: "books.vertical",
                    export: ("transfer.libraryExport", exportLibrary),
                    import: ("transfer.libraryImport", { chooseFile(prompt: "Importieren", then: stageLibrary) }))
                if let date = SettingsTransfer.previousLibraryDate() {
                    LabeledContent {
                        Button("Wiederherstellen …", systemImage: "clock.arrow.circlepath") { restorePreviousLibrary() }
                            .searchAnchor("transfer.libraryRestore")
                    } label: {
                        Text("Vorherige Bibliothek")
                        Text("Gesichert am \(date.formatted(date: .numeric, time: .shortened))")
                    }
                }
            } header: {
                Text("Bibliothek")
            } footer: {
                Text("Die Bibliothek merkt sich Formate, bekannte und geladene Folgen; das Werkzeug benutzt dieselbe Datei. Ein Import ersetzt sie, die bisherige bleibt als Sicherung. Danach die App neu starten.")
            }
        }
        .task { await account.refreshLibrary(minimumInterval: 5) }
    }

    /// What the app is, which version runs, under which licence it stands and
    /// — the point of the page — that it is an independent project.
    private var aboutPage: some View {
        Group {
            Section {
                HStack(spacing: Space.m) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 56, height: 56)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Orangeflix for Mac")
                            .font(AppFont.heading)
                        Text("Version \(AccountModel.appVersion)")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                            .textSelection(.enabled)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("App")
            } footer: {
                Text("Ein inoffizielles Zusatzprogramm für macOS, um die Mediathek eines Orangeflix.de-Kontos am Schreibtisch zu nutzen.")
            }


            Section {
                HStack(spacing: Space.m) {
                    AsyncImage(url: URL(string: "https://www.gravatar.com/avatar/f163b408cf74e04d857c250fb31a67a81ba22f4706ba5a7fca4eaee9b4ad8ced?s=192&d=identicon")) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Image(systemName: "person.crop.circle.fill")
                            .resizable()
                            .foregroundStyle(themeColor(.textSecondary))
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .accessibilityLabel("GitHub-Profilbild von Alexander")

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Entwickelt von")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                        Link(destination: URL(string: "https://github.com/revunix")!) {
                            HStack(spacing: Space.xs) {
                                Text("Alexander")
                                    .font(AppFont.heading)
                                Text("@revunix")
                                    .font(AppFont.bodySmall)
                                    .foregroundStyle(themeColor(.textSecondary))
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .buttonStyle(.plain)
                        Text("„it should work“ · Deutschland")
                            .font(AppFont.bodySmall)
                            .foregroundStyle(themeColor(.textSecondary))
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, Space.xs)
            } header: {
                Text("Entwickler")
            }

            Section {
                Text("Orangeflix for Mac ist ein unabhängiges, privat entwickeltes Projekt. Es steht in keiner Verbindung zu Orangeflix.de, zu deren Betreibern oder zu einem anderen Programm gleichen Namens. Es ist weder von dort beauftragt noch freigegeben, unterstützt oder mitgetragen.")
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .searchAnchor("about.independence")
            } header: {
                Text("Keine Verbindung zur Plattform")
            } footer: {
                Text("Der Name beschreibt nur, wofür die App gedacht ist. Marken und Namen gehören ihren jeweiligen Inhabern.")
            }

            Section {
                LabeledContent("Freigabe") {
                    Text("MIT")
                        .textSelection(.enabled)
                }
                .searchAnchor("about.license")
                Text("Der Quelltext steht unter der MIT-Lizenz. Er darf benutzt, verändert und weitergegeben werden, solange der Lizenztext und der Urheberrechtshinweis erhalten bleiben. Für die Nutzung gilt keine Gewährleistung.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(themeColor(.textSecondary))
            } header: {
                Text("Lizenz")
            }

            Section {
                Text("Die App greift auf die Schnittstellen von Orangeflix.de zu und braucht dafür ein Konto dort. Für Inhalte, Zugänge und Bedingungen ist der Anbieter verantwortlich, nicht dieses Programm.")
                    .fixedSize(horizontal: false, vertical: true)
                    .foregroundStyle(themeColor(.textSecondary))
            } header: {
                Text("Inhalte und Zugang")
            }
        }
    }

    private var automaticUpdateChecksBinding: Binding<Bool> {
        Binding(
            get: { automaticUpdateChecks },
            set: { value in
                automaticUpdateChecks = value
                updaterController.updater.automaticallyChecksForUpdates = value
            })
    }

    private var updateCheckIntervalBinding: Binding<TimeInterval> {
        Binding(
            get: { updateCheckInterval },
            set: { value in
                updateCheckInterval = value
                updaterController.updater.updateCheckInterval = value
            })
    }

    private var libraryDetail: String {
        let count = account.library.count
        return count == 1 ? "1 Format in der Bibliothek" : "\(count) Formate in der Bibliothek"
    }

    /// A file the page exports and imports: what it is, then the two buttons.
    private func transferRow(_ title: String, detail: String, symbol: String,
                             export: (anchor: String, action: () -> Void),
                             import importing: (anchor: String, action: () -> Void)) -> some View {
        HStack(spacing: Space.m) {
            Image(systemName: symbol)
                .font(.system(size: 17))
                .foregroundStyle(themeColor(.accent))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(AppFont.subheading)
                Text(detail).font(AppFont.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: Space.m)
            Button("Exportieren …", systemImage: "square.and.arrow.up", action: export.action)
                .searchAnchor(export.anchor)
            Button("Importieren …", systemImage: "square.and.arrow.down", action: importing.action)
                .searchAnchor(importing.anchor)
        }
        .padding(.vertical, Space.xxs)
    }

    private static func capitalized(_ text: String) -> String {
        guard let first = text.first else { return text }
        return first.uppercased() + text.dropFirst()
    }

    // MARK: Actions

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Auswählen"
        panel.directoryURL = app.downloadFolder
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try app.chooseDownloadFolder(url)
                } catch {
                    app.show(error)
                }
            }
        }
    }

    private func resetFolder() {
        app.resetDownloadFolder()
    }

    // MARK: Import and export

    private func report(_ message: String, failed: Bool = false) {
        transferMessage = message
        transferFailed = failed
    }

    private func report(_ error: any Error) {
        report(error.localizedDescription, failed: true)
        app.show(error)
    }

    /// Lets the user pick a file and hands it on with access to it.
    private func chooseFile(prompt: String, then handle: @escaping (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = prompt
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                handle(url)
            }
        }
    }

    /// Lets the user pick where a file goes; `write` writes it there.
    private func chooseTarget(name: String, then write: @escaping (URL) async throws -> String) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        panel.showsHiddenFiles = true
        panel.prompt = "Exportieren"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    report(try await write(url))
                } catch {
                    report(error)
                }
            }
        }
    }

    private func exportBackup() {
        chooseTarget(name: SettingsTransfer.backupFileName) { url in
            try SettingsTransfer.exportBackup(app.settings, to: url)
            return "Die Sicherung wurde als „\(url.lastPathComponent)“ gespeichert."
        }
    }

    private func importBackup(_ url: URL) {
        do {
            report(try SettingsTransfer.importBackup(from: url, into: app).summary)
            settingsError = nil
            app.show("Die Sicherung wurde importiert.")
        } catch {
            report(error)
        }
    }

    private func exportConfig() {
        chooseTarget(name: "config") { url in
            try SettingsTransfer.exportConfig(app.settings, to: url)
            return "Die config wurde als „\(url.lastPathComponent)“ gespeichert."
        }
    }

    private func importConfig(_ url: URL) {
        do {
            let result = try SettingsTransfer.applyConfig(ConfigFile.load(from: url), to: app)
            report(result.summary)
            settingsError = nil
            app.show("Die Einstellungen wurden importiert.")
        } catch {
            report(error)
        }
    }

    private func exportLibrary() {
        chooseTarget(name: "library.db") { url in
            try await app.services.store.exportDatabase(to: url)
            return "Die Bibliothek wurde als „\(url.lastPathComponent)“ gespeichert."
        }
    }

    private func stageLibrary(_ url: URL) {
        do {
            pendingLibrary = try SettingsTransfer.stageLibrary(from: url)
        } catch {
            report(error)
        }
    }

    /// Puts the library back that the last import replaced; the current one
    /// becomes the backup in turn.
    private func restorePreviousLibrary() {
        do {
            pendingLibrary = try SettingsTransfer.stageLibrary(from: SettingsTransfer.backupURL())
        } catch {
            report(error)
        }
    }

    private func activateLibrary() {
        guard let pendingLibrary else { return }
        self.pendingLibrary = nil
        do {
            try SettingsTransfer.activateLibrary(staging: pendingLibrary)
            report("Die Bibliothek wurde ersetzt. Bitte die App neu starten.")
            app.show("Die Bibliothek wurde ersetzt. Bitte die App neu starten.")
        } catch {
            report(error)
        }
    }

    // MARK: Bindings

    /// The name the account shows; the field writes back into the text of
    /// the page.
    private var nameBinding: Binding<String> {
        Binding(get: { name }, set: { name = $0 })
    }

    /// The name in the chat.
    private var chatnameBinding: Binding<String> {
        Binding(
            get: { chatname },
            set: { chatname = $0 })
    }

    /// The style of the main feed, 1…3.
    private var feedStyleBinding: Binding<Int> {
        Binding(
            get: { profile.preferences?.feedStyle ?? 1 },
            set: { value in Task { await profile.setFeedStyle(value) } })
    }

    /// The state of one channel of the notifications.
    private func channelBinding(_ channel: String) -> Binding<Bool> {
        Binding(
            get: { notifications.channels[channel] ?? false },
            set: { value in Task { await notifications.setChannel(channel, enabled: value) } })
    }

    /// The state of one event of the catalog.
    private func eventBinding(_ key: String) -> Binding<Bool> {
        Binding(
            get: { notifications.isEnabled(key) },
            set: { value in Task { await notifications.setEvent(key, enabled: value) } })
    }

    /// The categories the main feed leaves out.
    private var exclusionFilter: FeedExclusionFilter {
        profile.preferences?.exclusionFilter ?? [:]
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

    /// Whether one category of a format stays out of the main feed.
    private func exclusionBinding(_ pid: Int, _ subpid: Int) -> Binding<Bool> {
        Binding(
            get: { exclusionFilter[pid]?.contains(subpid) ?? false },
            set: { value in
                Task {
                    var filter = exclusionFilter
                    var excluded = filter[pid] ?? []
                    if value {
                        if !excluded.contains(subpid) { excluded.append(subpid) }
                    } else {
                        excluded.removeAll { $0 == subpid }
                    }
                    if excluded.isEmpty {
                        filter.removeValue(forKey: pid)
                    } else {
                        filter[pid] = excluded
                    }
                    await profile.setExclusionFilter(filter)
                }
            })
    }

    private var qualityBinding: Binding<AppSettings.Quality> {
        Binding(
            get: { app.settings.quality },
            set: { value in apply { $0.quality = value } })
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

    private var streamQualityBinding: Binding<AppSettings.Quality> {
        Binding(
            get: { app.settings.streamQuality },
            set: { value in apply { $0.streamQuality = value } })
    }

    private var layoutBinding: Binding<AppSettings.Layout> {
        Binding(
            get: { app.settings.layout },
            set: { value in apply { $0.layout = value } })
    }

    private var parallelBinding: Binding<Int> {
        Binding(
            get: { app.settings.parallel },
            set: { value in apply { $0.parallel = value } })
    }

    private var delayBinding: Binding<Double> {
        Binding(
            get: { app.settings.delay },
            set: { value in apply { $0.delay = value } })
    }

    private var limitBinding: Binding<Int> {
        Binding(
            get: { app.settings.limitKiB },
            set: { value in apply { $0.limitKiB = value } })
    }

    private var thumbBinding: Binding<Bool> {
        Binding(
            get: { app.settings.thumb },
            set: { value in apply { $0.thumb = value } })
    }

    private var metaBinding: Binding<Bool> {
        Binding(
            get: { app.settings.meta },
            set: { value in apply { $0.meta = value } })
    }

    private var themeBinding: Binding<AppSettings.Theme> {
        Binding(
            get: { app.settings.theme },
            set: { value in
                apply { $0.theme = value }
                app.show("Erscheinungsbild: \(value.label)")
            })
    }

    private var tintWithThemeBinding: Binding<Bool> {
        Binding(
            get: { app.settings.tintWithTheme },
            set: { value in apply { $0.tintWithTheme = value } })
    }

    private var glassPanelsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.glassPanels },
            set: { value in apply { $0.glassPanels = value } })
    }

    private var liveNotificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.liveNotificationsOn },
            set: { value in
                apply { $0.liveNotificationsOn = value }
                if value { Task { await watcher.refreshPermission(); await watcher.checkLive() } }
            })
    }

    private var runsInBackgroundBinding: Binding<Bool> {
        Binding(
            get: { app.settings.runsInBackground },
            set: { value in
                apply { $0.runsInBackground = value }
                background.updateDock()
            })
    }

    private var notificationsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.notificationsOn },
            set: { value in
                apply { $0.notificationsOn = value }
                if value { Task { await watcher.refreshPermission() } }
            })
    }

    /// On means the catalog shows the format.
    private func visibleBinding(_ pid: Int) -> Binding<Bool> {
        Binding(
            get: { !app.settings.hiddenMagazines.contains(pid) },
            set: { show in
                apply { settings in
                    var hidden = settings.hiddenMagazines
                    if show {
                        hidden.removeAll { $0 == pid }
                    } else if !hidden.contains(pid) {
                        hidden.append(pid)
                        settings.notifiedMagazines.removeAll { $0 == pid }
                    }
                    settings.hiddenMagazines = hidden
                }
            })
    }

    private func notifyBinding(_ pid: Int) -> Binding<Bool> {
        Binding(
            get: { app.settings.notifiedMagazines.contains(pid) },
            set: { on in
                apply { settings in
                    if on {
                        if !settings.notifiedMagazines.contains(pid) { settings.notifiedMagazines.append(pid) }
                        settings.notificationsOn = true
                    } else {
                        settings.notifiedMagazines.removeAll { $0 == pid }
                    }
                }
                if on { Task { await watcher.refreshPermission() } }
            })
    }

    /// Writes a setting and shows the validation error of the store.
    private func apply(_ change: @escaping (inout AppSettings) -> Void) {
        do {
            try app.updateSettings(change)
            settingsError = nil
        } catch {
            settingsError = error.localizedDescription
            app.show(error)
        }
    }
}
