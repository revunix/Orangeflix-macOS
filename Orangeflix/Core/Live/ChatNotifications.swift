import Foundation

/// The rules that turn a chat event into a notification. Pure logic, so the
/// wording and the match of a mention are testable without the app.
enum ChatNotifications {
    /// The shortest chat name a mention is looked for. A name of one letter
    /// would match half of the chat.
    static let minimumNameLength = 2

    /// How long an excerpt of a message may be before it is cut.
    static let excerptLimit = 120

    /// Whether `text` mentions the account. Like the web chat
    /// (`livechat.js`), every occurrence of the own chat name counts,
    /// whatever the case: the server has no separate mention marker.
    static func mentions(_ text: String, name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= minimumNameLength, !text.isEmpty else { return false }
        return text.range(of: name, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    /// The line of a mention: "Name: Text".
    static func mentionBody(from: String, text: String) -> String {
        let who = from.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = excerpt(text)
        return who.isEmpty ? body : "\(who): \(body)"
    }

    /// The line of a reaction on an own message: "Name: 👍 auf deine
    /// Nachricht: „…“".
    static func reactionBody(actor: String, emoji: String, text: String) -> String {
        let who = actor.trimmingCharacters(in: .whitespacesAndNewlines)
        let reacted = "\(emoji) auf deine Nachricht"
        let message = excerpt(text)
        let line = message.isEmpty ? reacted : "\(reacted): „\(message)“"
        return who.isEmpty ? line : "\(who): \(line)"
    }

    /// A one-line excerpt of a message for a notification; empty for empty
    /// text.
    static func excerpt(_ text: String, limit: Int = excerptLimit) -> String {
        let clean = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count > limit else { return clean }
        return String(clean.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
    }
}
