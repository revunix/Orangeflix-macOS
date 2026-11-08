import Foundation
import os

/// One connection to the live chat of the platform: messages, reactions,
/// polls and the state of the connection arrive on `events`.
///
/// The session logs in with a chat token from `tokenProvider` (the App layer
/// calls the API's `chat/token` endpoint) and fetches a fresh one for every
/// reconnect. Call `close()` when the chat is no longer shown.
actor ChatSession {
    /// The Socket.IO server of the platform.
    static let defaultURL = URL(string: "https://io.massengeschmack.tv")!
    /// The chat namespace of the server.
    static let defaultNamespace = "/chat"
    /// The namespace of the votings. The web chat (`voting.js`) reads them
    /// there without a login; the chat namespace never sends them.
    static let votingNamespace = "/voting"
    /// The longest message the server takes, in Unicode scalars.
    static let maxMessageLength = 500
    /// How long the login waits for the namespace after the connect.
    static let loginTimeout: Duration = .seconds(15)

    /// The events of the session, for one consumer. A slow consumer loses
    /// status events before messages; the stream finishes when the session
    /// closes or the connection is lost for good.
    nonisolated let events: AsyncStream<ChatEvent>
    /// The chat name of the account; marks its own messages and reactions.
    nonisolated let username: String

    private let queue: ChatEventQueue
    private let client: SocketIOClient
    /// The connection to the votings, beside the chat.
    private let votingClient: SocketIOClient
    private let tokenProvider: @Sendable () async throws -> String
    private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "live")
    private var token: String
    /// The running voting; its votes change with the updates of the server.
    private var poll: ChatPoll?
    private var pump: Task<Void, Never>?
    private var votingPump: Task<Void, Never>?
    private var isClosed = false

    private init(client: SocketIOClient, votingClient: SocketIOClient, token: String, username: String,
                 tokenProvider: @escaping @Sendable () async throws -> String) {
        let queue = ChatEventQueue()
        self.queue = queue
        self.client = client
        self.votingClient = votingClient
        self.token = token
        self.username = username
        self.tokenProvider = tokenProvider
        events = AsyncStream(unfolding: { await queue.next() })
    }

    deinit {
        let client = client
        let votingClient = votingClient
        Task {
            await client.close()
            await votingClient.close()
        }
        queue.finish()
    }

    /// Connects to the chat and logs in.
    /// - Parameters:
    ///   - url: The Socket.IO server.
    ///   - namespace: The chat namespace.
    ///   - username: The chat name of the account; nil reads the `username`
    ///     claim of the token.
    ///   - urlSession: The session of the WebSocket.
    ///   - tokenProvider: Returns a fresh chat JWT.
    /// - Throws: `LiveError` (`.missingToken`, `.connectTimedOut`,
    ///   `.loginTimedOut`, `.connectRefused`, …) or the error of the provider.
    static func open(
        url: URL = defaultURL,
        namespace: String = defaultNamespace,
        username: String? = nil,
        urlSession: URLSession = .shared,
        tokenProvider: @escaping @Sendable () async throws -> String
    ) async throws -> ChatSession {
        let token = try await tokenProvider()
        guard !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LiveError.missingToken }
        let client = SocketIOClient(
            configuration: .init(url: url, namespace: namespace),
            urlSession: urlSession
        )
        let votingClient = SocketIOClient(
            configuration: .init(url: url, namespace: votingNamespace),
            urlSession: urlSession
        )
        let session = ChatSession(
            client: client, votingClient: votingClient, token: token,
            username: username ?? ChatTokenClaims(jwt: token).username,
            tokenProvider: tokenProvider
        )
        await session.startPump()
        do {
            try await client.connect()
            try await Self.login(client: client, token: token, timeout: loginTimeout)
        } catch {
            await session.close()
            throw error
        }
        await session.startVoting()
        return session
    }

    /// Sends the login once the namespace is connected; a broken server
    /// would otherwise block forever.
    private static func login(client: SocketIOClient, token: String, timeout: Duration) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask { try await client.emit("login", [.string(token)]) }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LiveError.loginTimedOut
            }
            defer { group.cancelAll() }
            try await group.next()
        }
    }

    private func startPump() {
        let client = client
        pump = Task { [weak self] in
            for await event in client.events {
                guard let self else { return }
                await self.handle(event)
            }
            self?.queue.finish()
        }
    }

    /// Connects to the votings. The server sends the running voting on the
    /// connect; without the connection the chat still works, only without
    /// votings.
    private func startVoting() {
        let votingClient = votingClient
        votingPump = Task { [weak self] in
            do {
                try await votingClient.connect()
            } catch {
                await self?.votingFailed(error)
                return
            }
            for await event in votingClient.events {
                guard let self else { return }
                if case .event(let name, let arguments) = event {
                    await self.handleVotingEvent(name, arguments)
                }
            }
        }
    }

    private func votingFailed(_ error: any Error) {
        logger.warning("Voting connection failed: \(error.localizedDescription, privacy: .public)")
    }

    /// Disconnects the chat; `events` finishes.
    func close() async {
        guard !isClosed else { return }
        isClosed = true
        votingPump?.cancel()
        await votingClient.close()
        await client.close()
        queue.finish()
    }

    private func push(_ event: ChatEvent) {
        guard !isClosed else { return }
        queue.push(event)
    }

    // MARK: Incoming

    private func handle(_ event: SocketIOClient.Event) {
        switch event {
        case .connected:
            push(.status("Chat verbunden"))
        case .disconnected, .connectionLost:
            push(.status("Chat getrennt"))
        case .connectError(let reason):
            push(.error(.connectRefused(reason)))
        case .reconnected:
            Task { await self.relogin() }
        case .reconnectFailed:
            push(.error(.connectionLost))
        case .event(let name, let arguments):
            handleEvent(name, arguments)
        }
    }

    /// Logs in again after a reconnect, with a fresh token when the provider
    /// gives one.
    private func relogin() async {
        if let fresh = try? await tokenProvider(), !fresh.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            token = fresh
        } else {
            logger.warning("No fresh chat token for the reconnect; the old one is used")
        }
        do {
            try await client.emit("login", [.string(token)])
            push(.status("Chat verbunden"))
        } catch let error as LiveError {
            push(.error(error))
        } catch {
            push(.error(.transport(error.localizedDescription)))
        }
    }

    private func handleEvent(_ name: String, _ arguments: [LiveJSON]) {
        if name == "deleteVoting" {
            poll = nil
            push(.pollRemoved)
            return
        }
        // The handlers take one argument; an event without one is dropped,
        // as in the Go client.
        guard let data = arguments.first else { return }
        switch name {
        case "msg":
            if let message = ChatWire.message(data, username: username), message.to != "HOST" {
                push(.message(message))
            }
        case "shorthistory":
            guard let messages = ChatWire.history(data, username: username) else { return }
            var ids: [String] = []
            for message in messages where message.to != "HOST" {
                push(.message(message))
                if !message.id.isEmpty { ids.append(message.id) }
            }
            // The reactions of the history are not part of the messages.
            Task { await self.fetchReactions(ids) }
        case "newVoting":
            if let newPoll = ChatWire.poll(data) {
                poll = newPoll
                push(.poll(newPoll))
            }
        case "voteOccured", "votingClosed", "resultsVisibilityChanged", "submissionCount":
            updatePoll(data)
        case "metadata":
            if let update = ChatWire.metadataEvent(data, username: username) {
                push(.reactionChanged(update))
            }
        case "pinnedmsg":
            let text = ChatWire.pinnedText(data)
            if !text.isEmpty {
                push(.message(ChatMessage(from: "Angeheftet", text: text, time: Date(), isAdmin: true)))
            }
        case "userlist":
            if let count = ChatWire.userCount(data) {
                push(.status("\(count) im Chat"))
            }
        default:
            break
        }
    }

    /// An event of the voting namespace (`voting.js`).
    private func handleVotingEvent(_ name: String, _ arguments: [LiveJSON]) {
        switch name {
        case "voteOccured":
            // The votes come as a bare list, one count per answer. A secret
            // voting keeps them hidden until the studio reveals them.
            guard var current = poll, let data = arguments.first,
                  !(current.secret && !current.resultsVisible),
                  let results = ChatWire.counts(data, answers: current.answers.count) else { return }
            current.results = results
            current.resultsVisible = true
            poll = current
            push(.poll(current))
        case "switchToResultView":
            // The server tells a client that already voted: it takes no
            // second vote. The web chat locks its answers then.
            guard poll != nil else { return }
            push(.pollVoted)
        default:
            handleEvent(name, arguments)
        }
    }

    /// Takes over the new votes of the running voting.
    private func updatePoll(_ data: LiveJSON) {
        guard var current = poll else { return }
        defer { poll = current }
        if let update = ChatWire.pollResults(data, answers: current.answers.count) {
            if !update.pollID.isEmpty && !current.pollID.isEmpty && update.pollID != current.pollID { return }
            current.results = update.results
            current.resultsVisible = true
            if update.submissions > 0 { current.submissions = update.submissions }
        }
        if let update = ChatWire.pollVisibility(data, answers: current.answers.count) {
            if !current.pollID.isEmpty && update.pollID != current.pollID { return }
            current.resultsVisible = update.visible
            if update.visible, let results = update.results { current.results = results }
            if update.submissions > 0 { current.submissions = update.submissions }
        }
        if ChatWire.pollClosed(data) {
            current.closed = true
            current.resultsVisible = true
        }
        push(.poll(current))
    }

    /// Reads the reactions of the history and hands them on; a failure only
    /// leaves them out.
    private func fetchReactions(_ messageIDs: [String]) async {
        guard !messageIDs.isEmpty,
              let (states, emojis) = try? await reactionStates(messageIDs: messageIDs),
              !states.isEmpty else { return }
        push(.reactions(states, emojis: emojis))
    }

    // MARK: Outgoing

    /// The trimmed text of a message to send.
    /// - Throws: `LiveError.emptyMessage` or `.messageTooLong`.
    static func validatedMessage(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw LiveError.emptyMessage }
        guard trimmed.unicodeScalars.count <= maxMessageLength else { throw LiveError.messageTooLong }
        return trimmed
    }

    /// Writes a message to the main room.
    func send(_ text: String) async throws {
        try await sendReply(text, replyTo: "")
    }

    /// Writes a message to the main room as an answer to another message;
    /// an empty `replyTo` writes a plain message.
    func sendReply(_ text: String, replyTo: String) async throws {
        var payload: [String: LiveJSON] = [
            "to": .string(ChatReactions.room),
            "txt": .string(try Self.validatedMessage(text)),
            "clientId": .string("tui-\(clock_gettime_nsec_np(CLOCK_REALTIME))"),
        ]
        if !replyTo.isEmpty { payload["replyTo"] = .string(replyTo) }
        try await client.emit("message", [.object(payload)])
    }

    /// Writes a message to the studio. Only the team of the show reads it;
    /// the chat does not show it to the others.
    func sendHost(_ text: String) async throws {
        let payload: [String: LiveJSON] = ["to": .string("HOST"), "txt": .string(try Self.validatedMessage(text))]
        try await client.emit("message", [.object(payload)])
    }

    /// Sends an event and waits for the first argument of the ack.
    private func request(_ event: String, _ payload: LiveJSON, timeout: Duration) async throws -> LiveJSON {
        let answer = try await client.emitWithAck(event, [payload], timeout: timeout)
        guard let first = answer.first else { throw LiveError.noAnswer(event: event) }
        return first
    }

    /// Sets or removes a reaction of the account on a message.
    /// - Throws: `LiveError.reactionUnchanged` when the server kept its
    ///   state (read the state again), `.reactionRefused` for a refusal.
    func react(messageID: String, emoji: String, active: Bool) async throws {
        let answer = try await request("reaction", .object([
            "room": .string(ChatReactions.room),
            "messageId": .string(messageID),
            "emoji": .string(emoji),
            "active": .bool(active),
        ]), timeout: .seconds(8))
        try ChatWire.checkReactionAnswer(answer)
    }

    /// Reads the reactions of messages, a hundred per request.
    /// - Returns: The states and the emojis of reactions the server names
    ///   (key → emoji).
    func reactionStates(messageIDs: [String]) async throws -> (states: [ChatReactionState], emojis: [String: String]) {
        var states: [ChatReactionState] = []
        var emojis: [String: String] = [:]
        for start in stride(from: 0, to: messageIDs.count, by: 100) {
            let batch = messageIDs[start..<min(start + 100, messageIDs.count)]
            let answer = try await request("metadataState", .object([
                "room": .string(ChatReactions.room),
                "messageIds": .array(batch.map { .string($0) }),
            ]), timeout: .seconds(10))
            let part = try ChatWire.metadataState(answer)
            states.append(contentsOf: part.states)
            emojis.merge(part.emojis) { _, new in new }
        }
        return (states, emojis)
    }

    /// Answers the running poll with the answer at `answer` (zero-based).
    /// - Throws: `LiveError.voteRejected` when the server did not count it.
    /// The vote goes to the voting namespace. The web chat sends it without
    /// waiting for an answer, so a missing answer counts as sent; only a
    /// refusal of the server fails.
    func vote(answer: Int) async throws {
        let reply: [LiveJSON]
        do {
            reply = try await votingClient.emitWithAck("vote", [.integer(answer)], timeout: .seconds(4))
        } catch LiveError.noAnswer {
            return
        }
        guard let first = reply.first else { return }
        guard ChatWire.voteAccepted(first) else { throw LiveError.voteRejected }
    }
}
