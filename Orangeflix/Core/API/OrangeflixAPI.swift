import Foundation
import os

/// The tokens of a v3 session. The App layer stores them in the Keychain and
/// hands them back with `adopt` or `setToken` on the next start.
struct AuthSession: Sendable, Hashable, Codable {
    var accessToken: String
    var refreshToken: String
    /// The time the access token runs out; `nil` when unknown.
    var expiresAt: Date?
}

/// How long the answer of a GET may come from the `ResponseCache`.
struct APICachePolicy: Sendable {
    var maxAge: TimeInterval
    /// Serves the stored answer when the request fails (for example when the
    /// network is gone).
    var servesStaleOnError: Bool = true
}

/// The client of the version 3 API (https://massengeschmack.tv/api/v3/).
///
/// It authenticates with a bearer token. A token that is known is kept as
/// long as it works: the sessions of an account are limited, so a new login
/// only happens when the token is missing, expired or rejected, and then
/// exactly once, even when several requests fail at the same time.
actor OrangeflixAPI {
    let baseURL: String
    let userAgent: String
    /// The device name the login registers the session under.
    let deviceName: String

    /// Every new session (login, TOTP login, refresh, token recovery) is
    /// published here, so the App layer can persist it. Buffers the newest.
    nonisolated let sessionUpdates: AsyncStream<AuthSession>

    private let http: APIHTTP
    private let attempts: Int
    /// The persisted answers; nil disables the cache.
    private let cache: ResponseCache?
    /// The prefix of the keys of the current account; "" until the App layer
    /// sets it, which keeps the cache unused.
    private var cacheScope = ""
    private let sessionContinuation: AsyncStream<AuthSession>.Continuation
    private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "api")

    private var email: String
    private var password: String
    private var accessToken = ""
    private var refreshToken = ""
    private var expiresAt: Date?

    /// The confirmations the server still wants; it names them with the
    /// login and with every confirmation.
    private(set) var pendingActions: [UiAction] = []

    // The auth lock serialises everything that reads or replaces the tokens,
    // like the mutex of the Go client.
    private var authLocked = false
    private var authWaiters: [CheckedContinuation<Void, Never>] = []

    /// - Parameters:
    ///   - email: the login of the account; may be set later.
    ///   - cache: the persisted answers; nil keeps every request on the wire.
    ///   - attempts: tries per request (transport errors, 5xx, 429).
    ///   - sleep: the pause between tries; injectable for tests.
    init(
        email: String = "",
        password: String = "",
        baseURL: String = APIDefaults.v3BaseURL,
        userAgent: String = APIDefaults.userAgent,
        deviceName: String = "orangeflix-dl",
        cache: ResponseCache? = nil,
        attempts: Int = APIDefaults.v3Attempts,
        urlSession: URLSession = APIDefaults.urlSession,
        sleep: @escaping @Sendable (Duration) async -> Void = APIDefaults.sleep
    ) {
        self.email = email
        self.password = password
        self.baseURL = baseURL
        self.userAgent = userAgent
        self.deviceName = deviceName
        self.cache = cache
        self.attempts = attempts > 0 ? attempts : APIDefaults.v3Attempts
        self.http = APIHTTP(session: urlSession, sleep: sleep)
        (sessionUpdates, sessionContinuation) = AsyncStream.makeStream(of: AuthSession.self, bufferingPolicy: .bufferingNewest(1))
    }

    deinit {
        sessionContinuation.finish()
    }

    // MARK: Session state

    /// Replaces the login used for new sessions.
    func setCredentials(email: String, password: String) {
        self.email = email
        self.password = password
    }

    /// Stores a token that was fetched earlier.
    func setToken(_ session: AuthSession) async {
        await withAuthLock {
            accessToken = session.accessToken
            refreshToken = session.refreshToken
            expiresAt = session.expiresAt
        }
    }

    /// Fills only the tokens that are still empty, so a stored token never
    /// overwrites a fresh login.
    func adopt(_ session: AuthSession) async {
        await withAuthLock {
            if accessToken.isEmpty && !session.accessToken.isEmpty { accessToken = session.accessToken }
            if refreshToken.isEmpty && !session.refreshToken.isEmpty { refreshToken = session.refreshToken }
            if expiresAt == nil, let expiry = session.expiresAt { expiresAt = expiry }
        }
    }

    /// The current tokens.
    func session() async -> AuthSession {
        await withAuthLock { currentSession }
    }

    private var currentSession: AuthSession {
        AuthSession(accessToken: accessToken, refreshToken: refreshToken, expiresAt: expiresAt)
    }

    /// The token is usable until one minute before it runs out.
    private var tokenUsable: Bool {
        guard !accessToken.isEmpty else { return false }
        guard let expiresAt else { return true }
        return Date() < expiresAt.addingTimeInterval(-60)
    }

    // MARK: Authentication

    /// Opens a new session with email and password.
    /// - Throws: `APIError.totpRequired(token:)` when the account asks for a
    ///   second factor; finish with `completeTotpLogin`.
    func login() async throws {
        try await withAuthLock { try await loginLocked() }
    }

    /// Finishes the login with the code of the second factor.
    func completeTotpLogin(totpToken: String, code: String) async throws {
        let body = try APIJSON.encode([
            "totpToken": totpToken,
            "code": code.trimmingCharacters(in: .whitespacesAndNewlines),
        ])
        try await withAuthLock {
            let data = try await sendAuth(path: "auth/login/totp", body: body)
            let answer = try APIJSON.decode(AuthAnswer.self, from: data)
            guard !answer.auth.accessToken.isEmpty else { throw APIError.loginFailed(nil) }
            pendingActions = answer.uiActions.filter(\.required)
            apply(answer.auth)
        }
    }

    /// Fetches a new access token with the refresh token.
    func refresh() async throws {
        try await withAuthLock { try await refreshLocked() }
    }

    /// Makes sure a usable access token is there. A known, unexpired token is
    /// kept; otherwise the refresh token is tried, then a login.
    func ensureToken() async throws {
        try await withAuthLock {
            if !tokenUsable { accessToken = "" }
            if !accessToken.isEmpty { return }
            if !refreshToken.isEmpty {
                do {
                    try await refreshLocked()
                    return
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    // Only a rejected refresh token is dropped; a transport
                    // error must not cost the session.
                    guard Self.rejectsToken(error) else { throw error }
                    logger.notice("Der Token konnte nicht erneuert werden (\(error.localizedDescription, privacy: .public)), hole einen neuen.")
                    refreshToken = ""
                }
            }
            try await loginLocked()
        }
    }

    private func loginLocked() async throws {
        let body = try APIJSON.encode(LoginBody(email: email, password: password, remember: true,
                                                deviceName: deviceName, client: LoginClient()))
        let data = try await sendAuth(path: "auth/login", body: body)
        let answer = try APIJSON.decode(AuthAnswer.self, from: data)
        if answer.requiresTotp {
            throw APIError.totpRequired(token: answer.totpToken)
        }
        guard !answer.auth.accessToken.isEmpty else {
            throw APIError.loginFailed(answer.error.isEmpty ? nil : answer.error)
        }
        // The server names the confirmations that are still open.
        pendingActions = answer.uiActions.filter(\.required)
        apply(answer.auth)
    }

    /// Sends a request of the login. The server refuses the login with 409 or
    /// 429 when the account has too many sessions; then the body carries the
    /// recovery token that may list and end the sessions, so the body is read
    /// in every case.
    private func sendAuth(path: String, body: Data) async throws -> Data {
        let request = try makeRequest(method: "POST", path: path, body: body, token: "")
        // A repeated login would only extend the lock of the account.
        let policy = APIRetryPolicy(attempts: attempts, retryRateLimit: false,
                                    describe: { APIHTTP.apiErrorMessage($0) })
        let response = try await http.send(request, policy: policy)
        if response.status == 409 || response.status == 429 {
            if let recovery = Self.sessionRecovery(in: response.body), !recovery.token.isEmpty {
                throw APIError.sessionLimitReached(recovery: recovery)
            }
        }
        if response.status == 401 { throw APIError.unauthorized }
        if response.status >= 400 {
            throw APIError.http(status: response.status, message: APIHTTP.apiErrorMessage(response.body))
        }
        return response.body
    }

    /// Reads the recovery token out of an answer of the login.
    nonisolated static func sessionRecovery(in body: Data) -> SessionRecovery? {
        struct Envelope: Decodable { let sessionRecovery: SessionRecovery? }
        guard let envelope = try? JSONDecoder().decode(Envelope.self, from: body) else { return nil }
        return envelope.sessionRecovery
    }

    private func refreshLocked() async throws {
        guard !refreshToken.isEmpty else { throw APIError.noRefreshToken }
        let body = try APIJSON.encode(["refreshToken": refreshToken])
        let data = try await send(token: "", method: "POST", path: "auth/refresh", body: body)
        let answer = try APIJSON.decode(AuthAnswer.self, from: data)
        guard !answer.auth.accessToken.isEmpty else {
            throw APIError.refreshFailed(answer.error.isEmpty ? nil : answer.error)
        }
        apply(answer.auth)
    }

    /// Stores the tokens of an answer and publishes the session.
    private func apply(_ auth: AuthPayload) {
        accessToken = auth.accessToken
        if !auth.refreshToken.isEmpty { refreshToken = auth.refreshToken }
        if auth.expiresAt > 0 {
            expiresAt = Date(timeIntervalSince1970: TimeInterval(auth.expiresAt))
        } else if auth.expiresIn > 0 {
            expiresAt = Date().addingTimeInterval(TimeInterval(auth.expiresIn))
        } else {
            expiresAt = nil
        }
        sessionContinuation.yield(currentSession)
    }

    // MARK: Requests

    /// Sets the prefix of the stored answers of the current account; "" keeps
    /// the cache unused.
    func setCacheScope(_ scope: String) {
        cacheScope = scope
    }

    /// Sends a request with the access token. A rejected token is renewed
    /// once (refresh, else login) and the request is repeated. A GET whose
    /// stored answer is younger than `cache.maxAge` returns without a request.
    func requestData(_ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil, cache policy: APICachePolicy? = nil) async throws -> Data {
        let key = cacheKey(method, path, query: query, body: body, policy: policy)
        var stored: (body: Data, storedAt: Date)?
        if let key, let policy {
            stored = await cache?.value(for: key)
            if let stored, Date().timeIntervalSince(stored.storedAt) <= policy.maxAge {
                return stored.body
            }
        }
        do {
            let data = try await authorizedData(method, path, query: query, body: body)
            // An empty answer (304) carries no content, so the stored body
            // stays in place.
            if let key, !data.isEmpty { await cache?.store(data, for: key) }
            return data
        } catch {
            guard let policy, let stored, policy.servesStaleOnError else { throw error }
            logger.notice("Antwort aus dem Zwischenspeicher: \(path, privacy: .public)")
            return stored.body
        }
    }

    /// The key of a stored answer; nil when the request is not cached (only
    /// GETs without body, and only with a scope).
    private func cacheKey(_ method: String, _ path: String, query: [(String, String)], body: Data?, policy: APICachePolicy?) -> String? {
        guard policy != nil, method == "GET", body == nil, cache != nil, !cacheScope.isEmpty else { return nil }
        let pairs = query.sorted { $0.0 < $1.0 }.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
        return "\(cacheScope)|\(path)?" + pairs
    }

    /// Drops the stored answers of one path, after a change that made them
    /// wrong.
    func invalidateCache(_ path: String) async {
        await cache?.remove(prefix: "\(cacheScope)|\(path)?")
    }

    /// Sends the request and recovers a rejected token.
    private func authorizedData(_ method: String, _ path: String, query: [(String, String)], body: Data?) async throws -> Data {
        let token = await withAuthLock { accessToken }
        do {
            return try await send(token: token, method: method, path: path, query: query, body: body)
        } catch let error as APIError where error == .unauthorized && !token.isEmpty {
            return try await withAuthLock {
                // Another request may have replaced the token already.
                if !accessToken.isEmpty && accessToken != token {
                    return try await send(token: accessToken, method: method, path: path, query: query, body: body)
                }
                logger.notice("Der Token wurde abgelehnt, erneuere ihn.")
                accessToken = ""
                try await recoverTokens(rejected: token)
                return try await send(token: accessToken, method: method, path: path, query: query, body: body)
            }
        }
    }

    /// Gets a new token after `token` was rejected: the refresh token, else a
    /// login. A failure that does not concern the token itself (a transport
    /// error, a rate limit) keeps the tokens and is thrown unchanged — a
    /// flaky network must not cost the session.
    private func recoverTokens(rejected token: String) async throws {
        if !refreshToken.isEmpty {
            do {
                try await refreshLocked()
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard Self.rejectsToken(error) else {
                    // The token may have been fine all along; the next request
                    // tries it again.
                    accessToken = token
                    throw error
                }
                logger.notice("Der Token konnte nicht erneuert werden (\(error.localizedDescription, privacy: .public)), hole einen neuen.")
                refreshToken = ""
            }
        }
        try await loginLocked()
    }

    /// Whether the error says the refresh token itself is no good.
    private nonisolated static func rejectsToken(_ error: any Error) -> Bool {
        switch error as? APIError {
        case .unauthorized, .refreshFailed, .http: true
        default: false
        }
    }

    /// Sends a request and decodes the answer.
    func request<T: Decodable>(_ type: T.Type, _ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil, cache policy: APICachePolicy? = nil) async throws -> T {
        try APIJSON.decode(type, from: try await requestData(method, path, query: query, body: body, cache: policy))
    }

    /// Sends a request and decodes one field of the answer object; a missing
    /// or null field gives the zero value.
    func requestField<T: Decodable & APIZeroValue & Sendable>(_ field: String, as type: T.Type, _ method: String, _ path: String, query: [(String, String)] = [], body: Data? = nil, cache policy: APICachePolicy? = nil) async throws -> T {
        let data = try await requestData(method, path, query: query, body: body, cache: policy)
        let decoder = JSONDecoder()
        decoder.userInfo[APIFieldEnvelope<T>.fieldKey] = field
        do {
            return try decoder.decode(APIFieldEnvelope<T>.self, from: data).value
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }

    /// Sends a request with an explicit token and without the recovery of a
    /// rejected token.
    func send(token: String, method: String, path: String, query: [(String, String)] = [], body: Data? = nil) async throws -> Data {
        let request = try makeRequest(method: method, path: path, query: query, body: body, token: token)

        // A repeated login would only extend the lock of the account.
        let policy = APIRetryPolicy(attempts: attempts, retryRateLimit: !path.contains("auth/login"),
                                    describe: { APIHTTP.apiErrorMessage($0) })
        let response = try await http.send(request, policy: policy)
        if response.status == 401 { throw APIError.unauthorized }
        if response.status >= 400 {
            throw APIError.http(status: response.status, message: APIHTTP.apiErrorMessage(response.body))
        }
        return response.body
    }

    /// Builds the request of the API.
    func makeRequest(method: String, path: String, query: [(String, String)] = [], body: Data? = nil,
                     token: String) throws -> URLRequest {
        var address = baseURL + (path.hasPrefix("/") ? String(path.dropFirst()) : path)
        if !query.isEmpty { address += "?" + APIHTTP.encodeQuery(query) }
        guard let url = URL(string: address) else { throw APIError.invalidURL(address) }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        }
        if !token.isEmpty {
            request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        }
        return request
    }

    // MARK: Auth lock

    private func withAuthLock<T>(_ body: () async throws -> T) async rethrows -> T {
        if authLocked {
            await withCheckedContinuation { authWaiters.append($0) }
        } else {
            authLocked = true
        }
        defer {
            if authWaiters.isEmpty {
                authLocked = false
            } else {
                authWaiters.removeFirst().resume()
            }
        }
        return try await body()
    }
}

