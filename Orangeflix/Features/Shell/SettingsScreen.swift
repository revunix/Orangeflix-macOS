import AppKit
import SwiftUI
import Sparkle

/// The settings window: an Apple-ID-style account card at the top of the
/// sidebar, three grouped category sections with squircle badges below, and
/// themed card sections on the right.
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

    /// Logical groups in the sidebar below the top Account card.
    enum SidebarGroup: String, CaseIterable, Identifiable {
        case app
        case media
        case system

        var id: String { rawValue }

        var title: String {
            switch self {
            case .app: "App"
            case .media: "Wiedergabe & Katalog"
            case .system: "System"
            }
        }

        var panes: [Pane] {
            switch self {
            case .app: [.general, .appearance, .notifications]
            case .media: [.playback, .downloads, .formats]
            case .system: [.transfer, .about]
            }
        }
    }

    /// The areas of the sidebar (consolidated from 12 scattered tabs into 8 clear areas).
    enum Pane: String, CaseIterable, Identifiable, Hashable {
        case account
        case general
        case appearance
        case notifications
        case playback
        case downloads
        case formats
        case transfer
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .account: "Konto & Profil"
            case .general: "Allgemein"
            case .appearance: "Darstellung"
            case .notifications: "Mitteilungen"
            case .playback: "Wiedergabe & Live"
            case .downloads: "Downloads"
            case .formats: "Formate"
            case .transfer: "Sicherung & Daten"
            case .about: "Über Orangeflix"
            }
        }

        var icon: String {
            switch self {
            case .account: "person.crop.circle.fill"
            case .general: "gearshape.fill"
            case .appearance: "paintpalette.fill"
            case .notifications: "bell.badge.fill"
            case .playback: "play.tv.fill"
            case .downloads: "arrow.down.circle.fill"
            case .formats: "square.stack.3d.up.fill"
            case .transfer: "arrow.up.arrow.down.square.fill"
            case .about: "info.circle.fill"
            }
        }

        var badgeColors: (top: Color, bottom: Color) {
            switch self {
            case .account: (Color(hex: "FA9E14"), Color(hex: "D97E00"))
            case .general: (Color(hex: "7E7970"), Color(hex: "59554E"))
            case .appearance: (Color(hex: "FA9E14"), Color(hex: "D47600"))
            case .notifications: (Color(hex: "F25C50"), Color(hex: "C8372D"))
            case .playback: (Color(hex: "9A6EE2"), Color(hex: "7045BA"))
            case .downloads: (Color(hex: "4B93E8"), Color(hex: "296CC0"))
            case .formats: (Color(hex: "47B872"), Color(hex: "288D4E"))
            case .transfer: (Color(hex: "3BB5B8"), Color(hex: "218689"))
            case .about: (Color(hex: "E39B32"), Color(hex: "B67213"))
            }
        }

        /// Words the search finds besides the title.
        var keywords: String {
            switch self {
            case .account: "konto profil sharing link teilen freigabe name chatname adresse geburtstag credits abo datenschutz agb sitzungen"
            case .general: "updates aktualisierung updater automatisch prüfintervall softwareupdate hintergrund anmeldung starten autostart menüleiste"
            case .appearance: "themes design erscheinungsbild hell dunkel automatisch farben glas liquid dock icon symbol"
            case .notifications: "benachrichtigung push email e-mail ereignis gerät testmitteilung folgen livestream formate melden erlaubnis kanäle"
            case .playback: "streaming discord rich presence status spotify fortschritt link wiedergabe qualität livestream chat umfrage abstimmung voting schrift schriftgröße profilbild avatar uhrzeit"
            case .downloads: "download speicherort zielordner ordner qualität ablage tempo parallel pause tempolimit vorschaubild metadaten feed"
            case .formats: "katalog mediathek ausblenden einblenden sichtbar"
            case .transfer: "import export sicherung backup wiederherstellen config bibliothek library datenbank"
            case .about: "version lizenz mit rechtliches impressum disclaimer unabhängig inoffiziell projekt entwickler"
            }
        }
    }

    @State private var pane: Pane = .general
    @State private var accountTab: AccountSubTab = .overview
    @State private var appearancePreviewDark: Bool? = nil
    @State private var downloadsAdvancedExpanded = false
    @State private var history: [Pane] = [.general]
    @State private var historyIndex = 0
    @State private var search = ""
    @State private var highlight: String?
    @State private var jumps = 0
    @State private var formatListGeneration = 0
    @State private var settingsError: String?
    @State private var transferMessage: String?
    @State private var transferFailed = false
    @State private var pendingLibrary: URL?
    @State private var pendingBackup: AppSettings?
    @State private var pendingDelete: SettingsDelete?
    @State private var previousLibrary: Date?

    /// Default frame of the redesigned Settings window.
    static let windowSize = CGSize(width: 840, height: 700)

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 236, max: 268)
                .toolbar(removing: .sidebarToggle)
        } detail: {
            detail
                .navigationTitle(pane.title)
                .toolbar {
                    if #available(macOS 26, *) {
                        ToolbarItem(placement: .navigation) {
                            historyArrows
                                .glassEffect(.regular.interactive(), in: .capsule)
                                .padding(.leading, Self.arrowsInset)
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

                    if pane == .account {
                        ToolbarItem(placement: .primaryAction) {
                            SettingsSegmentedTabs(
                                options: AccountSubTab.allCases,
                                selection: $accountTab,
                                title: \.title,
                                badgeDot: { $0 == .details && profile.needsLegalConfirmation }
                            )
                        }
                        .flatInSettingsToolbar()
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
        .frame(minWidth: 760, idealWidth: Self.windowSize.width,
               minHeight: 540, idealHeight: Self.windowSize.height)
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

    private static let arrowsInset: CGFloat = 20
    private static let titleGap: CGFloat = 10

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

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: sidebarSelection) {
            let words = SettingsSearch.words(search)
            if words.isEmpty {
                accountSidebarRow
                    .padding(.bottom, 4)

                ForEach(SidebarGroup.allCases) { group in
                    Section {
                        ForEach(group.panes) { item in
                            sidebarRow(item)
                        }
                    } header: {
                        Text(group.title)
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(Palette.textTertiary)
                    }
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

    private var sidebarSelection: Binding<Pane?> {
        Binding(
            get: { pane },
            set: { next in
                guard let next else { return }
                select(next)
            })
    }

    /// Apple-ID-style account card at the very top of the Settings sidebar.
    private var accountSidebarRow: some View {
        let chosen = pane == .account
        let displayName = accountDisplayName
        return HStack(spacing: 10) {
            Group {
                if app.hasCredentials, let image = account.avatarImage {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ZStack {
                        Circle()
                            .fill(Palette.accentSoft)
                        Image(systemName: "person.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Palette.accentText)
                    }
                }
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(chosen ? Palette.accent.opacity(0.6) : Palette.border.opacity(0.6), lineWidth: 1)
            }

            VStack(alignment: .leading, spacing: 1.5) {
                Text(displayName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    Circle()
                        .fill(accountStatusDotColor)
                        .frame(width: 6, height: 6)
                    Text(accountSubtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(chosen ? Palette.accentSoft : Color.primary.opacity(colorScheme == .dark ? 0.04 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .strokeBorder(chosen ? Palette.accent.opacity(0.45) : Color.primary.opacity(0.07), lineWidth: 1)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
        )
        .background(SidebarSelectionChrome())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .tag(Pane.account)
    }

    private var accountDisplayName: String {
        guard app.hasCredentials else { return "Nicht angemeldet" }
        if let chatname = account.details?.chatname, !chatname.trimmingCharacters(in: .whitespaces).isEmpty {
            return chatname
        }
        if let name = account.details?.name, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        return app.username.isEmpty ? "Konto" : app.username
    }

    private var accountSubtitle: String {
        guard app.hasCredentials else { return "Konto & Sharing" }
        switch account.status {
        case .active:
            if account.profile?.lifetime == true { return "Dauerzugang" }
            if let tier = account.profile?.tier, tier > 0 { return "Abo aktiv · Stufe \(tier)" }
            return "Abo aktiv"
        case .expired: return "Abo abgelaufen"
        case .totpRequired: return "2FA erforderlich"
        case .failed: return "Prüfung fehlgeschlagen"
        case .loading: return "Wird geprüft …"
        case .unknown: return "Konto & Profil"
        }
    }

    private var accountStatusDotColor: Color {
        guard app.hasCredentials else { return Palette.textTertiary }
        switch account.status {
        case .active: return Palette.success
        case .expired, .failed, .totpRequired: return Palette.danger
        case .loading, .unknown: return Palette.warning
        }
    }

    /// One category row of the sidebar with a macOS squircle icon badge and soft selection capsule.
    private func sidebarRow(_ item: Pane) -> some View {
        let chosen = item == pane
        let colors = item.badgeColors
        return HStack(spacing: 9) {
            SettingsSquircleBadge(symbol: item.icon, top: colors.top, bottom: colors.bottom)
            Text(item.title)
                .font(.system(size: 13, weight: chosen ? .semibold : .regular))
                .foregroundStyle(chosen ? Palette.textPrimary : Palette.textPrimary.opacity(0.88))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .listRowBackground(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(chosen ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.085) : .clear)
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.14 : 0.08), lineWidth: 0.75)
                    }
                }
                .padding(.horizontal, 8)
        )
        .background(SidebarSelectionChrome())
        .accessibilityAddTraits(chosen ? .isSelected : [])
        .tag(item)
    }

    private func resultRow(_ entry: SettingsSearchEntry) -> some View {
        Button {
            open(entry)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                Text(entry.section)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.leading, 31)
            .padding(.vertical, 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            entry.id == highlight
                ? RoundedRectangle(cornerRadius: 6, style: .continuous).fill(themeColor(.accentSoft)).padding(.horizontal, 8)
                : nil
        )
    }

    private func open(_ entry: SettingsSearchEntry) {
        if entry.id.hasPrefix("formats.visible.") || entry.id.hasPrefix("formats.notify.") {
            formatListGeneration += 1
        }
        if let tab = entry.accountTab {
            accountTab = tab
        }
        if entry.expandsDownloadsAdvanced {
            downloadsAdvancedExpanded = true
        }
        if entry.id.hasPrefix("appearance.theme.") {
            let id = String(entry.id.dropFirst("appearance.theme.".count))
            let allDark = [AppTheme.standard(dark: true)] + AppTheme.builtIn(dark: true) + app.settings.importedThemes.filter(\.isDark)
            appearancePreviewDark = allDark.contains { $0.id == id }
        }
        select(entry.pane)
        highlight = entry.id
        jumps += 1
    }

    // MARK: - Detail

    private var detail: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    if let settingsError {
                        ProfileNotice(
                            symbol: "exclamationmark.triangle.fill",
                            text: settingsError,
                            tint: Palette.danger,
                            background: Palette.dangerSoft
                        )
                    }
                    page
                }
                .padding(.horizontal, Space.page)
                .padding(.top, Space.l)
                .padding(.bottom, Space.xxl)
                .frame(maxWidth: 680, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .id("\(pane.rawValue)-\(pane == .account ? accountTab.rawValue : "")")
            .glassButtonStyle()
            .environment(\.settingsHighlight, highlight)
            .task(id: jumps) {
                guard jumps > 0, let target = highlight else { return }
                try? await Task.sleep(for: .milliseconds(90))
                guard !Task.isCancelled, highlight == target else { return }
                withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(target, anchor: .center) }
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { return }
                highlight = nil
            }
        }
        .background(themeColor(.background))
        .overlay(alignment: .top) { StatusBannerView() }
    }

    private func select(_ next: Pane) {
        guard next != pane else { return }
        highlight = nil
        settingsError = nil
        history = Array(history.prefix(historyIndex + 1))
        history.append(next)
        historyIndex = history.count - 1
        pane = next
    }

    private func step(_ direction: Int) {
        let next = historyIndex + direction
        guard history.indices.contains(next) else { return }
        highlight = nil
        settingsError = nil
        historyIndex = next
        pane = history[next]
    }

    private func searchGroups(_ words: [String]) -> [SettingsSearchGroup] {
        let found = searchEntries.filter { $0.matches(words) }
        return Pane.allCases.compactMap { item in
            let entries = found.filter { $0.pane == item }
            let name = SettingsSearch.fold("\(item.title) \(item.keywords)")
            guard !entries.isEmpty || words.allSatisfy({ name.contains($0) }) else { return nil }
            return SettingsSearchGroup(pane: item, entries: entries)
        }
    }

    private var searchEntries: [SettingsSearchEntry] {
        let settings = app.settings
        let themes = [false, true].flatMap { dark in
            ([AppTheme.standard(dark: dark)] + AppTheme.builtIn(dark: dark)
                + settings.importedThemes.filter { $0.isDark == dark })
                .map { theme in
                    SettingsSearchEntry(
                        id: "appearance.theme.\(theme.id)",
                        pane: .appearance,
                        title: theme.name,
                        section: dark ? "Themes · Dunkler Modus" : "Themes · Heller Modus",
                        keywords: "theme farben"
                    )
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
            switch entry.id {
            case "general.allowNotifications": !watcher.isAllowed
            case "transfer.libraryRestore": previousLibrary != nil
            default: true
            }
        }
        return app.hasCredentials ? all : all.filter {
            ($0.pane != .account || $0.id == "sharing.check") && !$0.id.hasPrefix("notifications.")
        }
    }

    // MARK: - Pages

    @ViewBuilder private var page: some View {
        switch pane {
        case .account:
            SettingsAccountPage(subTab: $accountTab, pendingDelete: $pendingDelete)
        case .general:
            SettingsGeneralPage(
                updaterController: updaterController,
                automaticUpdateChecks: $automaticUpdateChecks,
                updateCheckInterval: $updateCheckInterval,
                settingsError: $settingsError
            )
        case .appearance:
            SettingsAppearancePage(
                settingsError: $settingsError,
                pendingDelete: $pendingDelete,
                previewDarkOverride: $appearancePreviewDark
            )
        case .notifications:
            SettingsNotificationsPage(
                settingsError: $settingsError,
                pendingDelete: $pendingDelete,
                showFormats: { select(.formats) }
            )
        case .playback:
            SettingsPlaybackPage(settingsError: $settingsError)
        case .downloads:
            SettingsDownloadsPage(
                settingsError: $settingsError,
                advancedExpanded: $downloadsAdvancedExpanded
            )
        case .formats:
            SettingsFormatsPage(settingsError: $settingsError, formatListGeneration: formatListGeneration)
        case .transfer:
            SettingsTransferPage(
                transferMessage: $transferMessage,
                transferFailed: $transferFailed,
                settingsError: $settingsError,
                pendingLibrary: $pendingLibrary,
                pendingBackup: $pendingBackup,
                previousLibrary: $previousLibrary
            )
        case .about:
            SettingsAboutPage()
        }
    }

    private func themeColor(_ token: ThemeToken) -> Color {
        Color(hex: ThemeRuntime.shared.hex(token, dark: colorScheme == .dark))
    }

    // MARK: - Import, export & delete confirmations

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

private extension ToolbarContent {
    @ToolbarContentBuilder
    func flatInSettingsToolbar() -> some ToolbarContent {
        if #available(macOS 26, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}
