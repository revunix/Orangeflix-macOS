import AppKit
import Foundation
import Observation

/// The account state of the shell: the subscription (Go `ProfileSummary`
/// via `loadProfile`), the library numbers of the Konto box, whether the
/// window must ask for the login and the sign-out.
@MainActor @Observable final class AccountModel {
    /// The state of the "Zugang" line (Go `profileLine`).
    enum Status: Equatable {
        case unknown
        case loading
        case totpRequired
        case failed(String)
        case expired
        case active(String)

        /// The German text of the Konto line.
        var text: String {
            switch self {
            case .unknown: "unbekannt"
            case .loading: "wird geprüft …"
            case .totpRequired: "2FA-Code nötig"
            case .failed: "Anmeldung fehlgeschlagen"
            case .expired: "● abgelaufen"
            case .active(let summary): "● " + summary
            }
        }
    }

    @ObservationIgnored private let app: AppModel
    /// Loads the picture of the account by its chat name, as the chat does.
    @ObservationIgnored private let avatarLoader = LiveAvatarLoader()

    /// The subscription of the last successful load.
    private(set) var profile: ProfileSummary?
    /// The whole answer of `user/me` of the last successful load.
    private(set) var details: AccountProfile?
    /// The started episodes of the account (`playback/progress`); nil while
    /// unknown.
    private(set) var progress: [WatchProgressEntry]?
    /// The picture of the account; nil when it has none or it did not load.
    private(set) var avatar: Data?
    /// The same picture, decoded once, so the Konto page does not decode it
    /// on every redraw.
    private(set) var avatarImage: NSImage?
    /// Whether the profile is being loaded.
    private(set) var isLoading = false
    /// The error of the last load.
    private(set) var loadError: (any Error)?
    /// Set when the last load needs the 2FA code (`totpRequired` /
    /// `totpRejected`); the window shows the login with the code field.
    private(set) var authProblem: AuthError?
    /// True while the sign-out runs.
    private(set) var isSigningOut = false
    /// The formats of the library (Konto box: Neue Folgen, Bibliothek).
    private(set) var library: [LibraryFormat] = []
    /// The warning of a subscription that ran out or runs out within 14
    /// days; nil when there is none (Go `ExpiryWarning`).
    private(set) var expiryWarning: String?

    @ObservationIgnored private var loadedGeneration: Int?
    @ObservationIgnored private var lastLibraryRefresh: Date?
    /// The warning that was shown last, to keep it out of the log twice.
    @ObservationIgnored private var lastWarning = ""

    init(app: AppModel) {
        self.app = app
    }

    /// The "Zugang" line.
    var status: Status {
        if let profile {
            return profile.hasAccess ? .active(profile.summarize()) : .expired
        }
        if isLoading { return .loading }
        if authProblem == .totpRequired { return .totpRequired }
        if let loadError { return .failed(loadError.localizedDescription) }
        return .unknown
    }

    /// The sum of the new episodes of the library.
    var newEpisodeCount: Int { library.reduce(0) { $0 + $1.newCount } }

    /// Whether the main window shows the login instead of the app: nothing
    /// is stored, or the stored account wants its 2FA code.
    var needsLogin: Bool {
        !app.hasCredentials || authProblem == .totpRequired || authProblem == .totpRejected
    }

    /// Loads the subscription (Go `loadProfile`: `EnsureV3` + `Profile`).
    /// A new account generation clears the old profile first. 2FA problems
    /// set `authProblem`, which brings up the login; an expired or soon
    /// expiring subscription shows the warning as banner.

