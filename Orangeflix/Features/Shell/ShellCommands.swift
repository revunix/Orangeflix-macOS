import AppKit
import SwiftUI
import Sparkle

/// The menu bar of the app (Go palette "Gehe zu" and "Allgemein"): the
/// sections of the sidebar with ⌘1…⌘8, the search, the sign-out, the
/// Protokoll and the download folder.
struct ShellCommands: Commands {
    @Environment(\.openSettings) private var openSettings
    /// The state of the app.
    let app: AppModel
    /// The account; the "Abmelden" command uses it.
    let account: AccountModel
    let updaterController: SPUStandardUpdaterController

    /// Whether the Protokoll is shown; the window reads the same key.
    @AppStorage("showLogPanel") private var showLogPanel = false

    init(app: AppModel, account: AccountModel, updaterController: SPUStandardUpdaterController) {
        self.app = app
        self.account = account
        self.updaterController = updaterController
    }

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("Über Orangeflix") { openAbout() }
            Button("Nach Updates suchen …") { updaterController.checkForUpdates(nil) }
        }
        CommandMenu("Gehe zu") {
            Button("Schnellwechsel …") {
                NotificationCenter.default.post(name: .toggleCommandPalette, object: nil)
            }
            .keyboardShortcut("k", modifiers: .command)
            Divider()
            ForEach(Array(SidebarItem.allCases.enumerated()), id: \.element) { index, item in
                Button(item.title) { app.selection = item }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
            }
        }
        CommandMenu("Allgemein") {
            Button("Volltextsuche in allen Folgen") { app.selection = .search }
                .keyboardShortcut("f", modifiers: .command)
            Button("Abmelden …") { account.confirmSignOut() }
                .disabled(!app.hasCredentials || account.isSigningOut)
            Button(showLogPanel ? "Protokoll ausblenden" : "Protokoll einblenden") {
                showLogPanel.toggle()
            }
            .keyboardShortcut("l", modifiers: .command)
            Button("Speicherort ändern …") { chooseFolder() }
            Divider()
            Button("Nach Updates suchen …") { updaterController.checkForUpdates(nil) }
        }
    }

    /// Opens the settings on the page that says what the app is.
    private func openAbout() {
        openSettings()
        // The Settings scene may not have installed its notification observer
        // until after `openSettings()` creates the window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NotificationCenter.default.post(name: .openAboutPane, object: nil)
        }
    }

    /// Lets the user pick the download folder (Go `applyPath`).
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
}
