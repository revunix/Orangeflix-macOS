import Foundation

/// One line of the chat of the live show (Go `chatLine`).
struct LiveChatLine: Hashable, Sendable {
    /// The id of the message on the server; empty for a pending one.
    var id: String = ""
    /// The name of the sender.
    var from: String = ""
    /// The text of the message.
    var text: String = ""
    /// The moment the message was written; nil when the server sent none.
    var time: Date?
    /// Written by the account.
    var isSelf = false
    /// Written by the team of the show.
    var isAdmin = false
    /// Written to the studio; only the team reads it.
    var isStudio = false
    /// Waiting for the echo of the server.
    var isPending = false
    /// A note of the program, not a message.
    var isSystem = false
    /// A line of the chat transcript of a replay; it cannot be answered.
    var isReplay = false
    /// The id of the message this one answers.
    var replyTo: String = ""
    /// The reactions of the message by key.
    var reactions: [String: Int] = [:]
    /// The reactions of the account.
    var mine: Set<String> = []
    /// The cursor of the server the reactions belong to.
    var cursor: String = ""
    /// Names a line written here until the server answers with its id.
    var localID: String = ""
}

/// The reactions of one message at a cursor of the server.
struct LiveReactionState: Hashable, Sendable {
    /// The message the state belongs to.
    var messageID: String
    /// The cursor of the server.
    var cursor: String
    /// The count per reaction key.
    var counts: [String: Int]
    /// The reactions of the account.
    var mine: [String]
}

/// One change of a reaction, sent by the server to all.
struct LiveReactionChange: Hashable, Sendable {
    /// The message the change belongs to.
    var messageID: String
    /// The cursor of the server.
    var cursor: String
    /// The reaction key.
    var emoji: String
    /// The new number of the reaction.
    var count: Int
    /// Whether the reaction is set now.
    var active: Bool
    /// The account made the change.
    var isSelf: Bool
}

/// The voting of the live show with the choice of the account (Go
/// `pollAnswers`).
struct LivePoll: Hashable, Sendable {
    /// What is asked.
    var question: String = ""
    /// The choices in the order of the server.
    var answers: [String] = []
    /// The votes per answer; nil while they are hidden.
    var results: [Int]?
    /// Names the voting.
    var pollID: String = ""
    /// The votes stay hidden until the voting ends.
    var secret = false
    /// The votes may be shown.
    var resultsVisible = false
    /// The number of people that took part.
    var submissions = 0
    /// The voting is over.
    var closed = false
    /// The answer of the account; -1 when it did not vote here.
    var choice: Int = -1
    /// The account voted, but not in this app or the answer is unknown: the
    /// server said so, or refused the vote of this network.
    var votedElsewhere = false

    /// Whether the votes may be shown (Go `pollPanel`).
    var showsResults: Bool { (resultsVisible && !secret) || closed }

    /// The number of the counted votes.
    var voteCount: Int { results?.reduce(0, +) ?? 0 }

    /// Whether the account voted.
    var hasVoted: Bool { choice >= 0 || votedElsewhere }

    /// Takes over a voting of the server; the choice of the account stays
    /// when the voting is the same (Go `applyPoll`).
    static func merged(_ incoming: LivePoll, current: LivePoll?) -> LivePoll {
        var next = incoming
        if let current, current.question == incoming.question, current.answers.count == incoming.answers.count {
            next.choice = current.choice
            next.votedElsewhere = current.votedElsewhere
        }
        return next
    }

    /// The share of an answer in percent (Go `pollPanel`).
    func percent(of index: Int) -> Int {
        let total = voteCount
        guard total > 0 else { return 0 }
        let votes = results ?? []
        let count = votes.indices.contains(index) ? votes[index] : 0
        return count * 100 / total
    }

    /// The footer of the panel (Go `pollPanel`).
    var footer: String {
        if closed { return "Die Abstimmung ist beendet." }
        if secret && !resultsVisible {
            return hasVoted ? "Du hast abgestimmt. Das Ergebnis bleibt verdeckt, bis die Abstimmung endet."
                : "Das Ergebnis bleibt verdeckt, bis die Abstimmung endet."
        }
        if !hasVoted { return "1 – \(answers.count) wählen" }
        // An open voting has no count of the people, only the votes.
        let votes = max(submissions, voteCount)
        return "Du hast abgestimmt · \(votes) \(votes == 1 ? "Stimme" : "Stimmen")"
    }
}

