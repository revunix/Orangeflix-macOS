import Darwin
import Foundation
import Observation
import os

/// Connection state of Discord Rich Presence for Settings diagnostics.
enum DiscordConnectionStatus: Sendable, Equatable {
    case disabled
    case idle
    case waitingForDiscord
    case connected
    case rejected(String)

    var label: String {
        switch self {
        case .disabled: "Ausgeschaltet"
        case .idle: "Bereit (aktiv bei Wiedergabe)"
        case .waitingForDiscord: "Discord Desktop nicht geöffnet"
        case .connected: "Mit Discord verbunden"
        case .rejected(let reason): "Abgelehnt: \(reason)"
        }
    }

    var isHealthy: Bool {
        switch self {
        case .connected, .idle: true
        default: false
        }
    }
}

/// Coordinates playback snapshots and publishes Discord Rich Presence state on
/// the main actor while performing socket I/O on a background actor.
@MainActor @Observable final class DiscordPresenceService {
    private(set) var status: DiscordConnectionStatus = .idle

    @ObservationIgnored private let worker = DiscordIPCWorker()
    @ObservationIgnored private var lastSent: (snapshot: DiscordPresenceLogic.Snapshot, sentAt: Date)?

    func refreshIdleState(enabled: Bool) {
        if !enabled {
            status = .disabled
            clear()
            return
        }
        probe(enabled: true)
    }

    /// Checks whether Discord Desktop's IPC socket is reachable right now so
    /// Settings immediately reflects live connectivity.
    func probe(enabled: Bool) {
        guard enabled else {
            status = .disabled
            return
        }
        let clientID = DiscordPresenceLogic.clientID
        Task { [worker] in
            let nextStatus = await worker.probeConnection(clientID: clientID)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.status = nextStatus
            }
        }
    }

    func update(
        snapshot: DiscordPresenceLogic.Snapshot?,
        liveStartedAt: Date?,
        enabled: Bool,
        force: Bool = false
    ) {
        guard enabled else {
            status = .disabled
            if lastSent != nil { clear() }
            return
        }
        guard let snapshot else {
            clear()
            if case .connected = status { status = .idle }
            return
        }

        let now = Date()
        if !force,
           !DiscordPresenceLogic.shouldSendUpdate(previous: lastSent, current: snapshot, now: now) {
            return
        }

        lastSent = (snapshot, now)
        let activity = DiscordPresenceLogic.activity(from: snapshot, now: now, liveStartedAt: liveStartedAt)
        let pid = ProcessInfo.processInfo.processIdentifier
        let clientID = DiscordPresenceLogic.clientID

        Task { [worker] in
            let nextStatus = await worker.sendActivity(activity, clientID: clientID, pid: pid)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.status = nextStatus
                if nextStatus != .connected {
                    self.lastSent = nil
                }
            }
        }
    }

    func clear() {
        lastSent = nil
        let pid = ProcessInfo.processInfo.processIdentifier
        Task { [worker] in
            await worker.clearActivity(pid: pid)
        }
    }
}

// MARK: - Background IPC Worker

