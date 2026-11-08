import Foundation

// The models of the chapter suggestions. A viewer may write the chapters of
// an episode; the server keeps the suggestion until it is decided.

// MARK: - Categories

/// A category a suggested chapter may carry.
struct ChapterCategory: Sendable, Hashable, Decodable, Identifiable {
    var id: String { key }

    /// The name of the category.
    var key = ""
    /// The name the interface shows.
    var label = ""
    /// The color of the category on the timeline.
    var color = ""

    init(from decoder: any Decoder) throws {
        let c = try decoder.apiContainer()
        key = try c.zero("key")
        label = try c.zero("label")
        color = try c.zero("color")
    }
}

// MARK: - Suggestions

/// One chapter of a suggestion.
struct SuggestedChapter: Sendable, Hashable, Identifiable {
    /// The name of the chapter together with its start; two chapters of the
    /// same episode may carry the same name.
    var id: String { "\(start)-\(title)" }

    /// The name of the chapter.
    var title = ""
    /// The start of the chapter in seconds.
    var start = 0.0
    /// The end of the chapter in seconds.
    var end = 0.0
    /// The category of the chapter; empty when it has none.
    var category = ""

    /// The length of the chapter in seconds.
    var duration: Double { max(end - start, 0) }

    init(title: String, start: Double, end: Double, category: String = "") {
        self.title = title
        self.start = start
        self.end = end
        self.category = category
    }

    init(raw: JSONValue) {
        title = raw.firstString(of: ["title", "name", "label"]) ?? ""
        start = ChapterModels.seconds(raw["start"]) ?? 0
        end = ChapterModels.seconds(raw["end"]) ?? 0
        category = raw.firstString(of: ["category", "categoryKey", "kind"]) ?? ""
    }
}

/// The state that is needed to write a chapter suggestion for an episode.
struct ChapterSuggestionContext: Sendable, Hashable, Decodable {
    /// Whether the account may write a suggestion.
    var canSubmit = false
    /// The revision of the chapters the suggestion is based on.
    var revision = 0
    /// The chapters the episode has now.
    var chapters: [SuggestedChapter] = []
    /// The suggestion of the account that is still open.
    var openSuggestion: ChapterSuggestion?
    /// The outcome of the last decided suggestion of the account.
    var lastDecision: ChapterDecision?

    init(from decoder: any Decoder) throws {
        let raw = try JSONValue(from: decoder)
        canSubmit = raw.firstBool(of: ["canSubmit", "allowed", "maySubmit", "permitted"]) ?? false
        revision = raw.firstInt(of: ["revision", "chapterRevision", "chaptersRevision"]) ?? 0
        chapters = (raw.array("chapters") ?? []).map { SuggestedChapter(raw: $0) }
        if let suggestion = raw["openSuggestion"] ?? raw["ownSuggestion"] ?? raw["suggestion"] {
            openSuggestion = ChapterSuggestion(raw: suggestion)
        }
        if let decision = raw["lastDecision"] ?? raw["lastOutcome"] ?? raw["decision"] {
            lastDecision = ChapterDecision(raw: decision)
        }
    }
}

/// A suggestion of the account for the chapters of an episode.
struct ChapterSuggestion: Sendable, Hashable {
    /// The chapters of the suggestion.
    var chapters: [SuggestedChapter] = []
    /// The revision of the chapters the suggestion is based on.
    var revision = 0
    /// The state of the suggestion ("open", "accepted", "rejected").
    var state = ""
    /// The moment the suggestion was sent, in Unix seconds.
    var createdAt: Int64 = 0

    init(raw: JSONValue) {
        chapters = (raw.array("chapters") ?? []).map { SuggestedChapter(raw: $0) }
        revision = raw.firstInt(of: ["revision", "chapterRevision", "chaptersRevision"]) ?? 0
        state = raw.firstString(of: ["state", "status"]) ?? ""
        createdAt = Int64(raw.firstInt(of: ["createdAt", "created"]) ?? 0)
    }
}

/// The outcome of a decided suggestion.
struct ChapterDecision: Sendable, Hashable {
    /// The state ("accepted", "rejected").
    var state = ""
    /// The reason the server gives.
    var reason = ""

    /// Whether the server took the chapters.
    var isAccepted: Bool { state.lowercased() == "accepted" }

    init(raw: JSONValue) {
        state = raw.firstString(of: ["state", "status", "outcome"]) ?? ""
        reason = raw.firstString(of: ["reason", "message", "note"]) ?? ""
    }
}

// MARK: - Bodies

/// The body of a chapter suggestion: the whole set of chapters and the
/// revision they are based on.
struct ChapterSuggestionBody: Encodable {
    /// The revision of the chapters the suggestion is based on.
    var revision: Int64
    /// The chapters of the episode.
    var chapters: [SuggestedChapterBody]

    init(revision: Int64, chapters: [SuggestedChapterBody]) {
        self.revision = revision
        self.chapters = chapters
    }
}

/// One chapter of a suggestion.
struct SuggestedChapterBody: Encodable {
    /// The name of the chapter.
    var title: String
    /// The start of the chapter in seconds.
    var start: Double
    /// The end of the chapter in seconds.
    var end: Double
    /// The category of the chapter; left out when it has none.
    var category: String?

    init(title: String, start: Double, end: Double, category: String? = nil) {
        self.title = title
        self.start = start
        self.end = end
        self.category = category
    }
}

// MARK: - Helpers

/// Reads the answers of the chapter endpoints, whose shape the API does not
/// fix.
enum ChapterModels {
    /// The seconds of a value; the API writes whole seconds as a number or
    /// as a string.
    static func seconds(_ value: JSONValue?) -> Double? {
        guard let value else { return nil }
        if case .number(let number) = value { return number }
        if case .string(let text) = value, let number = Double(text) { return number }
        return nil
    }
}