/// The answers the account gave, kept across launches. The chat server does
/// not say whether an account voted, and it takes only one vote, so the app
/// has to remember it to keep the answers locked.
enum LivePollVotes {
    private static let key = "live.pollVotes"
    /// The newest votings; older ones are long over.
    private static let limit = 30

    /// The answer the account gave to this voting: -1 when it voted with an
    /// unknown answer, nil when it did not vote.
    static func choice(for poll: LivePoll) -> Int? {
        let stored = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
        let id = identity(of: poll)
        guard let entry = stored.first(where: { $0["id"] as? String == id }),
              let choice = entry["choice"] as? Int, choice == -1 || poll.answers.indices.contains(choice)
        else { return nil }
        return choice
    }

    static func remember(_ choice: Int, for poll: LivePoll) {
        let id = identity(of: poll)
        var stored = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
        stored.removeAll { $0["id"] as? String == id }
        stored.insert(["id": id, "choice": choice], at: 0)
        UserDefaults.standard.set(Array(stored.prefix(limit)), forKey: key)
    }

    /// The id of the server when it has one, else the question with the
    /// answers.
    static func identity(of poll: LivePoll) -> String {
        if !poll.pollID.isEmpty { return "id:" + poll.pollID }
        return "q:" + ([poll.question] + poll.answers).joined(separator: "\u{1F}")
    }
}

/// The rules of the chat of the live show, ported from the Go app
/// (`internal/tui/chat_bubbles.go`, `chat_actions.go`, `chat_composer.go`,
/// `poll.go`).
enum LiveChatLogic {
    /// The time within which the messages of one sender share a bubble head
    /// (Go `chatGroupGap`).
    static let groupGap: TimeInterval = 180

    /// The number of lines the chat keeps (Go `chatHistory`).
    static let historyLimit = 300

    /// The longest message the chat takes (Go `chatLimit`).
    static let messageLimit = 500

    /// The number of characters from which the counter warns (Go
    /// `chatLimit-50`).
    static let warningLimit = 450

    /// The time in which the echo of the server replaces the pending line
    /// (Go `applyEvent`).
    static let echoWindow: TimeInterval = 15

    /// The emoji the composer offers (Go `quickEmojis`).
    static let quickEmojis = ["😂", "👍", "❤️", "🔥", "😮", "😢", "👏", "🙏", "🎉"]

    // MARK: Bubbles

    /// Whether the message belongs to the bubble of the one before, like in
    /// a messenger (Go `chatGrouped`).
    static func isGrouped(after previous: LiveChatLine?, _ current: LiveChatLine) -> Bool {
        guard let previous else { return false }
        if previous.isSystem || current.isSystem || !current.replyTo.isEmpty { return false }
        if previous.from != current.from { return false }
        if previous.isSelf != current.isSelf { return false }
        if previous.isStudio != current.isStudio { return false }
        guard let previousTime = previous.time, let currentTime = current.time else { return true }
        let gap = currentTime.timeIntervalSince(previousTime)
        return gap >= 0 && gap < groupGap
    }

    /// The name the interface shows (Go `chatName`).
    static func displayName(_ line: LiveChatLine) -> String {
        if line.isSelf { return "Du" }
        if line.from.isEmpty { return "?" }
        return line.from
    }

    /// Adds a line and keeps the history at its limit (Go `appendChatLine`).
    static func append(_ line: LiveChatLine, to lines: inout [LiveChatLine]) {
        lines.append(line)
        if lines.count > historyLimit {
            lines.removeFirst(lines.count - historyLimit)
        }
    }

    /// Replaces the pending line with the echo of the server (Go
    /// `applyEvent` for a message of the account). A pending line that is
    /// older than `echoWindow` is left alone.
    static func replacePending(with line: LiveChatLine, in lines: inout [LiveChatLine], now: Date) -> Bool {
        // The text decides first; only then an answer is known by the
        // message it answers, so two quick answers keep their order.
        for byText in [true, false] {
            for index in lines.indices.reversed() where isEcho(line, of: lines[index], byText: byText) {
                if let time = lines[index].time, now.timeIntervalSince(time) > echoWindow { return false }
                lines[index] = line
                return true
            }
        }
        return false
    }

    /// Whether a message of the server is the echo of a line of the account.
    /// A line that came from the server already is only replaced by the same
    /// message. The server cleans the text (white space, markup), so the text
    /// is compared cleaned; an answer is also known by the message it answers.
    static func isEcho(_ line: LiveChatLine, of old: LiveChatLine, byText: Bool) -> Bool {
        guard old.isSelf, !old.isSystem, !old.isStudio else { return false }
        if !old.id.isEmpty { return byText && old.id == line.id }
        if byText { return old.text == line.text || LiveHTML.cleanText(old.text) == line.text }
        return !line.replyTo.isEmpty && old.replyTo == line.replyTo
    }

