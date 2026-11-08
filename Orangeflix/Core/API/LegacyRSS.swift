import Foundation

/// The RSS feeds of the legacy API: ten episodes per request, much cheaper
/// than the JSON feed.
extension LegacyAPIClient {
    /// The URL of one feed page, e.g. `…/feed/23-1/hd.xml?page=1`.
    func rssPageURL(pid: Int, submodule: Int, page: Int, quality: String = "hd") -> String {
        let quality = quality.isEmpty ? "hd" : quality
        return "\(feedURL)\(pid)-\(submodule)/\(quality).xml?page=\(page)"
    }

    /// One page of an RSS feed.
    func rssPage(pid: Int, submodule: Int, page: Int, quality: String = "hd") async throws -> [Episode] {
        let data = try await get(rssPageURL(pid: pid, submodule: submodule, page: page, quality: quality))
        let feed = try LegacyRSSParser.parse(data)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"

        var episodes: [Episode] = []
        episodes.reserveCapacity(feed.items.count)
        for item in feed.items {
            let identifier = item.guid.trimmingCharacters(in: .whitespacesAndNewlines)
            if identifier.isEmpty { continue }
            var episode = Episode(
                identifier: identifier,
                pid: pid,
                number: Self.numberFromIdentifier(identifier),
                title: item.title,
                formatName: feed.title.trimmingCharacters(in: .whitespacesAndNewlines),
                description: Self.stripHTML(item.description),
                duration: item.duration.trimmingCharacters(in: .whitespacesAndNewlines))
            episode.date = formatter.date(from: item.pubDate.trimmingCharacters(in: .whitespacesAndNewlines))
            if episode.number == 0 { episode.number = Self.numberFromTitle(item.title) }
            episodes.append(episode)
        }
        return episodes
    }

    /// Every episode of a format over the RSS feed, oldest first. Stops at
    /// an empty page or a page without new episodes; at most 200 pages.
    func episodesViaRSS(pid: Int, submodule: Int, quality: String = "hd") async throws -> [Episode] {
        var seen = Set<String>()
        var all: [Episode] = []
        for page in 1...200 {
            let episodes = try await rssPage(pid: pid, submodule: submodule, page: page, quality: quality)
            if episodes.isEmpty { break }
            var added = 0
            for episode in episodes where seen.insert(episode.identifier).inserted {
                all.append(episode)
                added += 1
            }
            if added == 0 { break }
        }
        return Self.sortedByNumber(all)
    }

    /// The episode number of a title like "Folge 420 - Die Mediatheke".
    static func numberFromTitle(_ title: String) -> Int {
        let fields = title.split(whereSeparator: \.isWhitespace)
        for (index, field) in fields.enumerated() {
            let lowered = field.lowercased()
            guard lowered == "folge" || lowered == "folge:", index + 1 < fields.count else { continue }
            let candidate = fields[index + 1].trimmingCharacters(in: CharacterSet(charactersIn: ".,:"))
            if let value = Int(candidate) { return value }
        }
        return 0
    }

    /// Removes the tags of a description, decodes the HTML entities and
    /// collapses the whitespace.
    static func stripHTML(_ text: String) -> String {
        let withoutTags = text.replacingOccurrences(of: "<[^>]*>", with: " ", options: .regularExpression)
        return LegacyHTMLEntities.decode(withoutTags)
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
    }
}

/// The parts of an RSS document the app reads.
struct LegacyRSSFeed: Sendable {
    struct Item: Sendable {
        var title = ""
        var link = ""
        var pubDate = ""
        var guid = ""
        var description = ""
        var duration = ""
    }

    var title = ""
    var items: [Item] = []
}

/// Parses an RSS document like Go's `encoding/xml` with the field tags of
/// the Go client: elements match by their local name (so `itunes:duration`
/// fills `duration`), only direct children count, the last one wins.
final class LegacyRSSParser: NSObject, XMLParserDelegate {
    private var feed = LegacyRSSFeed()
    private var path: [String] = []
    private var text = ""
    private var item: LegacyRSSFeed.Item?

