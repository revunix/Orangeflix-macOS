import Foundation

/// The readers of the chat payloads. They follow the Go decoding rules: a
/// field of the wrong type makes the whole payload unreadable, `null` is the
/// zero value.
enum ChatWire {
    // MARK: Messages

    /// A chat message and its addressee; nil when the payload is unreadable.
    static func message(_ raw: LiveJSON, username: String) -> ChatMessage? {
        do {
            let fields = try raw.goObject()
            let from = try fields.field("from")?.goString() ?? ""
            return ChatMessage(
                id: try fields.field("id")?.goString() ?? "",
                from: from,
                text: LiveHTML.cleanText(try fields.field("text")?.goString() ?? ""),
                to: try fields.field("to")?.goString() ?? "",
                replyTo: try fields.field("replyTo")?.goString() ?? "",
                time: parseTime(fields.field("time")),
                isAdmin: try fields.field("h")?.goBool() ?? false,
                isSelf: from == username
            )
        } catch {
            return nil
        }
    }

    /// The messages of the history; nil when one of them is unreadable.
    static func history(_ raw: LiveJSON, username: String) -> [ChatMessage]? {
        let items: [LiveJSON]?
        do { items = try raw.goArray() } catch { return nil }
        var messages: [ChatMessage] = []
        for item in items ?? [] {
            guard let message = message(item, username: username) else { return nil }
            messages.append(message)
        }
        return messages
    }

    /// Accepts the RFC 3339 strings of the history and the numeric
    /// timestamps (seconds or milliseconds) of some live events.
    static func parseTime(_ raw: LiveJSON?) -> Date? {
        switch raw {
        case .string(let text)?:
            return parseRFC3339(text)
        case .number(let literal)?:
            guard var number = Int64(literal) else { return nil }
            if number > 1_000_000_000_000 { number /= 1000 }
            return Date(timeIntervalSince1970: TimeInterval(number))
        default:
            return nil
        }
    }