    // MARK: Reactions

    /// Counts the reaction of the account in or out (Go `adjustReaction`).
    static func adjustReaction(_ line: inout LiveChatLine, key: String, active: Bool) {
        if line.mine.contains(key) == active { return }
        if active {
            line.mine.insert(key)
        } else {
            line.mine.remove(key)
        }
        if active {
            line.reactions[key, default: 0] += 1
        } else if let count = line.reactions[key], count > 0 {
            line.reactions[key] = count - 1
        }
        if line.reactions[key] == 0 {
            line.reactions.removeValue(forKey: key)
        }
    }

    /// Takes over the state of the reactions of the server (Go
    /// `applyReactionStates`). A state that is older than the one the
    /// message has is left out.
    static func applyReactionStates(_ states: [LiveReactionState], to lines: inout [LiveChatLine]) {
        for state in states {
            guard let index = lines.firstIndex(where: { $0.id == state.messageID }) else { continue }
            if !lines[index].cursor.isEmpty,
               ChatReactions.compareCursor(state.cursor, lines[index].cursor) < 0 { continue }
            var counts: [String: Int] = [:]
            for (key, count) in state.counts where count > 0 { counts[key] = count }
            lines[index].reactions = counts
            lines[index].mine = Set(state.mine)
            lines[index].cursor = state.cursor
        }
    }

    /// Takes over one change of the server (Go `applyReactionChange`). The
    /// count of the server is the total, so a change that arrives twice does
    /// no harm.
    static func applyReactionChange(_ change: LiveReactionChange, to lines: inout [LiveChatLine]) {
        guard let index = lines.firstIndex(where: { $0.id == change.messageID }) else { return }
        if !lines[index].cursor.isEmpty,
           ChatReactions.compareCursor(change.cursor, lines[index].cursor) <= 0 { return }
        if change.count > 0 {
            lines[index].reactions[change.emoji] = change.count
        } else {
            lines[index].reactions.removeValue(forKey: change.emoji)
        }
        if change.isSelf {
            if change.active {
                lines[index].mine.insert(change.emoji)
            } else {
                lines[index].mine.remove(change.emoji)
            }
        }
        lines[index].cursor = change.cursor
    }

    /// The reactions of a message in the order of the display (Go
    /// `reactionOrder`).
    static func reactionOrder(counts: [String: Int]) -> [String] {
        var order: [String: Int] = [:]
        for (index, key) in (ChatReactions.keys + ["surprised"]).enumerated() where order[key] == nil {
            order[key] = index
        }
        return counts.filter { $0.value > 0 }.keys.sorted { first, second in
            switch (order[first], order[second]) {
            case let (left?, right?): return left < right
            case (nil, _?): return false
            case (_?, nil): return true
            default: return first < second
            }
        }
    }

    /// The emoji of a reaction key (Go `reactionEmoji`).
    static func reactionEmoji(_ key: String, known: [String: String] = [:]) -> String {
        if let emoji = known[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !emoji.isEmpty { return emoji }
        return ChatReactions.emojis[key] ?? key
    }

    // MARK: Composer

    /// The state of the counter of the composer (Go `composerField`).
    enum CounterState: String, Hashable, Sendable {
        /// The text fits.
        case normal
        /// The text is near the limit.
        case warning
        /// The text is too long.
        case tooLong
    }

    /// The state of the counter for the number of characters.
    static func counterState(for count: Int) -> CounterState {
        if count > messageLimit { return .tooLong }
        if count > warningLimit { return .warning }
        return .normal
    }

    /// The text that goes out and where it goes (Go `sendChat`): "/host"
    /// sends to the studio.
    static func outgoing(_ text: String, toStudio: Bool) -> (text: String, isStudio: Bool)? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return nil }
        var studio = toStudio
        let lower = body.lowercased()
        if lower.hasPrefix("/host ") || lower == "/host" {
            studio = true
            body = String(body.dropFirst("/host".count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if body.isEmpty { return nil }
        }
        return (body, studio)
    }

    /// The number of characters of the text, counted like Go counts the
    /// runes.
    static func characterCount(_ text: String) -> Int {
        text.unicodeScalars.count
    }
}
