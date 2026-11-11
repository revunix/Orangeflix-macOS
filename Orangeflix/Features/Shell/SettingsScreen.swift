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
        _previousLibrary = State(initialValue: SettingsTransfer.previousLibraryDate())
    }

    /// The areas of the sidebar.
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case general, notifications, account, profile, sharing, appearance, downloads, streaming, live, formats, transfer, about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: "Allgemein"
            case .notifications: "Mitteilungen"
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
            case .notifications: "bell"
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
            case .general: "updates aktualisierung updater automatisch prüfintervall softwareupdate speicherort ordner download hintergrund anmeldung starten autostart"
            case .notifications: "benachrichtigung push email e-mail ereignis gerät testmitteilung folgen livestream formate melden erlaubnis kanäle"
            case .appearance: "themes design erscheinungsbild hell dunkel automatisch farben"
            case .streaming: "discord rich presence status spotify fortschritt link application id client id wiedergabe qualität"
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
    /// The control the search jumped to; it lights up for a moment.
    @State private var highlight: String?
    /// Counts the jumps of the search, so a second jump to the same control
    /// scrolls again.
    @State private var jumps = 0
    /// Bumps when the search opens a format, so that page clears its own
    /// search. The query lives on the page; a keystroke there does not
    /// rebuild this sidebar.
    @State private var formatListGeneration = 0
    /// The message of the last failed change.
    @State private var settingsError: String?
    /// The result of the last import or export.
    @State private var transferMessage: String?
    /// Whether the last import or export failed.
    @State private var transferFailed = false
    /// The library that waits for the confirmation of the user.
    @State private var pendingLibrary: URL?
    /// The settings of a backup that wait for the confirmation of the user.
    @State private var pendingBackup: AppSettings?
    /// A delete that waits until the user confirms it.
    @State private var pendingDelete: SettingsDelete?
    /// When the previous library was kept; nil when there is none. Read
    /// once, then again after an import, so the search does not touch the
    /// disk on every redraw.
    @State private var previousLibrary: Date?

    /// The size the window opens with; the scene in `MyApp` names the same,
    /// so the first frame is already this size.
    static let windowSize = CGSize(width: 740, height: 770)

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
        .confirmationDialog(
            "Alle Einstellungen werden durch die der Sicherung ersetzt.",
            isPresented: Binding(get: { pendingBackup != nil }, set: { if !$0 { pendingBackup = nil } }),
            titleVisibility: .visible
        ) {
            Button("Einstellungen ersetzen", role: .destructive) { applyBackup() }
            Button("Abbrechen", role: .cancel) { pendingBackup = nil }
        } message: {
            Text("Dazu gehören die Themes und die Auswahl der Formate. Anmeldung und Speicherort bleiben. Die jetzigen Einstellungen lassen sich nur mit einer eigenen Sicherung zurückholen.")
        }
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button(deleteConfirmTitle, role: .destructive) { performDelete() }
            Button("Abbrechen", role: .cancel) { pendingDelete = nil }
        } message: {
            Text(deleteMessage)
        }
        .task { await watcher.refreshPermission(ask: false) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await watcher.refreshPermission(ask: false) }
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

    /// The areas on the left. While searching it shows the matching areas
    /// with the controls found in them. The list selection is what the arrow
    /// keys change. macOS would paint that selection in the system accent, so
    /// the table draws none and the row paints the theme accent itself.
    private var sidebar: some View {
        List(selection: sidebarSelection) {
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

    /// The row the arrow keys move. Setting it goes through `select`, so the
    /// history of visited areas stays in step with the keyboard.
    private var sidebarSelection: Binding<Pane?> {
        Binding(
            get: { pane },
            set: { next in
                guard let next else { return }
                select(next)
            })
    }

    /// One area of the sidebar; the chosen one stands on the accent.
    private func sidebarRow(_ item: Pane) -> some View {
        let chosen = item == pane
        return Label {
            Text(item.title)
                .foregroundStyle(chosen ? onAccent : Color.primary)
        } icon: {
            Image(systemName: item.icon)
                .foregroundStyle(chosen ? onAccent : themeColor(.accent))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chosen ? themeColor(.accent) : .clear)
                .padding(.horizontal, 10))
        .background(SidebarSelectionChrome())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .tag(item)
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
            formatListGeneration += 1
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
                // A new page starts at the top. The reader stays outside
                // this identity, so a search jump can still scroll once the
                // page is on screen.
                .id(pane)
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
        // What a button of the page did or could not do.
        .overlay(alignment: .top) { StatusBannerView() }
    }

    /// Shows `next` and remembers the way there.
    private func select(_ next: Pane) {
        guard next != pane else { return }
        highlight = nil
        // The error belongs to the page it happened on.
        settingsError = nil
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
        settingsError = nil
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
        let all = (SettingsSearch.entries + themes + formats).filter { entry in
            // Rows that only show in a certain state.
            switch entry.id {
            case "general.allowNotifications": !watcher.isAllowed
            case "transfer.libraryRestore": previousLibrary != nil
            default: true
            }
        }
        // Signed out, the pages of the account have no rows to jump to, and
        // the notifications of the account are not there either.
        let accountPages: Set<Pane> = [.account, .profile, .sharing]
        return app.hasCredentials ? all : all.filter {
            !accountPages.contains($0.pane) && !$0.id.hasPrefix("notifications.")
        }
    }

    // MARK: Seiten

    @ViewBuilder private var page: some View {
        switch pane {
        case .general:
            SettingsGeneralPage(
                updaterController: updaterController,
                automaticUpdateChecks: $automaticUpdateChecks,
                updateCheckInterval: $updateCheckInterval,
                settingsError: $settingsError)
        case .notifications:
            SettingsNotificationsPage(
                settingsError: $settingsError,
                pendingDelete: $pendingDelete,
                showFormats: { select(.formats) })
        case .account:
            SettingsAccountPage()
        case .profile:
            SettingsProfilePage(pendingDelete: $pendingDelete)
        case .sharing:
            SettingsSharingPage(pendingDelete: $pendingDelete)
        case .appearance:
            SettingsAppearancePage(settingsError: $settingsError, pendingDelete: $pendingDelete)
        case .downloads:
            SettingsDownloadsPage(settingsError: $settingsError)
        case .streaming:
            SettingsStreamingPage(settingsError: $settingsError)
        case .live:
            SettingsLivePage(settingsError: $settingsError)
        case .formats:
            SettingsFormatsPage(settingsError: $settingsError, formatListGeneration: formatListGeneration)
        case .transfer:
            SettingsTransferPage(
                transferMessage: $transferMessage,
                transferFailed: $transferFailed,
                settingsError: $settingsError,
                pendingLibrary: $pendingLibrary,
                pendingBackup: $pendingBackup,
                previousLibrary: $previousLibrary)
        case .about:
            SettingsAboutPage()
        }
    }

    /// A color of the active theme, as a new value whenever the theme
    /// changes, so the window repaints.
    private func themeColor(_ token: ThemeToken) -> Color {
        Color(hex: ThemeRuntime.shared.hex(token, dark: colorScheme == .dark))
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

    private func applyBackup() {
        guard let pendingBackup else { return }
        self.pendingBackup = nil
        do {
            report(try SettingsTransfer.applyBackup(pendingBackup, to: app).summary)
            settingsError = nil
            app.show("Die Sicherung wurde importiert.")
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
        previousLibrary = SettingsTransfer.previousLibraryDate()
    }

    /// The question of the delete confirmation.
    private var deleteTitle: String {
        switch pendingDelete {
        case .address: "Die Lieferadresse wird gelöscht."
        case .birthday: "Das Geburtsdatum wird gelöscht."
        case .credits: "Der Eintrag in den Credits wird gelöscht."
        case .feedFilter: "Der Feed-Filter wird geleert."
        case .sharingLink: "Der Sharing-Link wird beendet."
        case .pushDevice: "Das Gerät wird abgemeldet."
        case .theme: "Das importierte Theme wird entfernt."
        case nil: ""
        }
    }

    /// The confirming button of that question.
    private var deleteConfirmTitle: String {
        switch pendingDelete {
        case .address, .birthday, .credits: "Löschen"
        case .feedFilter: "Filter leeren"
        case .sharingLink: "Beenden"
        case .pushDevice: "Abmelden"
        case .theme: "Entfernen"
        case nil: "Löschen"
        }
    }

    /// The line under the question.
    private var deleteMessage: String {
        switch pendingDelete {
        case .address: "Der Server entfernt die hinterlegte Adresse."
        case .birthday: "Der Server entfernt das hinterlegte Datum."
        case .credits: "Der Server entfernt die Nennung."
        case .feedFilter: "Die ausgeschalteten Kategorien erscheinen wieder im Feed."
        case .sharingLink: "Der Link lässt sich danach nicht mehr aufrufen."
        case .pushDevice: "Der Server schickt an dieses Gerät keine Push-Mitteilungen mehr."
        case .theme: "Ist es gerade ausgewählt, gilt wieder das Standard-Theme."
        case nil: ""
        }
    }

    /// Carries out the delete the user just confirmed.
    private func performDelete() {
        guard let action = pendingDelete else { return }
        pendingDelete = nil
        switch action {
        case .address:
            Task { await profile.deleteAddress() }
        case .birthday:
            Task { await profile.deleteBirthday() }
        case .credits:
            Task { await profile.deleteCredits() }
        case .feedFilter:
            Task { await profile.clearExclusionFilter() }
        case .sharingLink(let code):
            Task { await sharing.revoke(code) }
        case .pushDevice(let id):
            Task { await notifications.removeDevice(id) }
        case .theme(let id):
            guard let theme = app.settings.importedThemes.first(where: { $0.id == id }) else { return }
            SettingsWrite.apply(app, $settingsError) { settings in
                settings.importedThemes.removeAll { $0.id == theme.id }
                if settings.lightThemeID == theme.id { settings.lightThemeID = AppTheme.orangeflixLight.id }
                if settings.darkThemeID == theme.id { settings.darkThemeID = AppTheme.orangeflixDark.id }
            }
        }
    }
}
