import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Appearance settings: 2-column scheme + glass style row, unified 3-column
/// theme grid with Hell/Dunkel switcher + inline Ghostty/iTerm import tile,
/// and Dock app icon selector.
struct SettingsAppearancePage: View {
    @Binding var settingsError: String?
    @Binding var pendingDelete: SettingsDelete?
    @Binding var previewDarkOverride: Bool?

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    private enum ThemeModeTab: String, CaseIterable, Identifiable {
        case light
        case dark
        var id: String { rawValue }
        var isDark: Bool { self == .dark }
        var title: String { self == .dark ? "Dunkel" : "Hell" }
        var symbol: String { self == .dark ? "moon.stars.fill" : "sun.max.fill" }
    }

    @State private var modeTab: ThemeModeTab = .dark
    @State private var modeInitialized = false
    @State private var dropTargeted = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            HStack(alignment: .top, spacing: Space.l) {
                colorSchemeSection
                interfaceStyleSection
            }

            themesSection
            appIconSection
        }
        .onAppear {
            if let override = previewDarkOverride {
                modeTab = override ? .dark : .light
                previewDarkOverride = nil
                modeInitialized = true
            } else if !modeInitialized {
                modeTab = colorScheme == .dark ? .dark : .light
                modeInitialized = true
            }
        }
        .onChange(of: previewDarkOverride) { _, next in
            guard let next else { return }
            withAnimation(.snappy(duration: 0.18)) {
                modeTab = next ? .dark : .light
            }
            previewDarkOverride = nil
        }
        .onChange(of: colorScheme) { _, scheme in
            if app.settings.theme != .auto {
                withAnimation(.snappy(duration: 0.18)) {
                    modeTab = scheme == .dark ? .dark : .light
                }
            }
        }
    }

    // MARK: - Top 2-column row

    private var colorSchemeSection: some View {
        SettingsSection(
            "Erscheinungsbild",
            footer: "„Automatisch“ wechselt mit macOS zwischen Hell und Dunkel."
        ) {
            EmptyView()
        } content: {
            HStack(spacing: Space.s) {
                ForEach([AppSettings.Theme.auto, .light, .dark], id: \.self) { theme in
                    SettingsChoiceCard(
                        title: SettingsFieldFormat.capitalized(theme.label),
                        isSelected: app.settings.theme == theme,
                        action: {
                            themeBinding.wrappedValue = theme
                            if theme == .light { modeTab = .light }
                            if theme == .dark { modeTab = .dark }
                        }
                    ) {
                        ModePreview(theme: theme)
                    }
                }
            }
            .searchAnchor("appearance.mode")
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    private var interfaceStyleSection: some View {
        SettingsSection(
            "Oberflächenstil",
            footer: "Liquid Glass zeichnet Leisten durchscheinend, Klassisch ruhig flächig."
        ) {
            EmptyView()
        } content: {
            HStack(spacing: Space.s) {
                ForEach(AppSettings.InterfaceStyle.allCases, id: \.self) { style in
                    SettingsChoiceCard(
                        title: style.shellTitle,
                        isSelected: app.settings.interfaceStyle == style,
                        action: { apply { $0.interfaceStyle = style } }
                    ) {
                        InterfaceStylePreview(style: style)
                    }
                }
            }
            .searchAnchor("appearance.style")

            Hairline()

            SettingsToggleRow(
                title: "Glas für Flächen",
                subtitle: "Auch Suchfelder und Filter-Pills in Glas",
                isOn: glassPanelsBinding
            )
            .disabled(app.settings.interfaceStyle == .classic)
            .opacity(app.settings.interfaceStyle == .classic ? 0.45 : 1)
            .searchAnchor("appearance.glass")
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Unified 3-column Theme Grid

    private var themesSection: some View {
        let dark = modeTab.isDark
        let settings = app.settings
        let standard = AppTheme.standard(dark: dark)
        let builtIn = AppTheme.builtIn(dark: dark)
        let imported = settings.importedThemes.filter { $0.isDark == dark }
        let selected = AppTheme.resolve(
            id: dark ? settings.darkThemeID : settings.lightThemeID,
            dark: dark,
            imported: settings.importedThemes
        ).id

        return SettingsSection(
            "Farbwelt & Themes",
            subtitle: (colorScheme == .dark) == dark ? "Aktives Erscheinungsbild" : "Vorschau für den \(dark ? "dunklen" : "hellen") Modus",
            footer: themeFooter(dark: dark)
        ) {
            SettingsSegmentedTabs(
                options: ThemeModeTab.allCases,
                selection: $modeTab,
                title: \.title,
                symbol: { $0.symbol },
                badgeDot: { ($0.isDark) == (colorScheme == .dark) }
            )
        } content: {
            LazyVGrid(columns: columns, spacing: 10) {
                ThemeCard(
                    theme: standard,
                    isSelected: selected == standard.id,
                    badge: "Standard"
                ) {
                    chooseTheme(standard.id, dark: dark)
                }
                .searchAnchor("appearance.theme.\(standard.id)")

                ForEach(builtIn) { theme in
                    ThemeCard(
                        theme: theme,
                        isSelected: selected == theme.id
                    ) {
                        chooseTheme(theme.id, dark: dark)
                    }
                    .searchAnchor("appearance.theme.\(theme.id)")
                }

                ForEach(imported) { theme in
                    ThemeCard(
                        theme: theme,
                        isSelected: selected == theme.id,
                        badge: "Import",
                        onRemove: { pendingDelete = .theme(theme.id) }
                    ) {
                        chooseTheme(theme.id, dark: dark)
                    }
                    .searchAnchor("appearance.theme.\(theme.id)")
                }

                importThemeTile
                    .searchAnchor("appearance.import")
            }

            Hairline()

            SettingsToggleRow(
                title: "Mit Theme einfärben",
                subtitle: "Übernimmt die Akzentfarbe des gewählten Themes statt Standard-Orange",
                isOn: tintWithThemeBinding
            )
            .searchAnchor("appearance.tint")

            Hairline()

            SettingsToggleRow(
                title: "Erweiterte Theme-Palette im \(dark ? "dunklen" : "hellen") Modus",
                subtitle: "Färbt zusätzlich Hintergrund, Karten und Textfarben des Modus ein",
                isOn: extendedBinding(dark: dark)
            )
            .searchAnchor("appearance.extended")
        }
    }

    private var importThemeTile: some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return Button(action: chooseThemeFile) {
            VStack(spacing: 6) {
                Image(systemName: dropTargeted ? "arrow.down.doc.fill" : "plus.circle.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(Palette.accent)
                Text("Theme importieren …")
                    .font(AppFont.captionMedium)
                    .foregroundStyle(Palette.textPrimary)
                    .lineLimit(1)
                Text("Ghostty oder iTerm")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.textTertiary)
                    .lineLimit(1)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 82)
            .background(
                shape.fill(dropTargeted ? Palette.accentSoft : Palette.surfaceMuted.opacity(0.55))
            )
            .overlay {
                shape.strokeBorder(
                    dropTargeted ? Palette.accent : Palette.border,
                    style: StrokeStyle(lineWidth: 1, dash: [5, 4])
                )
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onDrop(of: [.fileURL], isTargeted: $dropTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                guard let url else { return }
                Task { @MainActor in importTheme(url) }
            }
            return true
        }
        .help("Ghostty- oder .itermcolors-Datei auswählen oder hierher ziehen")
    }

    private func themeFooter(dark: Bool) -> String {
        let extended = dark ? app.settings.darkExtendedPalette : app.settings.lightExtendedPalette
        if extended {
            return "Ghostty- und iTerm-Themes kannst du auch direkt per Drag & Drop auf die Import-Kachel ziehen."
        }
        if app.settings.tintWithTheme {
            return "Erweiterte Palette ist aus: Nur die Akzentfarbe stammt vom Theme, Flächen und Texte bleiben beim ruhigen Standard."
        }
        return "Erweiterte Palette und Einfärben sind aus: Flächen bleiben beim Standard und der Akzent beim Orangeflix-Orange."
    }

    // MARK: - App Icon

    private var appIconSection: some View {
        SettingsSection(
            "App-Symbol im Dock",
            footer: "Das Symbol im Dock wechselt sofort; im Finder behält das App-Paket sein Standardsymbol."
        ) {
            EmptyView()
        } content: {
            HStack(spacing: Space.m) {
                ForEach(AppSettings.AppIcon.allCases, id: \.self) { icon in
                    SettingsChoiceCard(
                        title: icon.shellTitle,
                        isSelected: app.settings.appIcon == icon,
                        action: { apply { $0.appIcon = icon } }
                    ) {
                        AppIconArt(style: icon, dark: colorScheme == .dark)
                            .frame(width: 48, height: 48)
                    }
                }
            }
            .searchAnchor("appearance.appIcon")
        }
    }

    // MARK: - Bindings & actions

    private func extendedBinding(dark: Bool) -> Binding<Bool> {
        Binding(
            get: { dark ? app.settings.darkExtendedPalette : app.settings.lightExtendedPalette },
            set: { value in
                apply { if dark { $0.darkExtendedPalette = value } else { $0.lightExtendedPalette = value } }
            }
        )
    }

    private func chooseTheme(_ id: String, dark: Bool) {
        apply { if dark { $0.darkThemeID = id } else { $0.lightThemeID = id } }
    }

    private var themeBinding: Binding<AppSettings.Theme> {
        Binding(
            get: { app.settings.theme },
            set: { value in
                apply { $0.theme = value }
                app.show("Erscheinungsbild: \(value.label)")
            }
        )
    }

    private var tintWithThemeBinding: Binding<Bool> {
        Binding(
            get: { app.settings.tintWithTheme },
            set: { value in apply { $0.tintWithTheme = value } }
        )
    }

    private var glassPanelsBinding: Binding<Bool> {
        Binding(
            get: { app.settings.glassPanels },
            set: { value in apply { $0.glassPanels = value } }
        )
    }

    private func chooseThemeFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Importieren"
        SettingsPanels.present(panel) { url in importTheme(url) }
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
            modeTab = theme.isDark ? .dark : .light
            app.show("Theme „\(theme.name)“ für den \(theme.isDark ? "dunklen" : "hellen") Modus importiert")
        } catch {
            settingsError = error.localizedDescription
            app.show(error)
        }
    }

    private func apply(_ change: (inout AppSettings) -> Void) {
        SettingsWrite.apply(app, $settingsError, change)
    }
}
