import Foundation
import os

/// A Socket.IO v5 client (Engine.IO v4 over WebSocket) for one namespace,
/// modelled on the Go client the CLI uses: ping/pong heartbeat with the
/// timeout of the server, acks with timeouts, binary attachments, and
/// automatic reconnection with exponential backoff.
actor SocketIOClient {
    /// The lifecycle and the events of the namespace, in the order they
    /// arrive.
    enum Event: Sendable, Hashable {
        /// The server acknowledged the namespace CONNECT.
        case connected
        /// The server disconnected the namespace.
        case disconnected
        /// The server refused the namespace; the reason of the server.
        case connectError(String)
        /// An event of the server with its arguments.
        case event(String, [LiveJSON])
        /// The transport dropped; the reconnect attempts begin.
        case connectionLost
        /// A reconnect attempt succeeded; the CONNECT was sent again.
        case reconnected
        /// All reconnect attempts failed; the client is closed.
        case reconnectFailed
    }

    struct Configuration: Sendable {
        /// The server ("https://host"); an empty path becomes "/socket.io/".
        var url: URL
        var namespace: String
        /// Limits dial and Engine.IO handshake of every attempt.
        var connectTimeout: Duration = .seconds(15)
        var reconnectAttempts = 5
        /// The first backoff; it doubles up to eight times this value.
        var reconnectWait: Duration = .seconds(5)
        /// The largest sum of the attachments of one binary packet.
        var maxBinarySize = 64 << 20
    }

    private static let maxBinaryAttachments = 1 << 16

    /// The events of the client; finishes when the client closes.
    nonisolated let events: AsyncStream<Event>
    private let eventContinuation: AsyncStream<Event>.Continuation
    private let configuration: Configuration
    private let urlSession: URLSession
    private let logger = Logger(subsystem: "com.revunix.orangeflix", category: "live")

    private var socket: URLSessionWebSocketTask?
    /// Changes with every transport; loops of an old one stop.
    private var generation = 0
    private var receiveTask: Task<Void, Never>?
    private var heartbeatTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var heartbeatTimeout: Duration?
    private var heartbeatDeadline: ContinuousClock.Instant?
    private var connectStarted = false
    private var isClosed = false
    private var isReconnecting = false

    /// Emits wait until the namespace is acknowledged.
    private var namespaceConnected = false
    private var gateWaiters: [Int: CheckedContinuation<Void, any Error>] = [:]
    private var nextWaiterID = 0

    private var ackCounter = 0
    private var ackWaiters: [Int: CheckedContinuation<[LiveJSON], any Error>] = [:]
    private var ackTimers: [Int: Task<Void, Never>] = [:]

    private var pendingBinary: SocketIOPacket?
    private var pendingAttachments: [Data] = []
    private var pendingBytes = 0

    init(configuration: Configuration, urlSession: URLSession = .shared) {
        self.configuration = configuration
        self.urlSession = urlSession
        (events, eventContinuation) = AsyncStream.makeStream(of: Event.self)
    }

    // MARK: Connection

    /// Opens the transport and waits for the Engine.IO handshake, then sends
    /// the namespace CONNECT. Like the Go client it returns before the
    /// namespace is acknowledged; emits wait for that.
    func connect() async throws {
        guard !isClosed else { throw LiveError.closed }
        guard !connectStarted else { throw LiveError.protocolViolation("connect wurde zweimal aufgerufen") }
        connectStarted = true
        try await openTransport()
    }

    /// The WebSocket URL of the Engine.IO endpoint.
    func webSocketURL() throws -> URL {
        guard var components = URLComponents(url: configuration.url, resolvingAgainstBaseURL: false) else {
            throw LiveError.handshakeFailed("ungültige Adresse")
        }
        switch components.scheme?.lowercased() {
        case "http", "ws": components.scheme = "ws"
        case "https", "wss": components.scheme = "wss"
        default: throw LiveError.handshakeFailed("ungültiges Schema der Adresse")
        }
        if components.path.isEmpty { components.path = "/socket.io/" }
        var items = (components.queryItems ?? []).filter { $0.name != "EIO" && $0.name != "transport" }
        items.append(URLQueryItem(name: "EIO", value: "4"))
        items.append(URLQueryItem(name: "transport", value: "websocket"))
        components.queryItems = items.sorted { $0.name < $1.name }
        guard let url = components.url else { throw LiveError.handshakeFailed("ungültige Adresse") }
        return url
    }

    private func openTransport() async throws {
        var request = URLRequest(url: try webSocketURL())
        request.timeoutInterval = Self.seconds(configuration.connectTimeout)
        let task = urlSession.webSocketTask(with: request)
        task.maximumMessageSize = configuration.maxBinarySize
        generation += 1
        let current = generation
        socket = task
        task.resume()
        let handshake: EngineIOHandshake
        do {
            handshake = try await Self.awaitOpen(task, timeout: configuration.connectTimeout)
        } catch {
            task.cancel(with: .goingAway, reason: nil)
            if current == generation { socket = nil }
            throw error
        }
        guard !isClosed, current == generation else {
            task.cancel(with: .goingAway, reason: nil)
            throw LiveError.closed
        }
        logger.debug("Engine.IO open, ping interval \(handshake.pingInterval) ms")
        heartbeatTimeout = handshake.heartbeatTimeout
        refreshHeartbeat()
        // The CONNECT goes out before the loops start: from their start on,
        // the caller runs without suspending until it marks the transport
        // as current, so a drop is never lost between the two.
        let connect = SocketIOPacket(type: .connect, namespace: configuration.namespace, payload: .object([:]))
        do {
            try await sendFrame(EngineIOPacket(type: .message, text: connect.encoded).encoded)
        } catch {
            logger.error("Socket.IO CONNECT failed: \(error.localizedDescription, privacy: .public)")
        }
        guard !isClosed, current == generation else { throw LiveError.closed }
        receiveTask = Task { await self.receiveLoop(task, generation: current) }
        heartbeatTask = Task { await self.heartbeatLoop(generation: current) }
    }

    /// Reads frames until the OPEN packet of the server arrives.
    private static func awaitOpen(_ task: URLSessionWebSocketTask, timeout: Duration) async throws -> EngineIOHandshake {
        let started = ContinuousClock.now
        let timer = Task {
            try? await Task.sleep(for: timeout)
            if !Task.isCancelled { task.cancel(with: .goingAway, reason: nil) }
        }
        defer { timer.cancel() }
        return try await withTaskCancellationHandler {
            while true {
                let message: URLSessionWebSocketTask.Message
                do {
                    message = try await task.receive()
                } catch {
                    try Task.checkCancellation()
                    if ContinuousClock.now - started >= timeout { throw LiveError.connectTimedOut }
                    throw LiveError.transport(error.localizedDescription)
                }
                guard case .string(let text) = message else { continue }
                let packet = try EngineIOPacket.decode(text)
                if packet.type == .open { return try EngineIOHandshake(json: packet.text) }
            }
        } onCancel: {
            task.cancel(with: .goingAway, reason: nil)
        }
    }

    private func receiveLoop(_ task: URLSessionWebSocketTask, generation current: Int) async {
        while true {
            let message: URLSessionWebSocketTask.Message
            do {
                message = try await task.receive()
            } catch {
                transportDropped(generation: current, reason: error.localizedDescription)
                return
            }
            guard current == generation, !isClosed else { return }
            switch message {
            case .string(let text): handleFrame(text)
            case .data(let data): handleAttachment(data)
            @unknown default: break
            }
        }
    }

    private func refreshHeartbeat() {
        heartbeatDeadline = heartbeatTimeout.map { ContinuousClock.now + $0 }
    }

    /// Drops the transport when the server stops pinging.
    private func heartbeatLoop(generation current: Int) async {
        while !Task.isCancelled {
            guard current == generation, let deadline = heartbeatDeadline else { return }
            if ContinuousClock.now >= deadline {
                transportDropped(generation: current, reason: "engine.io ping timeout")
                return
            }
            try? await Task.sleep(until: deadline, clock: .continuous)
        }
    }

    private func tearDownTransport() {
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        receiveTask = nil
        heartbeatTask = nil
        socket?.cancel(with: .goingAway, reason: nil)
        socket = nil
        heartbeatDeadline = nil
        clearPendingBinary()
    }

    private func transportDropped(generation current: Int, reason: String) {
        guard current == generation, !isClosed, !isReconnecting else { return }
        logger.warning("Chat transport dropped: \(reason, privacy: .public)")
        generation += 1
        tearDownTransport()
        // Emits after the drop wait for the CONNECT of the next transport.
        namespaceConnected = false
        eventContinuation.yield(.connectionLost)
        guard configuration.reconnectAttempts > 0 else {
            eventContinuation.yield(.reconnectFailed)
            close()
            return
        }
        isReconnecting = true
        reconnectTask = Task { await self.reconnectLoop() }
    }

    /// Up to `reconnectAttempts` attempts; the wait doubles each time and
    /// stays below eight times the first one.
    private func reconnectLoop() async {
        let base = configuration.reconnectWait > .zero ? configuration.reconnectWait : .seconds(1)
        let maxBackoff = base * 8
        var backoff = base
        for attempt in 1...configuration.reconnectAttempts {
            try? await Task.sleep(for: backoff)
            if isClosed || Task.isCancelled { return }
            do {
                try await openTransport()
                logger.info("Chat reconnected on attempt \(attempt)")
                isReconnecting = false
                eventContinuation.yield(.reconnected)
                return
            } catch {
                if isClosed { return }
                logger.error("Chat reconnect attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)")
            }
            backoff = min(backoff * 2, maxBackoff)
        }
        isReconnecting = false
        eventContinuation.yield(.reconnectFailed)
        close()
    }

    /// Closes the connection for good. Waiting emits and requests fail.
    func close() {
        guard !isClosed else { return }
        isClosed = true
        generation += 1
        reconnectTask?.cancel()
        reconnectTask = nil
        receiveTask?.cancel()
        heartbeatTask?.cancel()
        socket?.cancel(with: .normalClosure, reason: nil)
        socket = nil
        clearPendingBinary()
        failGate(LiveError.closed)
        for (id, waiter) in ackWaiters {
            ackTimers.removeValue(forKey: id)?.cancel()
            waiter.resume(throwing: LiveError.closed)
        }
        ackWaiters.removeAll()
        eventContinuation.finish()
    }

    // MARK: Incoming packets

    private func handleFrame(_ text: String) {
        let packet: EngineIOPacket
        do {
            packet = try EngineIOPacket.decode(text)
        } catch {
            logger.error("Unreadable Engine.IO packet")
            return
        }
        switch packet.type {
        case .ping:
            refreshHeartbeat()
            Task { try? await self.sendFrame(EngineIOPacket(type: .pong).encoded) }
        case .message:
            if let binary = packet.binary {
                handleAttachment(binary)
            } else {
                handleSocketIO(packet.text)
            }
        case .open, .close, .pong, .upgrade, .noop:
            break
        }
    }

    private func handleSocketIO(_ text: String) {
        // A text packet cannot interrupt the attachments of a binary one:
        // both are dropped.
        if pendingBinary != nil {
            clearPendingBinary()
            logger.error("Text packet before all binary attachments; both dropped")
            return
        }
        let packet: SocketIOPacket
        do {
            packet = try SocketIOPacket.decode(text)
        } catch {
            logger.error("Unreadable Socket.IO packet: \(error.localizedDescription, privacy: .public)")
            return
        }
        guard let needed = packet.attachments else {
            dispatch(packet)
            return
        }
        if needed == 0 {
            if let complete = try? packet.reconstructed(with: []) { dispatch(complete) }
            return
        }
        guard needed > 0, needed <= Self.maxBinaryAttachments else {
            logger.error("Binary packet declares \(needed) attachments; dropped")
            return
        }
        pendingBinary = packet
        pendingAttachments = []
        pendingBytes = 0
    }

    private func handleAttachment(_ data: Data) {
        guard let pending = pendingBinary else {
            logger.error("Binary attachment without a binary packet; dropped")
            return
        }
        guard data.count <= configuration.maxBinarySize - pendingBytes else {
            clearPendingBinary()
            logger.error("Binary attachments too large; dropped")
            return
        }
        pendingBytes += data.count
        pendingAttachments.append(data)
        guard pendingAttachments.count >= (pending.attachments ?? 0) else { return }
        let attachments = pendingAttachments
        clearPendingBinary()
        do {
            dispatch(try pending.reconstructed(with: attachments))
        } catch {
            logger.error("Binary packet not rebuilt: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func clearPendingBinary() {
        pendingBinary = nil
        pendingAttachments = []
        pendingBytes = 0
    }

    private func dispatch(_ packet: SocketIOPacket) {
        if packet.type == .ack || packet.type == .binaryAck {
            guard let id = packet.ackID else { return }
            resolveAck(id, .success(packet.arguments))
            return
        }
        guard packet.namespace == configuration.namespace else { return }
        switch packet.type {
        case .connect:
            namespaceConnected = true
            for waiter in gateWaiters.values { waiter.resume() }
            gateWaiters.removeAll()
            eventContinuation.yield(.connected)
        case .disconnect:
            eventContinuation.yield(.disconnected)
        case .event, .binaryEvent:
            if let name = packet.eventName { eventContinuation.yield(.event(name, packet.arguments)) }
        case .connectError:
            let reason = Self.connectErrorReason(packet.errorMessage ?? "")
            failGate(LiveError.connectRefused(reason))
            eventContinuation.yield(.connectError(reason))
        case .ack, .binaryAck:
            break
        }
    }

    /// The text of a CONNECT_ERROR: the `message` of the JSON object, else
    /// the raw payload.
    static func connectErrorReason(_ raw: String) -> String {
        if case .object(let fields)? = try? LiveJSON.parse(raw), case .string(let message)? = fields["message"] {
            return message
        }
        return raw
    }

    // MARK: Outgoing packets

    private func sendFrame(_ text: String) async throws {
        guard let socket else { throw LiveError.notConnected }
        do {
            try await socket.send(.string(text))
        } catch {
            throw LiveError.transport(error.localizedDescription)
        }
    }

    private func sendPacket(_ packet: SocketIOPacket) async throws {
        try await sendFrame(EngineIOPacket(type: .message, text: packet.encoded).encoded)
    }

    /// Waits until the server acknowledged the namespace.
    func waitUntilConnected() async throws {
        if namespaceConnected { return }
        if isClosed { throw LiveError.closed }
        let id = nextWaiterID
        nextWaiterID += 1
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    gateWaiters[id] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelGateWaiter(id) }
        }
    }

    private func cancelGateWaiter(_ id: Int) {
        gateWaiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
    }

    private func failGate(_ error: LiveError) {
        for waiter in gateWaiters.values { waiter.resume(throwing: error) }
        gateWaiters.removeAll()
    }

    /// Sends an event to the namespace once it is connected.
    func emit(_ event: String, _ arguments: [LiveJSON]) async throws {
        try await waitUntilConnected()
        try await sendPacket(SocketIOPacket(
            type: .event, namespace: configuration.namespace, eventName: event, arguments: arguments
        ))
    }

    /// Sends an event that asks for an ack and returns the arguments of the
    /// ack. Throws `LiveError.noAnswer` when it does not come in time.
    func emitWithAck(_ event: String, _ arguments: [LiveJSON], timeout: Duration) async throws -> [LiveJSON] {
        try await waitUntilConnected()
        ackCounter += 1
        let id = ackCounter
        let packet = SocketIOPacket(
            type: .event, namespace: configuration.namespace, ackID: id, eventName: event, arguments: arguments
        )
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[LiveJSON], any Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                ackWaiters[id] = continuation
                ackTimers[id] = Task {
                    try? await Task.sleep(for: timeout)
                    if !Task.isCancelled { self.resolveAck(id, .failure(LiveError.noAnswer(event: event))) }
                }
                Task {
                    do {
                        try await self.sendPacket(packet)
                    } catch {
                        self.resolveAck(id, .failure(error))
                    }
                }
            }
        } onCancel: {
            Task { await self.resolveAck(id, .failure(CancellationError())) }
        }
    }

    private func resolveAck(_ id: Int, _ result: Result<[LiveJSON], any Error>) {
        ackTimers.removeValue(forKey: id)?.cancel()
        ackWaiters.removeValue(forKey: id)?.resume(with: result)
    }

    private static func seconds(_ duration: Duration) -> TimeInterval {
        let (seconds, attoseconds) = duration.components
        return TimeInterval(seconds) + TimeInterval(attoseconds) / 1e18
    }
}
