import Foundation

// MARK: - Engine.IO v4

/// The packet types of Engine.IO protocol 4.
enum EngineIOPacketType: UInt8, Sendable {
    case open = 0, close, ping, pong, message, upgrade, noop
}

/// One Engine.IO packet. Over WebSocket every frame is one packet; a binary
/// frame is a binary message.
struct EngineIOPacket: Sendable, Hashable {
    var type: EngineIOPacketType
    /// The text after the type digit.
    var text: String = ""
    /// The bytes of a binary message.
    var binary: Data?

    /// Reads a text frame. A leading "b" is a base64 binary message (the
    /// long-polling form).
    static func decode(_ frame: String) throws(LiveError) -> EngineIOPacket {
        guard let first = frame.utf8.first else { throw LiveError.protocolViolation("leeres Engine.IO-Paket") }
        if first == UInt8(ascii: "b") {
            guard let data = Data(base64Encoded: String(frame.dropFirst())) else {
                throw LiveError.protocolViolation("ungültiger Binärteil")
            }
            return EngineIOPacket(type: .message, binary: data)
        }
        guard first >= 0x30, let type = EngineIOPacketType(rawValue: first &- 0x30) else {
            throw LiveError.protocolViolation("unbekannter Engine.IO-Pakettyp")
        }
        return EngineIOPacket(type: type, text: String(frame.dropFirst()))
    }

    /// A binary frame.
    static func decode(binary data: Data) -> EngineIOPacket {
        EngineIOPacket(type: .message, binary: data)
    }

    /// The text frame of the packet ("b" + base64 for a binary message).
    var encoded: String {
        if let binary { return "b" + binary.base64EncodedString() }
        return String(type.rawValue) + text
    }
}

/// The OPEN packet of the server.
struct EngineIOHandshake: Sendable, Hashable {
    var sid: String
    var upgrades: [String]
    /// Milliseconds between the pings of the server.
    var pingInterval: Int
    /// Milliseconds the server waits for the pong.
    var pingTimeout: Int

    /// Reads and checks the JSON of an OPEN packet like the Go client: a sid
    /// is required, the heartbeat values must not be negative or overflow.
    init(json text: String) throws(LiveError) {
        do {
            let fields = try LiveJSON.parse(text).goObject()
            sid = try fields.field("sid")?.goString() ?? ""
            upgrades = try fields.field("upgrades")?.goStrings() ?? []
            pingInterval = try fields.field("pingInterval")?.goInt() ?? 0
            pingTimeout = try fields.field("pingTimeout")?.goInt() ?? 0
        } catch {
            throw LiveError.handshakeFailed(error.message)
        }
        guard !sid.isEmpty else { throw LiveError.handshakeFailed("keine sid") }
        let maxMilliseconds = Int.max / 1_000_000
        guard pingInterval >= 0, pingTimeout >= 0, pingInterval <= maxMilliseconds,
              pingTimeout <= maxMilliseconds - pingInterval else {
            throw LiveError.handshakeFailed("ungültiges Heartbeat-Intervall")
        }
    }

    /// The time after the last ping when the connection counts as dead;
    /// nil when the server did not ask for a heartbeat.
    var heartbeatTimeout: Duration? {
        let total = pingInterval + pingTimeout
        return total > 0 ? .milliseconds(total) : nil
    }
}

// MARK: - Socket.IO v5

/// The packet types of Socket.IO protocol 5.
enum SocketIOPacketType: UInt8, Sendable {
    case connect = 0, disconnect, event, ack, connectError, binaryEvent, binaryAck
}

/// One Socket.IO packet, encoded and decoded like the default parser of the
/// Go client (`github.com/maldikhan/go.socket.io`).
struct SocketIOPacket: Sendable, Hashable {
    var type: SocketIOPacketType
    var namespace: String = "/"
    var ackID: Int?
    /// The number of binary attachments that follow a binary packet.
    var attachments: Int?
    /// The name of an event; nil for acks.
    var eventName: String?
    /// The arguments of an event or ack (without the name).
    var arguments: [LiveJSON] = []
    /// The payload of a CONNECT packet; `null`, `""` and `{}` are left out.
    var payload: LiveJSON?
    /// The raw text of a CONNECT_ERROR packet.
    var errorMessage: String?

    /// The text of the packet (without the Engine.IO message prefix).
    var encoded: String {
        var out = String(type.rawValue)
        if let attachments { out += "\(attachments)-" }
        if namespace != "/" && !namespace.isEmpty { out += namespace + "," }
        if let ackID { out += String(ackID) }
        switch type {
        case .event, .ack, .binaryEvent, .binaryAck:
            var items: [LiveJSON] = []
            if let eventName, !eventName.isEmpty { items.append(.string(eventName)) }
            items.append(contentsOf: arguments)
            out += LiveJSON.array(items).encoded
        default:
            if let payload {
                let json = payload.encoded
                if json != "null" && json != "\"\"" && json != "{}" { out += json }
            }
        }
        return out
    }

