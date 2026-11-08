import Foundation

/// One line of the live chat.
struct ChatMessage: Sendable, Hashable {
    var id: String = ""
    var from: String = ""
    /// Plain text; the HTML of the web chat is already cleaned.
    var text: String = ""
    /// The addressee ("mainroom" for the public chat).
    var to: String = ""
    /// The id of the message this one answers; empty for none.
    var replyTo: String = ""
    /// When the message was written; nil when the server sent no time.
    var time: Date?
    /// Written by the team of the show.
    var isAdmin: Bool = false
    /// Written by the logged-in account.
    var isSelf: Bool = false
}

/// The reactions of one message at a cursor of the server.
struct ChatReactionState: Sendable, Hashable {
    var messageID: String
    var cursor: String
    /// Count per reaction key; only counts above zero.
    var counts: [String: Int]
    /// The reactions of the account.
    var mine: [String]
}

/// One change of a reaction, sent by the server to all.
struct ChatReactionUpdate: Sendable, Hashable {
    var messageID: String
    var cursor: String
    var emoji: String
    /// The new number of the reaction.
    var count: Int
    var active: Bool
    /// The account made the change.
    var isSelf: Bool
}

/// A voting of the live show.
struct ChatPoll: Sendable, Hashable {
    /// What is asked.
    var question: String
    /// The choices in the order of the server.
    var answers: [String]
    /// The votes per answer; nil while they are hidden.
    var results: [Int]?
    /// Names the voting; only a secret one has one.
    var pollID: String = ""
    /// The votes stay hidden until the voting ends.
    var secret: Bool = false
    /// The votes may be shown.
    var resultsVisible: Bool = false
    /// The number of people that took part.
    var submissions: Int = 0
    /// The voting is over.
    var closed: Bool = false

    /// The number of the votes that were counted.
    var voteCount: Int { results?.reduce(0, +) ?? 0 }

    /// The answer with the most votes (the first one on a tie) and its
    /// votes; index -1 when no answer has a vote.
    var leading: (index: Int, votes: Int) {
        var best = -1
        var votes = 0
        for (index, count) in (results ?? []).enumerated() where count > votes {
            best = index
            votes = count
        }
        return (best, votes)
    }
}

/// One event of a chat session.
enum ChatEvent: Sendable, Hashable {
    /// A chat message (live, from the history, or the pinned one).
    case message(ChatMessage)
    /// A connection state in German ("Chat verbunden", "12 im Chat", …).
    case status(String)
    /// A chat failure.
    case error(LiveError)
    /// The reactions of the history; `emojis` names reactions the client
    /// does not know yet (key → emoji).
    case reactions([ChatReactionState], emojis: [String: String])
    /// One change of a reaction.
    case reactionChanged(ChatReactionUpdate)
    /// A new voting or its changed votes or its end.
    case poll(ChatPoll)
    /// The voting is over and gone.
    case pollRemoved
    /// The server says this client already voted in the running voting
    /// (`switchToResultView`); it does not say for which answer.
    case pollVoted
}

/// The reactions the web chat knows.
enum ChatReactions {
    /// The room of the public chat.
    static let room = "mainroom"

    /// The reactions the web chat offers, in its order. The server can name
    /// more in its answers.
    static let keys = ["thumbsup", "heart", "laugh", "celebrate"]

    /// The emoji per reaction key. The heart carries the variation selector
    /// so it is drawn as emoji and not as text glyph.
    static let emojis: [String: String] = [
        "thumbsup": "👍",
        "heart": "❤️",
        "laugh": "😂",
        "celebrate": "🎉",
        "surprised": "😮",
    ]

    /// The German names of the reactions.
    static let names: [String: String] = [
        "thumbsup": "Daumen hoch",
        "heart": "Herz",
        "laugh": "Lachen",
        "celebrate": "Feiern",
        "surprised": "Überrascht",
    ]

    /// Orders two cursors of the server ("1730000000000-3"): the time first,
    /// then the sequence. -1 means `a` is older.
    static func compareCursor(_ a: String, _ b: String) -> Int {
        let (aTime, aSequence) = splitCursor(a)
        let (bTime, bSequence) = splitCursor(b)
        if aTime != bTime { return aTime < bTime ? -1 : 1 }
        if aSequence != bSequence { return aSequence < bSequence ? -1 : 1 }
        return 0
    }