    func load() async {
        if loadedGeneration != app.accountGeneration {
            loadedGeneration = app.accountGeneration
            profile = nil
            details = nil
            progress = nil
            rememberAvatar(nil)
        }
        // Without credentials there is nothing to check: the login screen
        // shows and the API would only answer with an error.
        guard app.hasCredentials else {
            isLoading = false
            loadError = nil
            authProblem = nil
            expiryWarning = nil
            return
        }
        isLoading = true
        loadError = nil
        authProblem = nil
        expiryWarning = nil
        defer { isLoading = false }
        do {
            try await app.ensureSession()
            let answer = try await app.services.api.profile()
            let summary = ProfileSummary(profile: answer)
            profile = summary
            details = answer
            let warning = summary.expiryWarning()
            if !warning.isEmpty {
                expiryWarning = warning
                // The profile is loaded more than once (start, account
                // change, sidebar); the warning belongs into the log once.
                if warning != lastWarning {
                    lastWarning = warning
                    app.record(warning)
                    app.show(warning)
                }
            } else {
                lastWarning = ""
            }
            await loadExtras(answer)
        } catch is CancellationError {
            return
        } catch let error as AuthError where error == .totpRequired || error == .totpRejected {
            loadError = error
            authProblem = error
            app.show(error.localizedDescription, error: true)
        } catch let error as AuthError where error == .sessionLimit {
            // The account has too many sessions; the Konto page shows the
            // list of them, so one can be ended.
            loadError = error
            authProblem = error
            app.show(error.localizedDescription, error: true)
        } catch {
            loadError = error
        }
    }

    /// The started episodes and the picture of the account. Both only add
    /// to the Konto page, so a failure is logged and nothing else.
    private func loadExtras(_ answer: AccountProfile) async {
        do {
            progress = try await app.services.api.playbackProgress()
        } catch is CancellationError {
            return
        } catch {
            app.record("Der Wiedergabefortschritt des Kontos konnte nicht geladen werden: \(error.localizedDescription)",
                       error: true)
        }
        if let url = AccountFacts(profile: answer).avatarURL {
            var request = URLRequest(url: url)
            request.setValue(APIDefaults.userAgent, forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = LiveAvatarLoader.timeout
            if let (data, response) = try? await URLSession.shared.data(for: request),
               (response as? HTTPURLResponse)?.statusCode == 200,
               data.count <= 2 << 20 {
                rememberAvatar(data)
                return
            }
        }
        rememberAvatar(await avatarLoader.data(for: answer.chatname))
    }

    /// Keeps the bytes and the decoded picture together.
    private func rememberAvatar(_ data: Data?) {
        avatar = data
        avatarImage = data.flatMap { NSImage(data: $0) }
    }

    /// Re-reads the library formats from the store. `minimumInterval` skips
    /// the query when the last one was a moment ago; the Protokoll line
    /// that asks for it may come in bursts.
    func refreshLibrary(minimumInterval: TimeInterval = 0) async {
        if minimumInterval > 0, let last = lastLibraryRefresh,
           Date().timeIntervalSince(last) < minimumInterval {
            return
        }
        do {
            library = try await app.services.store.formats()
            lastLibraryRefresh = Date()
        } catch {
            app.record("Die Bibliothek konnte nicht gelesen werden: \(error.localizedDescription)", error: true)
        }
    }

    /// Asks before the sign-out; it removes the login from this Mac.
    func confirmSignOut() {
        let alert = NSAlert()
        alert.messageText = "Abmelden?"
        alert.informativeText = "Die Sitzung wird beendet, E-Mail und Passwort werden von diesem Mac entfernt. Heruntergeladene Folgen bleiben erhalten."
        alert.addButton(withTitle: "Abmelden").hasDestructiveAction = true
        alert.addButton(withTitle: "Abbrechen")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await signOut() }
    }

    /// Ends the session and drops everything that belongs to the account.
    func signOut() async {
        guard !isSigningOut else { return }
        isSigningOut = true
        defer { isSigningOut = false }
        await app.signOut()
        profile = nil
        details = nil
        progress = nil
        rememberAvatar(nil)
        loadError = nil
        authProblem = nil
        expiryWarning = nil
        lastWarning = ""
        app.show("Abgemeldet")
    }

    /// Called by the login screen after a successful sign-in.
    func signedIn() {
        authProblem = nil
    }

    /// The version of the app: "1.0 (3)".
    static var appVersion: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        if let build = info["CFBundleVersion"] as? String, !build.isEmpty, build != short {
            return "\(short) (\(build))"
        }
        return short
    }
}