    /// Go's `time.Parse(time.RFC3339Nano, …)`.
    static func parseRFC3339(_ text: String) -> Date? {
        let bytes = Array(text.utf8)
        var index = 0
        func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for _ in 0..<count {
                let byte = bytes[index]
                guard (0x30...0x39).contains(byte) else { return nil }
                value = value * 10 + Int(byte - 0x30)
                index += 1
            }
            return value
        }
        func expect(_ character: Character) -> Bool {
            guard index < bytes.count, bytes[index] == character.asciiValue else { return false }
            index += 1
            return true
        }
        guard let year = digits(4), expect("-"), let month = digits(2), expect("-"), let day = digits(2),
              expect("T"), let hour = digits(2), expect(":"), let minute = digits(2), expect(":"),
              let second = digits(2) else { return nil }
        var fraction = 0.0
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") || bytes[index] == UInt8(ascii: ",") {
            index += 1
            let start = index
            var scale = 0.1
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                fraction += Double(bytes[index] - 0x30) * scale
                scale /= 10
                index += 1
            }
            guard index > start, index - start <= 9 else { return nil }
        }
        var offset = 0
        if expect("Z") {
            offset = 0
        } else if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
            let sign = bytes[index] == UInt8(ascii: "-") ? -1 : 1
            index += 1
            guard let offsetHour = digits(2), expect(":"), let offsetMinute = digits(2),
                  offsetHour < 24, offsetMinute < 60 else { return nil }
            offset = sign * (offsetHour * 3600 + offsetMinute * 60)
        } else {
            return nil
        }
        guard index == bytes.count, (1...12).contains(month), hour < 24, minute < 60, second < 60 else { return nil }
        let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
        let monthDays = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
        guard day >= 1, day <= monthDays[month - 1] else { return nil }
        // Days from the civil date (Howard Hinnant's algorithm).
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400
        let shiftedMonth = month > 2 ? month - 3 : month + 9
        let dayOfYear = (153 * shiftedMonth + 2) / 5 + day - 1
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear
        let days = era * 146_097 + dayOfEra - 719_468
        let seconds = days * 86_400 + hour * 3600 + minute * 60 + second - offset
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    /// The pinned message. The server sends it as a message object or as a
    /// plain text; an empty answer means nothing is pinned.
    static func pinnedText(_ raw: LiveJSON) -> String {
        switch raw {
        case .null: return ""
        case .string(let text): return LiveHTML.cleanText(text)
        case .object(let fields):
            do {
                let candidates = [
                    try fields.field("text")?.goString(), try fields.field("txt")?.goString(),
                    try fields.field("msg")?.goString(), try fields.field("message")?.goString(),
                ]
                for case let candidate? in candidates where !candidate.isEmpty {
                    return LiveHTML.cleanText(candidate)
                }
            } catch {
                return ""
            }
            return ""
        case .array(let items):
            return items.first.map(pinnedText) ?? ""
        default:
            return ""
        }
    }

    /// The number of the people in the chat; nil when unreadable.
    static func userCount(_ raw: LiveJSON) -> Int? {
        do { return try raw.goStrings()?.count ?? 0 } catch { return nil }
    }

    // MARK: Polls

    /// A voting of the server. A voting without a question or without
    /// answers is not one.
    static func poll(_ raw: LiveJSON) -> ChatPoll? {
        do {
            let fields = try raw.goObject()
            let question = try fields.field("question")?.goString() ?? ""
            let pollID = try fields.field("pollId")?.goString() ?? ""
            let secretPoll = try fields.field("secretPoll")?.goBool() ?? false
            let resultsVisible = try fields.field("resultsVisible")?.goOptionalBool()
            let closed = try fields.field("closed")?.goBool() ?? false
            guard !question.isEmpty, let answersRaw = fields.field("answers"),
                  let answers = try answersRaw.goStrings(), !answers.isEmpty else { return nil }
            let secret = secretPoll && !pollID.isEmpty
            let visible = !secret || resultsVisible == true
            var poll = ChatPoll(
                question: LiveHTML.cleanText(question),
                answers: answers.map(LiveHTML.cleanText),
                pollID: pollID,
                secret: secret,
                resultsVisible: visible,
                submissions: count(fields.field("submissions")),
                closed: closed
            )
            if visible {
                // Wrong values in the results count as none: the web chat
                // shows zeros then.
                poll.results = counts(fields.field("results"), answers: answers.count)
                    ?? Array(repeating: 0, count: answers.count)
            }
            return poll
        } catch {
            return nil
        }
    }

    /// The new votes of a voting.
    static func pollResults(_ raw: LiveJSON, answers: Int) -> (pollID: String, results: [Int], submissions: Int)? {
        guard let fields = try? raw.goObject(),
              let pollID = try? fields.field("pollId")?.goString() ?? "",
              let results = counts(fields.field("results"), answers: answers) else { return nil }
        return (pollID, results, count(fields.field("submissions")))
    }

    /// The change of the visibility of the votes.
    static func pollVisibility(_ raw: LiveJSON, answers: Int)
        -> (pollID: String, visible: Bool, results: [Int]?, submissions: Int)? {
        guard let fields = try? raw.goObject(),
              let pollID = try? fields.field("pollId")?.goString() ?? "",
              let visible = try? fields.field("resultsVisible")?.goBool() ?? false,
              !pollID.isEmpty else { return nil }
        let results = counts(fields.field("results"), answers: answers)
        if visible && results == nil { return nil }
        return (pollID, visible, results, count(fields.field("submissions")))
    }

    /// The server ended the voting.
    static func pollClosed(_ raw: LiveJSON) -> Bool {
        guard let fields = try? raw.goObject() else { return false }
        return (try? fields.field("closed")?.goBool()) ?? false
    }

    /// The votes of the answers: a list of the same length with whole
    /// numbers that are not negative.
    static func counts(_ raw: LiveJSON?, answers: Int) -> [Int]? {
        // `null` reads as an empty list, which never matches the answers.
        guard let raw, let list = try? raw.goArray() else { return nil }
        guard list.count == answers else { return nil }
        var counts: [Int] = []
        counts.reserveCapacity(list.count)
        for item in list {
            guard let value = try? item.goDouble(), value >= 0, value == value.rounded(.towardZero),
                  value < 9.2e18 else { return nil }
            counts.append(Int(value))
        }
        return counts
    }

    /// The number of the people that took part.
    static func count(_ raw: LiveJSON?) -> Int {
        guard let raw, let number = try? raw.goDouble(), number >= 0 else { return 0 }
        return number < 9.2e18 ? Int(number) : Int.max
    }

    /// The answer of the server to a vote.
    static func voteAccepted(_ raw: LiveJSON) -> Bool {
        switch raw {
        case .null: return false
        case .bool(let value): return value
        case .object(let fields):
            do {
                let accepted = try fields.field("accepted")?.goOptionalBool()
                let ok = try fields.field("ok")?.goOptionalBool()
                return accepted ?? ok ?? false
            } catch {
                return false
            }
        default:
            return false
        }
    }

    // MARK: Reactions

    /// The answer to a reaction; throws the refusal of the server.
    static func checkReactionAnswer(_ raw: LiveJSON) throws(LiveError) {
        let ok: Bool, code: String, discarded: Bool, changed: Bool?
        do {
            let fields = try raw.goObject()
            ok = try fields.field("ok")?.goBool() ?? false
            code = try fields.field("error")?.goString() ?? ""
            discarded = try fields.field("discarded")?.goBool() ?? false
            changed = try fields.field("changed")?.goOptionalBool()
        } catch {
            throw LiveError.reactionRefused(code: "")
        }
        guard ok else { throw LiveError.reactionRefused(code: code) }
        if discarded || changed == false { throw LiveError.reactionUnchanged }
    }

    /// The answer of metadataState: the states and the emojis of the
    /// reactions the server names.
    static func metadataState(_ raw: LiveJSON) throws(LiveError) -> (states: [ChatReactionState], emojis: [String: String]) {
        do {
            let fields = try raw.goObject()
            let ok = try fields.field("ok")?.goBool() ?? false
            let emojiMap = try fields.field("emojis")?.goStringMap() ?? [:]
            var entries: [(String, [String: Double], [String])] = []
            for entry in try fields.field("reactions")?.goArray() ?? [] {
                let entryFields = try entry.goObject()
                entries.append((
                    try entryFields.field("messageId")?.goString() ?? "",
                    try entryFields.field("counts")?.goDoubleMap() ?? [:],
                    try entryFields.field("mine")?.goStrings() ?? []
                ))
            }
            guard ok else { throw LiveError.invalidReactionState }
            let cursor = cursorText(fields.field("cursor"))
            var states: [ChatReactionState] = []
            for (messageID, rawCounts, mine) in entries where !messageID.isEmpty {
                var counts: [String: Int] = [:]
                for (key, value) in rawCounts {
                    let count = value < 9.2e18 && value > -9.2e18 ? Int(value) : 0
                    if count > 0 { counts[key] = count }
                }
                states.append(ChatReactionState(messageID: messageID, cursor: cursor, counts: counts, mine: mine))
            }
            var emojis: [String: String] = [:]
            for (key, emoji) in emojiMap {
                let clean = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
                if !clean.isEmpty { emojis[key] = clean }
            }
            return (states, emojis)
        } catch let error as LiveError {
            throw error
        } catch {
            throw LiveError.invalidReactionState
        }
    }

    /// One change of a reaction that the server sends to all.
    static func metadataEvent(_ raw: LiveJSON, username: String) -> ChatReactionUpdate? {
        do {
            let fields = try raw.goObject()
            let version = try fields.field("version")?.goInt() ?? 0
            let type = try fields.field("type")?.goString() ?? ""
            let id = try fields.field("id")?.goString() ?? ""
            let messageID = try fields.field("messageId")?.goString() ?? ""
            let room = try fields.field("room")?.goString() ?? ""
            let actor = try fields.field("actor")?.goString() ?? ""
            guard let data = try fields.field("data")?.goOptionalObject() else { return nil }
            let emoji = try data.field("emoji")?.goString() ?? ""
            let count = try data.field("count")?.goOptionalDouble()
            let active = try data.field("active")?.goBool() ?? false
            guard version == 1, type == "reaction.set", !id.isEmpty, !messageID.isEmpty,
                  room == ChatReactions.room, !emoji.isEmpty, let count else { return nil }
            let whole = count < 9.2e18 && count > -9.2e18 ? Int(count) : (count > 0 ? Int.max : 0)
            return ChatReactionUpdate(
                messageID: messageID, cursor: id, emoji: emoji, count: max(0, whole),
                active: active, isSelf: !username.isEmpty && actor == username, actor: actor
            )
        } catch {
            return nil
        }
    }

    /// A cursor that comes as a text or as a number.
    static func cursorText(_ raw: LiveJSON?) -> String {
        switch raw {
        case .string(let text)?: text
        case .number(let literal)?: literal
        default: ""
        }
    }
}