private actor DiscordIPCWorker {
    private static let logger = Logger(subsystem: "com.revunix.orangeflix", category: "discord")

    private var socketFD: Int32 = -1
    private var activeClientID: String?

    func sendActivity(
        _ activity: DiscordPresenceLogic.Activity,
        clientID: String,
        pid: Int32
    ) -> DiscordConnectionStatus {
        if activeClientID != clientID {
            disconnect()
        }
        if socketFD < 0 {
            let result = connect(clientID: clientID)
            if result != .connected {
                return result
            }
        }
        guard let packet = try? DiscordIPCFrame.setActivity(activity, pid: pid) else {
            return .waitingForDiscord
        }
        if !writeAll(packet) || !drainReply() {
            // Reconnect once if Discord restarted since the last activity update.
            disconnect()
            let retry = connect(clientID: clientID)
            guard retry == .connected, writeAll(packet), drainReply() else {
                return retry == .connected ? .waitingForDiscord : retry
            }
        }
        return .connected
    }

    func clearActivity(pid: Int32) {
        guard socketFD >= 0 else { return }
        if let packet = try? DiscordIPCFrame.setActivity(nil, pid: pid) {
            _ = writeAll(packet)
            _ = drainReply()
        }
        disconnect()
    }

    func probeConnection(clientID: String) -> DiscordConnectionStatus {
        if socketFD >= 0, activeClientID == clientID {
            return .connected
        }
        return connect(clientID: clientID)
    }

    // MARK: Socket lifecycle

    private func connect(clientID: String) -> DiscordConnectionStatus {
        disconnect()
        var lastRejection: String?
        let candidates = Self.candidateSocketPaths()

        for path in candidates {
            guard FileManager.default.fileExists(atPath: path) else { continue }
            guard let fd = Self.openUnixSocket(path: path) else { continue }
            socketFD = fd
            switch performHandshake(clientID: clientID) {
            case .connected:
                activeClientID = clientID
                Self.logger.debug("Discord RPC verbunden über \(path, privacy: .public)")
                return .connected
            case .rejected(let message):
                lastRejection = message
                Self.logger.debug("Discord RPC abgelehnt: \(message, privacy: .public)")
                disconnect()
                return .rejected(message)
            default:
                disconnect()
            }
        }

        if let lastRejection {
            return .rejected(lastRejection)
        }
        return .waitingForDiscord
    }

    private func disconnect() {
        if socketFD >= 0 {
            Darwin.close(socketFD)
            socketFD = -1
        }
        activeClientID = nil
    }

    private func performHandshake(clientID: String) -> DiscordConnectionStatus {
        guard let packet = try? DiscordIPCFrame.handshake(clientID: clientID),
              writeAll(packet),
              let frame = readFrame() else {
            return .waitingForDiscord
        }
        switch frame.opcode {
        case .close:
            let reason = Self.extractMessage(from: frame.payload) ?? "Verbindung geschlossen"
            return .rejected(reason)
        case .frame:
            if let evt = Self.extractString("evt", from: frame.payload), evt == "ERROR" {
                let reason = Self.extractMessage(from: frame.payload) ?? "Ungültige Application-ID"
                return .rejected(reason)
            }
            return .connected
        default:
            return .connected
        }
    }

    private func drainReply() -> Bool {
        guard let frame = readFrame() else { return false }
        switch frame.opcode {
        case .ping:
            let pong = DiscordIPCFrame(opcode: .pong, payload: frame.payload).encoded()
            return writeAll(pong)
        case .close:
            return false
        case .frame:
            if let evt = Self.extractString("evt", from: frame.payload), evt == "ERROR" {
                Self.logger.debug("Discord RPC Fehler: \(Self.extractMessage(from: frame.payload) ?? "unbekannt", privacy: .public)")
            }
            return true
        default:
            return true
        }
    }

    // MARK: Low-level POSIX I/O

    private func writeAll(_ data: Data) -> Bool {
        guard socketFD >= 0 else { return false }
        return data.withUnsafeBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return true }
            var sent = 0
            while sent < rawBuffer.count {
                let n = Darwin.send(socketFD, base.advanced(by: sent), rawBuffer.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    private func readFrame() -> DiscordIPCFrame? {
        guard let header = readExact(count: 8),
              let decoded = DiscordIPCFrame.decodeHeader(header) else {
            return nil
        }
        guard decoded.length > 0 else {
            return DiscordIPCFrame(opcode: decoded.opcode, payload: Data())
        }
        guard let payload = readExact(count: decoded.length) else {
            return nil
        }
        return DiscordIPCFrame(opcode: decoded.opcode, payload: payload)
    }

    private func readExact(count: Int) -> Data? {
        guard socketFD >= 0 else { return nil }
        var buffer = Data(count: count)
        let ok = buffer.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return false }
            var received = 0
            while received < count {
                let n = Darwin.recv(socketFD, base.advanced(by: received), count - received, 0)
                if n <= 0 { return false }
                received += n
            }
            return true
        }
        return ok ? buffer : nil
    }

    private static func openUnixSocket(path: String) -> Int32? {
        let utf8 = Array(path.utf8CString)
        var addr = sockaddr_un()
        let maxPathLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard utf8.count <= maxPathLen else { return nil }

        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }

        var noSigPipe: Int32 = 1
        _ = setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))

        var timeout = timeval(tv_sec: 1, tv_usec: 500_000)
        _ = setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        _ = setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))

        addr.sun_family = sa_family_t(AF_UNIX)
        withUnsafeMutableBytes(of: &addr.sun_path) { dest in
            utf8.withUnsafeBytes { src in
                if let dstBase = dest.baseAddress, let srcBase = src.baseAddress {
                    memcpy(dstBase, srcBase, src.count)
                }
            }
        }

        let connected = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            Darwin.close(fd)
            return nil
        }
        return fd
    }

    /// Discovers Discord's IPC socket directories. Inside App Sandbox both
    /// `TMPDIR` and `_CS_DARWIN_USER_TEMP_DIR` are redirected into the app's
    /// container, whereas Discord Desktop places `discord-ipc-0` in the user's
    /// real `/private/var/folders/<bucket>/<dir>/T/` directory.
    private static func candidateSocketPaths() -> [String] {
        var directories: [String] = []
        directories.append(contentsOf: realVarFoldersTempDirectories())
        if let darwinTemp = darwinUserTempDirectory() {
            directories.append(darwinTemp)
            if darwinTemp.hasPrefix("/var/") {
                directories.append("/private" + darwinTemp)
            }
        }
        if let envTmp = ProcessInfo.processInfo.environment["TMPDIR"], !envTmp.isEmpty {
            directories.append(envTmp)
        }
        directories.append("/private/tmp")
        directories.append("/tmp")

        var seen = Set<String>()
        var paths: [String] = []
        for raw in directories {
            let trimmed = raw.hasSuffix("/") ? String(raw.dropLast()) : raw
            guard !trimmed.isEmpty, seen.insert(trimmed).inserted else { continue }
            for slot in 0..<10 {
                paths.append("\(trimmed)/discord-ipc-\(slot)")
            }
        }
        return paths
    }

    /// Finds `/private/var/folders/<bucket>/<user-dir>/T` owned by `getuid()`.
    private static func realVarFoldersTempDirectories() -> [String] {
        let root = "/private/var/folders"
        let uid = UInt(Darwin.getuid())
        let fm = FileManager.default
        guard let buckets = try? fm.contentsOfDirectory(atPath: root) else {
            return []
        }
        var found: [String] = []
        for bucket in buckets where !bucket.hasPrefix(".") {
            let bucketPath = "\(root)/\(bucket)"
            guard let entries = try? fm.contentsOfDirectory(atPath: bucketPath) else {
                continue
            }
            for entry in entries where !entry.hasPrefix(".") {
                let candidate = "\(bucketPath)/\(entry)/T"
                if let attrs = try? fm.attributesOfItem(atPath: candidate),
                   let owner = attrs[.ownerAccountID] as? NSNumber,
                   owner.uintValue == uid {
                    found.append(candidate)
                }
            }
        }
        return found
    }

    private static func darwinUserTempDirectory() -> String? {
        var buf = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, &buf, buf.count)
        guard length > 0 else { return nil }
        return String(cString: buf)
    }

    private static func extractString(_ key: String, from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json[key] as? String
    }

    private static func extractMessage(from data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        if let message = json["message"] as? String, !message.isEmpty { return message }
        if let nested = json["data"] as? [String: Any],
           let message = nested["message"] as? String, !message.isEmpty {
            return message
        }
        return nil
    }
}