    private static func splitCursor(_ value: String) -> (Int64, Int64) {
        guard let dash = value.firstIndex(of: "-") else { return (Int64(value) ?? 0, 0) }
        return (Int64(value[..<dash]) ?? 0, Int64(value[value.index(after: dash)...]) ?? 0)
    }
}

/// The claims of a chat token that the session needs.
struct ChatTokenClaims: Sendable, Hashable {
    /// The chat name of the account; marks its own messages and reactions.
    var username: String = ""
    var admin: Bool = false

    /// Reads the claims of the decoded token (`jwtd` of the API answer).
    /// Fields of the wrong type are left empty, like Go's best-effort read.
    init(json: Data) {
        guard let value = try? LiveJSON.parse(json), case .object(let fields) = value else { return }
        username = (try? fields.field("username")?.goString()) ?? ""
        admin = (try? fields.field("admin")?.goBool()) ?? false
    }

    /// Reads the claims from the payload part of a JWT.
    init(jwt: String) {
        let parts = jwt.split(separator: ".", omittingEmptySubsequences: false)
        var base64 = parts.count >= 2 ? String(parts[1]) : ""
        base64 = base64.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        self.init(json: Data(base64Encoded: base64) ?? Data())
    }
}

/// The failures of the live chat.
enum LiveError: LocalizedError, Sendable, Hashable {
    /// The API gave no chat token.
    case missingToken
    case emptyMessage
    /// More than 500 characters.
    case messageTooLong
    case notConnected
    case closed
    /// The Engine.IO handshake did not finish within the connect timeout.
    case connectTimedOut
    /// The namespace was not confirmed in time after the connect.
    case loginTimedOut
    /// The server refused the namespace (CONNECT_ERROR).
    case connectRefused(String)
    case handshakeFailed(String)
    case protocolViolation(String)
    /// The WebSocket failed.
    case transport(String)
    /// All reconnect attempts failed; the session is over.
    case connectionLost
    /// The server did not answer a request in time.
    case noAnswer(event: String)
    /// The server did not count the vote.
    case voteRejected
    /// The server kept the old state; read the state of the message again.
    case reactionUnchanged
    /// A refusal of a reaction, with the code of the server.
    case reactionRefused(code: String)
    /// The answer of metadataState was refused or unreadable.
    case invalidReactionState

    var errorDescription: String? {
        switch self {
        case .missingToken: "Kein Chat-Token erhalten."
        case .emptyMessage: "Die Nachricht ist leer."
        case .messageTooLong: "Die Nachricht ist zu lang (höchstens 500 Zeichen)."
        case .notConnected: "Der Chat ist nicht verbunden."
        case .closed: "Der Chat ist geschlossen."
        case .connectTimedOut: "Die Verbindung zum Chat hat zu lange gedauert."
        case .loginTimedOut: "Die Anmeldung am Chat hat zu lange gedauert."
        case .connectRefused(let reason): "Der Chat hat die Verbindung abgelehnt: \(reason)"
        case .handshakeFailed(let reason): "Der Chat-Handshake ist fehlgeschlagen: \(reason)"
        case .protocolViolation(let reason): "Ungültige Antwort des Chats: \(reason)"
        case .transport(let reason): "Verbindungsfehler im Chat: \(reason)"
        case .connectionLost: "Die Verbindung zum Chat ist abgebrochen."
        case .noAnswer(let event): event == "vote"
            ? "Der Chat hat auf die Stimme nicht geantwortet."
            : "Der Chat hat nicht geantwortet (\(event))."
        case .voteRejected: "Die Stimme wurde nicht gezählt."
        case .reactionUnchanged: "Die Reaktion wurde nicht geändert."
        case .reactionRefused(let code):
            switch code {
            case "unauthenticated": "Zum Reagieren bitte anmelden."
            case "rate_limited": "Zu viele Reaktionen. Bitte kurz warten."
            case "not_found": "Nachricht nicht mehr verfügbar."
            case "forbidden": "Keine Berechtigung für diesen Raum."
            case "invalid_payload": "Reaktion konnte nicht gesendet werden."
            default: "Reaktion fehlgeschlagen."
            }
        case .invalidReactionState: "Ungültiger Stand der Reaktionen."
        }
    }
}
