import AppKit
import SwiftUI

/// The look of the app: the color scheme, the interface style, the theme of
/// each mode, the import of terminal themes and the symbol in the Dock.
struct SettingsAppearancePage: View {
    @Binding var settingsError: String?
    @Binding var pendingDelete: SettingsDelete?

    @Environment(AppModel.self) private var app
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            Section {
                HStack(alignment: .top, spacing: Space.m) {
                    ForEach([AppSettings.Theme.auto, .light, .dark], id: \.self) { theme in
                        SettingsChoiceCard(
                            title: SettingsFieldFormat.capitalized(theme.label),
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

    private func themeSection(_ title: String, dark: Bool) -> some View {
        let settings = app.settings
        let selected = AppTheme.resolve(
            id: dark ? settings.darkThemeID : settings.lightThemeID, dark: dark,
            imported: settings.importedThemes).id
        let builtIn = AppTheme.builtIn(dark: dark)
        let imported = settings.importedThemes.filter { $0.isDark == dark }
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
                themeStrip("Integriert", themes: builtIn, selected: selected, dark: dark, removable: false)
                if !imported.isEmpty {
                    Divider().frame(height: 100)
                    themeStrip("Importiert", themes: imported, selected: selected, dark: dark, removable: true)
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

    /// One row of theme cards. Imported themes show a button that removes
    /// them; built-in themes stay.
    private func themeStrip(_ title: String, themes: [AppTheme], selected: String, dark: Bool, removable: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: Space.m) {
                    ForEach(themes) { theme in
                        VStack(spacing: Space.xxs) {
                            ThemeCard(theme: theme, isSelected: selected == theme.id) {
                                chooseTheme(theme.id, dark: dark)
                            }
                            if removable {
                                Button("Entfernen", role: .destructive) { pendingDelete = .theme(theme.id) }
                                    .buttonStyle(.borderless)
                                    .controlSize(.small)
                                    .font(.caption)
                            }
                        }
                        .searchAnchor("appearance.theme.\(theme.id)")
                    }
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