    /// Reads a packet with the rules of the Go parser.
    static func decode(_ text: String) throws(LiveError) -> SocketIOPacket {
        let bytes = Array(text.utf8)
        guard let first = bytes.first else { throw LiveError.protocolViolation("leeres Socket.IO-Paket") }
        guard first >= 0x30, let type = SocketIOPacketType(rawValue: first &- 0x30) else {
            throw LiveError.protocolViolation("unbekannter Socket.IO-Pakettyp")
        }
        var packet = SocketIOPacket(type: type)
        let needsBody: Bool = switch type {
        case .event, .ack, .connectError, .binaryEvent, .binaryAck: true
        case .connect, .disconnect: false
        }
        var rest = bytes[1...]
        func done() throws(LiveError) -> SocketIOPacket {
            if needsBody { throw LiveError.protocolViolation("Socket.IO-Paket ohne Inhalt") }
            return packet
        }
        if rest.isEmpty { return try done() }

        if type == .binaryEvent || type == .binaryAck {
            var end = rest.startIndex
            while end < rest.endIndex, (0x30...0x39).contains(rest[end]) {
                end += 1
                if end - rest.startIndex > 18 { throw LiveError.protocolViolation("falsche Anzahl der Anhänge") }
            }
            guard end > rest.startIndex, end < rest.endIndex, rest[end] == UInt8(ascii: "-"),
                  let count = Int(String(decoding: rest[rest.startIndex..<end], as: UTF8.self)) else {
                throw LiveError.protocolViolation("Anzahl der Anhänge fehlt")
            }
            packet.attachments = count
            rest = rest[(end + 1)...]
            if rest.isEmpty { throw LiveError.protocolViolation("Socket.IO-Paket ohne Inhalt") }
        }

        if rest.first == UInt8(ascii: "/") {
            for position in rest.indices {
                let byte = rest[position]
                if byte == UInt8(ascii: ",") {
                    packet.namespace = String(decoding: rest[rest.startIndex..<position], as: UTF8.self)
                    rest = rest[(position + 1)...]
                    break
                }
                if byte == UInt8(ascii: "[") || byte == UInt8(ascii: "{") { break }
            }
        }
        if rest.isEmpty { return try done() }

        var ackEnd = rest.startIndex
        while ackEnd < rest.endIndex, (0x30...0x39).contains(rest[ackEnd]) {
            ackEnd += 1
            if ackEnd - rest.startIndex > 18 { throw LiveError.protocolViolation("falsche Ack-Nummer") }
        }
        if ackEnd > rest.startIndex {
            guard let ackID = Int(String(decoding: rest[rest.startIndex..<ackEnd], as: UTF8.self)) else {
                throw LiveError.protocolViolation("falsche Ack-Nummer")
            }
            packet.ackID = ackID
            rest = rest[ackEnd...]
        }
        if rest.isEmpty { return try done() }

        switch type {
        case .event, .ack, .binaryEvent, .binaryAck:
            let isAck = type == .ack || type == .binaryAck
            let parsed: LiveJSON
            do {
                parsed = try LiveJSON.parse(String(decoding: rest, as: UTF8.self))
            } catch {
                throw LiveError.protocolViolation("Ereignis nicht lesbar: \(error.message)")
            }
            guard case .array(let items) = parsed else {
                throw LiveError.protocolViolation("Ereignis ist keine Liste")
            }
            if isAck {
                packet.arguments = items
            } else {
                guard case .string(let name)? = items.first else {
                    throw LiveError.protocolViolation("Ereignisname ist kein Text")
                }
                packet.eventName = name
                packet.arguments = Array(items.dropFirst())
            }
        case .connectError:
            packet.errorMessage = String(decoding: rest, as: UTF8.self)
        case .connect, .disconnect:
            break
        }
        return packet
    }

    /// Replaces the `{"_placeholder":true,"num":N}` markers of a binary
    /// packet with its attachments. A Go `json.RawMessage` handler sees an
    /// attachment as a base64 JSON string, so that is what replaces it.
    func reconstructed(with attachments: [Data]) throws(LiveError) -> SocketIOPacket {
        guard attachments.count == (self.attachments ?? 0) else {
            throw LiveError.protocolViolation("Anzahl der Anhänge stimmt nicht")
        }
        var packet = self
        var replaced: [LiveJSON] = []
        for argument in arguments {
            replaced.append(try Self.replacePlaceholders(argument, attachments))
        }
        packet.arguments = replaced
        packet.attachments = nil
        packet.type = type == .binaryAck ? .ack : (type == .binaryEvent ? .event : type)
        return packet
    }

    private static func replacePlaceholders(_ value: LiveJSON, _ attachments: [Data]) throws(LiveError) -> LiveJSON {
        switch value {
        case .object(let fields):
            if case .bool(true)? = fields["_placeholder"] {
                guard let number = fields["num"] else { throw LiveError.protocolViolation("Platzhalter ohne num") }
                guard case .number(let literal) = number, let index = Double(literal),
                      index == index.rounded(.towardZero), index >= 0, index < Double(attachments.count) else {
                    throw LiveError.protocolViolation("ungültiger Platzhalter")
                }
                return .string(attachments[Int(index)].base64EncodedString())
            }
            var out: [String: LiveJSON] = [:]
            for (key, item) in fields { out[key] = try replacePlaceholders(item, attachments) }
            return .object(out)
        case .array(let items):
            var out: [LiveJSON] = []
            for item in items { out.append(try replacePlaceholders(item, attachments)) }
            return .array(out)
        default:
            return value
        }
    }
}
