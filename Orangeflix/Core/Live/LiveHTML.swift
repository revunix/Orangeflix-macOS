import Foundation

/// The text cleaning of the chat: the web chat sends messages as HTML.
enum LiveHTML {
    /// A line break of the web chat. Go's `\s` is ASCII white space.
    private static let breakTag = try! NSRegularExpression(pattern: "(?i)<br[\\t\\n\\f\\r ]*/?>")
    /// Any other tag of the web chat; the text between the tags stays.
    private static let markupTag = try! NSRegularExpression(pattern: "</?[a-zA-Z][^<>]*>")

    /// Turns the HTML of a chat message into plain text. The tags are taken
    /// out before the entities are decoded: what a user typed arrives escaped
    /// ("&lt;3") and must stay. A line break that was escaped twice is caught
    /// after decoding. Runs of white space become one blank.
    static func cleanText(_ raw: String) -> String {
        var text = replace(breakTag, in: raw, with: " ")
        text = replace(markupTag, in: text, with: "")
        text = unescape(text)
        text = replace(breakTag, in: text, with: " ")
        return fields(text).joined(separator: " ")
    }

    private static func replace(_ expression: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(text.startIndex..., in: text)
        return expression.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    /// Splits around runs of Unicode white space, like Go's `strings.Fields`.
    static func fields(_ text: String) -> [String] {
        var out: [String] = []
        var current = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            if scalar.properties.isWhitespace {
                if !current.isEmpty {
                    out.append(String(current))
                    current = String.UnicodeScalarView()
                }
            } else {
                current.append(scalar)
            }
        }
        if !current.isEmpty { out.append(String(current)) }
        return out
    }

    /// Windows-1252 replacements of the numeric references 0x80…0x9F.
    private static let replacementTable: [UInt32] = [
        0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021,
        0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F,
        0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
        0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178,
    ]

    /// Decodes the character references of HTML5 exactly like Go's
    /// `html.UnescapeString`.
    static func unescape(_ text: String) -> String {
        guard text.utf8.contains(UInt8(ascii: "&")) else { return text }
        let bytes = Array(text.utf8)
        var out: [UInt8] = []
        out.reserveCapacity(bytes.count)
        var source = 0
        while source < bytes.count {
            if bytes[source] == UInt8(ascii: "&") {
                source = unescapeEntity(bytes, at: source, into: &out)
            } else {
                out.append(bytes[source])
                source += 1
            }
        }
        return String(decoding: out, as: UTF8.self)
    }

    private static func append(_ scalar: UInt32, to out: inout [UInt8]) {
        let value = Unicode.Scalar(scalar) ?? "\u{FFFD}"
        out.append(contentsOf: Array(String(value).utf8))
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        (0x61...0x7A).contains(byte) || (0x41...0x5A).contains(byte) || (0x30...0x39).contains(byte)
    }

    /// Reads the reference at `start` (an "&") and returns the index after it.
    private static func unescapeEntity(_ bytes: [UInt8], at start: Int, into out: inout [UInt8]) -> Int {
        let length = bytes.count - start
        func at(_ offset: Int) -> UInt8 { bytes[start + offset] }
        if length <= 1 {
            out.append(at(0))
            return start + 1
        }
        var i = 1
        if at(i) == UInt8(ascii: "#") {
            if length <= 3 {
                out.append(at(0))
                return start + 1
            }
            i += 1
            var hex = false
            if at(i) == UInt8(ascii: "x") || at(i) == UInt8(ascii: "X") {
                hex = true
                i += 1
            }
            var value: UInt32 = 0
            while i < length {
                let c = at(i)
                i += 1
                var digit: UInt32?
                if hex {
                    switch c {
                    case 0x30...0x39: digit = UInt32(c - 0x30)
                    case 0x61...0x66: digit = UInt32(c - 0x61 + 10)
                    case 0x41...0x46: digit = UInt32(c - 0x41 + 10)
                    default: digit = nil
                    }
                } else if (0x30...0x39).contains(c) {
                    digit = UInt32(c - 0x30)
                }
                if let digit {
                    // Saturate: anything above U+10FFFF is invalid anyway.
                    value = min(value * (hex ? 16 : 10) + digit, 0x110000)
                    continue
                }
                if c != UInt8(ascii: ";") { i -= 1 }
                break
            }
            if i <= 3 {
                out.append(at(0))
                return start + 1
            }
            if (0x80...0x9F).contains(value) {
                value = replacementTable[Int(value - 0x80)]
            } else if value == 0 || (0xD800...0xDFFF).contains(value) || value > 0x10FFFF {
                value = 0xFFFD
            }
            append(value, to: &out)
            return start + i
        }

        while i < length {
            let c = at(i)
            i += 1
            if isAlphanumeric(c) { continue }
            if c != UInt8(ascii: ";") { i -= 1 }
            break
        }
        let name = String(decoding: bytes[(start + 1)..<(start + i)], as: UTF8.self)
        if !name.isEmpty {
            if let scalars = LiveHTMLEntities.table[name] {
                for scalar in scalars { append(scalar.value, to: &out) }
                return start + i
            }
            let nameBytes = Array(name.utf8)
            let maxLength = min(nameBytes.count - 1, LiveHTMLEntities.longestWithoutSemicolon)
            if maxLength > 1 {
                for j in stride(from: maxLength, to: 1, by: -1) {
                    let prefix = String(decoding: nameBytes[0..<j], as: UTF8.self)
                    if let scalars = LiveHTMLEntities.table[prefix], scalars.count == 1 {
                        append(scalars[0].value, to: &out)
                        return start + j + 1
                    }
                }
            }
        }
        out.append(contentsOf: bytes[start..<(start + i)])
        return start + i
    }
}