// MARK: Auth payloads

private struct LoginBody: Encodable {
    let email: String
    let password: String
    let remember: Bool
    let deviceName: String
    /// The client the session belongs to; the server shows it in the list of
    /// the sessions of the account.
    let client: LoginClient
}

/// How the app names itself in the list of the sessions of an account.
private struct LoginClient: Encodable {
    let id = "orangeflix-mac"
    let platform = "macos"
    let deviceType = "mac"
}

private struct AuthPayload: Decodable {
    var accessToken = ""
    var refreshToken = ""
    var expiresIn: Int64 = 0
    var expiresAt: Int64 = 0

    init() {}

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        accessToken = try c.zero("accessToken")
        refreshToken = try c.zero("refreshToken")
        expiresIn = try c.zero("expiresIn")
        expiresAt = try c.zero("expiresAt")
    }
}

/// The answer of login, TOTP login and refresh.
private struct AuthAnswer: Decodable {
    let auth: AuthPayload
    let requiresTotp: Bool
    let totpToken: String
    let error: String
    /// The short-lived credential that may list and end the sessions; the
    /// server sends it when the login was refused.
    let sessionRecovery: SessionRecovery?
    /// The legal confirmations the server still wants.
    let uiActions: [UiAction]

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        auth = try c.optional("auth") ?? AuthPayload()
        requiresTotp = try c.zero("requiresTotp")
        totpToken = try c.zero("totpToken")
        error = try c.zero("error")
        sessionRecovery = try c.optional("sessionRecovery")
        let raw: [JSONValue]? = c.tolerant("uiActions")
        uiActions = (raw ?? []).map { UiAction(raw: $0) }
    }
}

/// Decodes the one field named in the decoder's user info.
struct APIFieldEnvelope<T: Decodable & APIZeroValue & Sendable>: Decodable {
    static var fieldKey: CodingUserInfoKey { CodingUserInfoKey(rawValue: "orangeflix.apiField")! }

    let value: T

    init(from decoder: any Decoder) throws {
        let field = decoder.userInfo[Self.fieldKey] as? String ?? ""
        value = try decoder.apiContainer().zero(field)
    }
}
