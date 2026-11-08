import SwiftUI

/// The login of the app. It fills the main window while nobody is signed in
/// or the stored account wants its 2FA code; the app shows nothing else
/// until the login succeeded. The code field only appears when the account
/// asks for it.
struct LoginScreen: View {
    @Environment(AppModel.self) private var app
    @Environment(AccountModel.self) private var account
    @Environment(SessionModel.self) private var sessions

    private enum Field: Hashable { case email, password, code }

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var isSigningIn = false
    @State private var errorText: String?
    /// Set when the server asked for the second factor during this login.
    @State private var askedForCode = false
    @State private var didPrefill = false
    @FocusState private var focus: Field?

    var body: some View {
        VStack(spacing: Space.xl) {
            VStack(spacing: Space.m) {
                BrandWordmark(closed: 0, size: 40)
                VStack(spacing: Space.xs) {
                    Text("Anmelden")
                        .font(AppFont.display)
                        .foregroundStyle(Palette.textPrimary)
                    Text(needsCode
                         ? "Gib den Code aus deiner Authenticator-App ein."
                         : "Melde dich mit deinem Orangeflix-Konto an.")
                        .font(AppFont.body)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            VStack(spacing: Space.s) {
                TextField("E-Mail", text: $email, prompt: Text("E-Mail"))
                    .textContentType(.username)
                    .focused($focus, equals: .email)
                    .disabled(isSigningIn)
                SecureField("Passwort", text: $password, prompt: Text("Passwort"))
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .disabled(isSigningIn)
                if needsCode {
                    TextField("Code", text: $code, prompt: Text("6-stelliger Code"))
                        .textContentType(.oneTimeCode)
                        .focused($focus, equals: .code)
                        .disabled(isSigningIn)
                        .onChange(of: code) { _, value in
                            let digits = value.filter(\.isNumber)
                            if digits != value || digits.count > 8 { code = String(digits.prefix(8)) }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .textFieldStyle(.roundedBorder)
            .controlSize(.large)
            .onSubmit(submit)

            if let errorText {
                Label(errorText, systemImage: "exclamationmark.circle.fill")
                    .font(AppFont.bodySmall)
                    .foregroundStyle(Palette.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // The account has too many sessions: the server handed out a
            // credential that may list and end them.
            if let recovery = app.sessionRecovery {
                sessionList(recovery)
            }

            VStack(spacing: Space.m) {
                Button(action: submit) {
                    HStack(spacing: Space.s) {
                        if isSigningIn {
                            ProgressView().controlSize(.small)
                        }
                        Text(isSigningIn ? "Wird angemeldet …" : "Anmelden")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)
                .disabled(!canSubmit)

                // A stored account that wants its code may also be left.
                if app.hasCredentials {
                    Button("Anderes Konto verwenden") {
                        Task { await account.signOut() }
                    }
                    .buttonStyle(.link)
                    .disabled(isSigningIn || account.isSigningOut)
                }
            }

            Text("E-Mail und Passwort bleiben nur auf diesem Mac.")
                .font(AppFont.caption)
                .foregroundStyle(Palette.textTertiary)
        }
        .frame(width: 320)
        .padding(Space.xl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Palette.background.ignoresSafeArea())
        .animation(.snappy(duration: 0.2), value: needsCode)
        .animation(.snappy(duration: 0.2), value: errorText)
        .onAppear(perform: prefill)
        .onChange(of: account.authProblem) { _, problem in
            guard let problem else { return }
            errorText = problem.localizedDescription
            focus = .code
        }
    }

    /// The sessions of the account, with the button that ends one of them.
    private func sessionList(_ recovery: SessionRecovery) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            SectionLabel(text: "Offene Sitzungen")
            if sessions.sessions.isEmpty {
                Text(sessions.isLoading ? "werden geladen …" : "Die Liste konnte nicht gelesen werden.")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            ForEach(sessions.sessions, id: \.id) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.label)
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.textPrimary)
                            .lineLimit(1)
                        Text(session.ip ?? session.createdDate.map { AppFormat.day($0) } ?? "")
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textTertiary)
                    }
                    Spacer(minLength: Space.s)
                    if session.current {
                        Text("diese")
                            .font(AppFont.caption)
                            .foregroundStyle(Palette.textTertiary)
                    } else {
                        Button("Beenden") {
                            Task { await sessions.revoke(session.id, recovery: recovery) }
                        }
                        .controlSize(.small)
                    }
                }
            }
            Button("Neu laden") {
                Task { await sessions.load(recovery: recovery) }
            }
            .controlSize(.small)
        }
        .padding(Space.m)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.m, style: .continuous))
        .task { await sessions.load(recovery: recovery) }
    }

    /// Whether the code field shows: the server or the stored account asked
    /// for the second factor.
    private var needsCode: Bool {
        askedForCode || account.authProblem == .totpRequired || account.authProblem == .totpRejected
    }

    private var canSubmit: Bool {
        guard !isSigningIn else { return false }
        let filled = !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        return filled && (!needsCode || !code.isEmpty)
    }

    /// Fills in a stored login, so an account that only wants its code needs
    /// nothing else, and puts the cursor into the first empty field.
    private func prefill() {
        guard !didPrefill else { return }
        didPrefill = true
        Task { @MainActor in
            let stored = await app.services.credentials.load()
            if !stored.email.isEmpty { email = stored.email }
            if !stored.password.isEmpty { password = stored.password }
            if needsCode {
                errorText = account.authProblem?.localizedDescription
                focus = .code
            } else {
                focus = email.isEmpty ? .email : .password
            }
        }
    }

    /// Signs in with the entered data (Go `startPanel`, `model.go:761-781`).
    private func submit() {
        guard canSubmit else { return }
        let entered = code
        isSigningIn = true
        errorText = nil
        Task { @MainActor in
            defer { isSigningIn = false }
            do {
                try await app.signIn(email: email, password: password, totp: entered)
                code = ""
                askedForCode = false
                account.signedIn()
            } catch let error as AuthError {
                errorText = error.localizedDescription
                switch error {
                case .totpRequired, .totpRejected:
                    askedForCode = true
                    code = ""
                    focus = .code
                case .missingCredentials:
                    focus = email.isEmpty ? .email : .password
                case .sessionLimit:
                    // The list of the sessions appears on its own.
                    focus = nil
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