    static func parse(_ data: Data) throws -> LegacyRSSFeed {
        let delegate = LegacyRSSParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.shouldProcessNamespaces = false
        guard parser.parse() else {
            let reason = parser.parserError.map { $0.localizedDescription } ?? "unbekannter Fehler"
            throw APIError.feedParsing(reason)
        }
        return delegate.feed
    }

    private static func localName(_ name: String) -> String {
        name.split(separator: ":").last.map(String.init) ?? name
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName)
        path.append(name)
        text = ""
        // root > channel > item
        if path.count == 3, path[1] == "channel", name == "item" {
            item = LegacyRSSFeed.Item()
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        text += String(decoding: CDATABlock, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        defer {
            path.removeLast()
            text = ""
        }
        if path.count == 3, path[1] == "channel" {
            if name == "item", let item {
                feed.items.append(item)
                self.item = nil
            } else if name == "title" {
                feed.title = text
            }
            return
        }
        guard path.count == 4, path[1] == "channel", path[2] == "item", item != nil else { return }
        switch name {
        case "title": item?.title = text
        case "link": item?.link = text
        case "pubDate": item?.pubDate = text
        case "guid": item?.guid = text
        case "description": item?.description = text
        case "duration": item?.duration = text
        default: break
        }
    }
}

/// Decodes HTML character references: numeric ones and the named entities
/// that occur in German feed texts.
enum LegacyHTMLEntities {
    private static let named: [String: String] = [
        "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}",
        "auml": "ä", "ouml": "ö", "uuml": "ü", "Auml": "Ä", "Ouml": "Ö", "Uuml": "Ü", "szlig": "ß",
        "eacute": "é", "egrave": "è", "ecirc": "ê", "aacute": "á", "agrave": "à", "acirc": "â",
        "oacute": "ó", "ograve": "ò", "ocirc": "ô", "uacute": "ú", "ugrave": "ù", "iacute": "í",
        "ccedil": "ç", "ntilde": "ñ", "Eacute": "É",
        "euro": "€", "pound": "£", "copy": "©", "reg": "®", "trade": "™", "deg": "°", "sect": "§",
        "ndash": "–", "mdash": "—", "hellip": "…", "bull": "•", "middot": "·", "shy": "\u{00AD}",
        "laquo": "«", "raquo": "»", "lsaquo": "‹", "rsaquo": "›",
        "bdquo": "„", "ldquo": "“", "rdquo": "”", "sbquo": "‚", "lsquo": "‘", "rsquo": "’",
        "times": "×", "divide": "÷", "plusmn": "±", "frac12": "½", "frac14": "¼", "frac34": "¾",
        "sup2": "²", "sup3": "³", "micro": "µ", "para": "¶", "iexcl": "¡", "iquest": "¿",
        "thinsp": "\u{2009}", "ensp": "\u{2002}", "emsp": "\u{2003}", "zwnj": "\u{200C}", "zwj": "\u{200D}",
    ]

    static func decode(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        result.reserveCapacity(text.utf8.count)
        var index = text.startIndex
        while index < text.endIndex {
            let character = text[index]
            guard character == "&",
                  let semicolon = text[index...].prefix(34).firstIndex(of: ";") else {
                result.append(character)
                index = text.index(after: index)
                continue
            }
            let name = text[text.index(after: index)..<semicolon]
            if let replacement = replacement(for: name) {
                result += replacement
                index = text.index(after: semicolon)
            } else {
                result.append(character)
                index = text.index(after: index)
            }
        }
        return result
    }

    private static func replacement(for name: Substring) -> String? {
        if name.hasPrefix("#") {
            let digits = name.dropFirst()
            let value: UInt32?
            if digits.hasPrefix("x") || digits.hasPrefix("X") {
                value = UInt32(digits.dropFirst(), radix: 16)
            } else {
                value = UInt32(digits, radix: 10)
            }
            guard let value else { return nil }
            // Like Go: invalid code points become U+FFFD.
            return String(Unicode.Scalar(value) ?? "\u{FFFD}")
        }
        return named[String(name)]
    }
}
