import SwiftUI

/// The login of the app. It fills the main window while nobody is signed in
/// or the stored account wants its 2FA code; the iris mark responds as the
/// credentials are entered and closes into the full brand orange during sign-in.
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

    /// How far the iris closes: open at rest, half-way as fields are filled,
    /// and fully closed in brand orange while signing in.
    private var irisClosure: Double {
        if isSigningIn { return 1.0 }
        let hasEmail = !email.trimmingCharacters(in: .whitespaces).isEmpty
        let hasPassword = !password.isEmpty
        if needsCode && !code.isEmpty { return 0.9 }
        if hasEmail && hasPassword { return 0.72 }
        if hasEmail || hasPassword { return 0.35 }
        return 0.0
    }

    var body: some View {
        ZStack {
            Palette.background.ignoresSafeArea()
            Circle()
                .fill(Palette.accent.opacity(0.08 + 0.07 * irisClosure))
                .frame(width: 420, height: 420)
                .blur(radius: 90)
                .allowsHitTesting(false)

            VStack(spacing: Space.xl) {
                VStack(spacing: Space.m) {
                    IrisBrandMark(closed: irisClosure, size: 54)
                    VStack(spacing: Space.xs) {
                        Text("orangeflix")
                            .font(.system(size: 13, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(Palette.accentText)
                        Text(needsCode ? "Bestätigungscode" : "Willkommen zurück")
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
                    fieldBox(symbol: "envelope", focused: focus == .email) {
                        TextField("E-Mail", text: $email, prompt: Text("E-Mail-Adresse"))
                            .textFieldStyle(.plain)
                            .textContentType(.username)
                            .focused($focus, equals: .email)
                            .disabled(isSigningIn)
                    }

                    fieldBox(symbol: "lock", focused: focus == .password) {
                        SecureField("Passwort", text: $password, prompt: Text("Passwort"))
                            .textFieldStyle(.plain)
                            .textContentType(.password)
                            .focused($focus, equals: .password)
                            .disabled(isSigningIn)
                    }

                    if needsCode {
                        fieldBox(symbol: "key.horizontal", focused: focus == .code) {
                            TextField("Code", text: $code, prompt: Text("6-stelliger Code"))
                                .textFieldStyle(.plain)
                                .font(AppFont.digitsMedium)
                                .textContentType(.oneTimeCode)
                                .focused($focus, equals: .code)
                                .disabled(isSigningIn)
                                .onChange(of: code) { _, value in
                                    let digits = value.filter(\.isNumber)
                                    if digits != value || digits.count > 8 { code = String(digits.prefix(8)) }
                                }
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .onSubmit(submit)

                if let errorText {
                    HStack(alignment: .top, spacing: Space.s) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(Palette.danger)
                        Text(errorText)
                            .font(AppFont.bodySmall)
                            .foregroundStyle(Palette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(Space.m)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Palette.dangerSoft, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
                }

                if let recovery = app.sessionRecovery {
                    sessionList(recovery)
                }

                VStack(spacing: Space.m) {
                    Button(action: submit) {
                        HStack(spacing: Space.s) {
                            if isSigningIn {
                                ProgressView()
                                    .controlSize(.small)
                                    .tint(.white)
                            }
                            Text(isSigningIn ? "Wird angemeldet …" : "Anmelden")
                                .font(AppFont.subheading)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                        .background(
                            Capsule().fill(canSubmit ? Palette.accent : Palette.accent.opacity(0.4))
                        )
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSubmit)

                    if app.hasCredentials {
                        Button("Anderes Konto verwenden") {
                            Task { await account.signOut() }
                        }
                        .buttonStyle(.link)
                        .font(AppFont.bodySmall)
                        .disabled(isSigningIn || account.isSigningOut)
                    }
                }

                Label("Zugangsdaten bleiben im Schlüsselbund dieses Macs.", systemImage: "lock.shield")
                    .font(AppFont.caption)
                    .foregroundStyle(Palette.textTertiary)
            }
            .padding(Space.xxl)
            .frame(width: 388)
            .contentCard(radius: Radius.panel)
            .shadow(color: .black.opacity(0.18), radius: 24, y: 10)
            .padding(Space.xl)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.snappy(duration: 0.22), value: needsCode)
        .animation(.snappy(duration: 0.22), value: errorText)
        .animation(.easeOut(duration: 0.25), value: irisClosure)
        .onAppear(perform: prefill)
        .onChange(of: account.authProblem) { _, problem in
            guard let problem else { return }
            errorText = problem.localizedDescription
            focus = .code
        }
    }

    private func fieldBox<FieldContent: View>(
        symbol: String,
        focused: Bool,
        @ViewBuilder content: () -> FieldContent
    ) -> some View {
        HStack(spacing: Space.s) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(focused ? Palette.accentText : Palette.textTertiary)
                .frame(width: 18)
            content()
                .font(AppFont.body)
                .foregroundStyle(Palette.textPrimary)
        }
        .padding(.horizontal, Space.m)
        .frame(height: 38)
        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.l, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Radius.l, style: .continuous)
                .strokeBorder(focused ? Palette.accent.opacity(0.65) : Palette.border, lineWidth: 1)
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

    private var needsCode: Bool {
        askedForCode || account.authProblem == .totpRequired || account.authProblem == .totpRejected
    }

    private var canSubmit: Bool {
        guard !isSigningIn else { return false }
        let filled = !email.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
        return filled && (!needsCode || !code.isEmpty)
    }

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
                    focus = nil
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }
}
