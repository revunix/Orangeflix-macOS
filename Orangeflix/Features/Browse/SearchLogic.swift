import Foundation
import SwiftUI

/// Where a hit of the search matched; the filter above the results.
enum SearchKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all, titles, chapters, spoken

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "Alle"
        case .titles: "Titel & Text"
        case .chapters: "Kapitel"
        case .spoken: "Gesprochen"
        }
    }

    func matches(_ hit: SearchResult) -> Bool {
        switch self {
        case .all: true
        case .titles: hit.kind == .clip
        case .chapters: hit.chapter != nil
        case .spoken: !hit.passages.isEmpty
        }
    }
}

/// The order of the results.
enum SearchSort: String, CaseIterable, Identifiable, Sendable {
    case relevance, newest, oldest

    var id: String { rawValue }

    var title: String {
        switch self {
        case .relevance: "Relevanz"
        case .newest: "Neueste zuerst"
        case .oldest: "Älteste zuerst"
        }
    }
}

enum SearchLogic {
    /// The shortest query the search sends; one letter finds everything.
    static let minimumQueryLength = 2
    /// The hits of one page.
    static let pageSize = 40
    /// The pause after the last key before the live search asks the server.
    static let typingDelay: Duration = .milliseconds(280)
    /// The searches the history keeps.
    static let historyLimit = 8

    /// The hits in the chosen order with the chosen kind.
    static func visible(_ hits: [SearchResult], kind: SearchKindFilter, sort: SearchSort) -> [SearchResult] {
        let filtered = hits.filter(kind.matches)
        switch sort {
        case .relevance: return filtered
        case .newest: return filtered.enumerated().sorted { byTime($0, $1, newest: true) }.map(\.element)
        case .oldest: return filtered.enumerated().sorted { byTime($0, $1, newest: false) }.map(\.element)
        }
    }

    /// Hits without a date go last; equal dates keep the order of relevance.
    private static func byTime(_ a: (offset: Int, element: SearchResult), _ b: (offset: Int, element: SearchResult),
                               newest: Bool) -> Bool {
        let left = a.element.time, right = b.element.time
        if left == right { return a.offset < b.offset }
        if left == 0 { return false }
        if right == 0 { return true }
        return newest ? left > right : left < right
    }

    /// The number of loaded hits of each kind.
    static func counts(_ hits: [SearchResult]) -> [SearchKindFilter: Int] {
        Dictionary(uniqueKeysWithValues: SearchKindFilter.allCases.map { kind in
            (kind, hits.filter(kind.matches).count)
        })
    }

    /// `history` with `query` at the front, without doubles (any case) and
    /// capped at `historyLimit`.
    static func remembering(_ query: String, in history: [String]) -> [String] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= minimumQueryLength else { return history }
        let rest = history.filter { $0.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame }
        return Array(([trimmed] + rest).prefix(historyLimit))
    }

    // MARK: Highlighting

    /// The text of the API with its `<em>` marks as emphasised runs; other
    /// tags are dropped and the common entities resolved.
    static func highlighted(_ html: String) -> AttributedString {
        var result = AttributedString()
        var rest = Substring(html)
        var emphasised = false
        while !rest.isEmpty {
            guard let open = rest.firstIndex(of: "<") else {
                result += run(rest, emphasised: emphasised)
                break
            }
            result += run(rest[..<open], emphasised: emphasised)
            guard let close = rest[open...].firstIndex(of: ">") else {
                result += run(rest[open...], emphasised: emphasised)
                break
            }
            let tag = rest[rest.index(after: open)..<close].lowercased()
            if tag == "em" || tag == "mark" || tag == "b" { emphasised = true }
            if tag == "/em" || tag == "/mark" || tag == "/b" { emphasised = false }
            rest = rest[rest.index(after: close)...]
        }
        return result
    }

    /// `text` with every word of `query` emphasised, regardless of case and
    /// accents; the titles of the API come without marks.
    static func marked(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init).filter { $0.count >= 2 }
        for word in words {
            var searchRange = text.startIndex..<text.endIndex
            while let found = text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange) {
                if let lower = AttributedString.Index(found.lowerBound, within: result),
                   let upper = AttributedString.Index(found.upperBound, within: result) {
                    emphasise(&result[lower..<upper])
                }
                searchRange = found.upperBound..<text.endIndex
            }
        }
        return result
    }

    private static func run(_ text: Substring, emphasised: Bool) -> AttributedString {
        var part = AttributedString(unescaped(String(text)))
        if emphasised { emphasise(&part[part.startIndex..<part.endIndex]) }
        return part
    }

    private static func emphasise(_ part: inout AttributedSubstring) {
        part.inlinePresentationIntent = .stronglyEmphasized
        part.foregroundColor = Palette.accentText
    }

    private static let entities = [
        "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&#39;": "'", "&apos;": "'", "&nbsp;": " ",
    ]

    static func unescaped(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = text
        for (entity, character) in entities { result = result.replacingOccurrences(of: entity, with: character) }
        return result
    }
}
