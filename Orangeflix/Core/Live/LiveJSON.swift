import Foundation

/// A JSON value of the chat protocol. Number literals stay verbatim, like
/// Go's `json.RawMessage`, so cursors and ids keep their exact text.
enum LiveJSON: Sendable, Hashable {
    case null
    case bool(Bool)
    /// A number literal exactly as it was written.
    case number(String)
    case string(String)
    case array([LiveJSON])
    /// An object; a key that appears twice keeps its last value.
    case object([String: LiveJSON])

    /// A number value for an integer.
    static func integer(_ value: Int) -> LiveJSON { .number(String(value)) }

    /// Parses one JSON document; trailing data is an error.
    static func parse(_ text: String) throws(LiveJSONError) -> LiveJSON {
        var parser = LiveJSONParser(bytes: Array(text.utf8))
        return try parser.parseDocument()
    }

    /// Parses one JSON document from bytes; trailing data is an error.
    static func parse(_ data: Data) throws(LiveJSONError) -> LiveJSON {
        var parser = LiveJSONParser(bytes: [UInt8](data))
        return try parser.parseDocument()
    }

    /// The compact encoding of Go's `json.Marshal`: object keys sorted by
    /// their bytes, `<`, `>`, `&`, U+2028 and U+2029 escaped.
    var encoded: String {
        var out = ""
        encode(into: &out)
        return out
    }

    private func encode(into out: inout String) {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let literal): out += literal
        case .string(let value): Self.encodeString(value, into: &out)
        case .array(let items):
            out += "["
            for (index, item) in items.enumerated() {
                if index > 0 { out += "," }
                item.encode(into: &out)
            }
            out += "]"
        case .object(let fields):
            out += "{"
            let keys = fields.keys.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
            for (index, key) in keys.enumerated() {
                if index > 0 { out += "," }
                Self.encodeString(key, into: &out)
                out += ":"
                fields[key, default: .null].encode(into: &out)
            }
            out += "}"
        }
    }

    private static let hexDigits = Array("0123456789abcdef")

    private static func encodeString(_ value: String, into out: inout String) {
        out += "\""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "<", ">", "&", "\u{2028}", "\u{2029}":
                out += unicodeEscape(scalar.value)
            default:
                if scalar.value < 0x20 {
                    out += unicodeEscape(scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }

    private static func unicodeEscape(_ value: UInt32) -> String {
        var text = "\\u"
        for shift in stride(from: 12, through: 0, by: -4) {
            text.append(hexDigits[Int((value >> UInt32(shift)) & 0xF)])
        }
        return text
    }
}

/// A JSON text that could not be read, or a value of the wrong type.
struct LiveJSONError: Error, Sendable, Equatable {
    var message: String
}

// MARK: - Go decoding rules

/// Accessors with the rules of Go's `encoding/json` when it fills a typed
/// field: `null` leaves the zero value, a value of another type is an error.
extension LiveJSON {
    var isNull: Bool { self == .null }

    /// A Go `string` field.
    func goString() throws(LiveJSONError) -> String {
        switch self {
        case .null: return ""
        case .string(let value): return value
        default: throw LiveJSONError(message: "not a string")
        }
    }

    /// A Go `bool` field.
    func goBool() throws(LiveJSONError) -> Bool {
        switch self {
        case .null: return false
        case .bool(let value): return value
        default: throw LiveJSONError(message: "not a bool")
        }
    }

    /// A Go `*bool` field: `null` stays nil.
    func goOptionalBool() throws(LiveJSONError) -> Bool? {
        if isNull { return nil }
        return try goBool()
    }

    /// A Go `int`/`int64` field: only an integer literal without fraction or
    /// exponent that fits 64 bits.
    func goInt() throws(LiveJSONError) -> Int {
        switch self {
        case .null: return 0
        case .number(let literal):
            guard let value = Int(literal) else { throw LiveJSONError(message: "not an integer") }
            return value
        default: throw LiveJSONError(message: "not a number")
        }
    }

    /// A Go `float64` field.
    func goDouble() throws(LiveJSONError) -> Double {
        switch self {
        case .null: return 0
        case .number(let literal):
            guard let value = Double(literal), value.isFinite else { throw LiveJSONError(message: "number out of range") }
            return value
        default: throw LiveJSONError(message: "not a number")
        }
    }

    /// A Go `*float64` field: `null` stays nil.
    func goOptionalDouble() throws(LiveJSONError) -> Double? {
        if isNull { return nil }
        return try goDouble()
    }

    /// A Go struct: `null` is the zero struct (an empty field set).
    func goObject() throws(LiveJSONError) -> [String: LiveJSON] {
        switch self {
        case .null: return [:]
        case .object(let fields): return fields
        default: throw LiveJSONError(message: "not an object")
        }
    }

    /// A Go pointer to a struct: `null` stays nil.
    func goOptionalObject() throws(LiveJSONError) -> [String: LiveJSON]? {
        if isNull { return nil }
        return try goObject()
    }

    /// A Go slice: `null` is a nil slice.
    func goArray() throws(LiveJSONError) -> [LiveJSON]? {
        switch self {
        case .null: return nil
        case .array(let items): return items
        default: throw LiveJSONError(message: "not an array")
        }
    }

    /// A Go `[]string`.
    func goStrings() throws(LiveJSONError) -> [String]? {
        guard let items = try goArray() else { return nil }
        var out: [String] = []
        out.reserveCapacity(items.count)
        for item in items { out.append(try item.goString()) }
        return out
    }

    /// A Go `map[string]string`.
    func goStringMap() throws(LiveJSONError) -> [String: String]? {
        if isNull { return nil }
        guard case .object(let fields) = self else { throw LiveJSONError(message: "not an object") }
        var out: [String: String] = [:]
        for (key, value) in fields { out[key] = try value.goString() }
        return out
    }

    /// A Go `map[string]float64`.
    func goDoubleMap() throws(LiveJSONError) -> [String: Double]? {
        if isNull { return nil }
        guard case .object(let fields) = self else { throw LiveJSONError(message: "not an object") }
        var out: [String: Double] = [:]
        for (key, value) in fields { out[key] = try value.goDouble() }
        return out
    }
}

extension Dictionary where Key == String, Value == LiveJSON {
    /// The value of a struct field: the exact key first, then a key that
    /// differs only in case, as Go matches struct fields.
    func field(_ name: String) -> LiveJSON? {
        if let value = self[name] { return value }
        let folded = name.lowercased()
        return first { $0.key.lowercased() == folded }?.value
    }
}

// MARK: - Parser

/// A strict JSON reader (RFC 8259) that keeps number literals verbatim.
struct LiveJSONParser {
    private let bytes: [UInt8]
    private var index = 0
    private static let maxDepth = 512

    init(bytes: [UInt8]) {
        self.bytes = bytes
    }

    mutating func parseDocument() throws(LiveJSONError) -> LiveJSON {
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw fail("trailing data") }
        return value
    }

    private func fail(_ message: String) -> LiveJSONError {
        LiveJSONError(message: "\(message) at offset \(index)")
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0A, 0x0D].contains(bytes[index]) { index += 1 }
    }

    private mutating func parseValue(depth: Int) throws(LiveJSONError) -> LiveJSON {
        guard depth < Self.maxDepth else { throw fail("nesting too deep") }
        skipWhitespace()
        guard index < bytes.count else { throw fail("unexpected end") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject(depth: depth)
        case UInt8(ascii: "["): return try parseArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expectLiteral("true"); return .bool(true)
        case UInt8(ascii: "f"): try expectLiteral("false"); return .bool(false)
        case UInt8(ascii: "n"): try expectLiteral("null"); return .null
        default: return .number(try parseNumber())
        }
    }

    private mutating func expectLiteral(_ literal: String) throws(LiveJSONError) {
        let expected = Array(literal.utf8)
        guard index + expected.count <= bytes.count,
              bytes[index..<(index + expected.count)].elementsEqual(expected) else { throw fail("invalid literal") }
        index += expected.count
    }

    private mutating func parseObject(depth: Int) throws(LiveJSONError) -> LiveJSON {
        index += 1
        var fields: [String: LiveJSON] = [:]
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
            index += 1
            return .object(fields)
        }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("expected key") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("expected colon") }
            index += 1
            fields[key] = try parseValue(depth: depth + 1)
            skipWhitespace()
            guard index < bytes.count else { throw fail("unexpected end") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(fields) }
            throw fail("expected comma or end of object")
        }
    }

    private mutating func parseArray(depth: Int) throws(LiveJSONError) -> LiveJSON {
        index += 1
        var items: [LiveJSON] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
            index += 1
            return .array(items)
        }
        while true {
            items.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            guard index < bytes.count else { throw fail("unexpected end") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            throw fail("expected comma or end of array")
        }
    }

    private mutating func parseNumber() throws(LiveJSONError) -> String {
        let start = index
        func isDigit(_ byte: UInt8) -> Bool { byte >= 0x30 && byte <= 0x39 }
        if index < bytes.count, bytes[index] == UInt8(ascii: "-") { index += 1 }
        guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid number") }
        if bytes[index] == 0x30 {
            index += 1
        } else {
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
            index += 1
            guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid fraction") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
            index += 1
            if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count, isDigit(bytes[index]) else { throw fail("invalid exponent") }
            while index < bytes.count, isDigit(bytes[index]) { index += 1 }
        }
        return String(decoding: bytes[start..<index], as: UTF8.self)
    }

    private mutating func parseHex4() throws(LiveJSONError) -> UInt32 {
        guard index + 4 <= bytes.count else { throw fail("invalid escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let byte = bytes[index]
            let digit: UInt32
            switch byte {
            case 0x30...0x39: digit = UInt32(byte - 0x30)
            case 0x41...0x46: digit = UInt32(byte - 0x41 + 10)
            case 0x61...0x66: digit = UInt32(byte - 0x61 + 10)
            default: throw fail("invalid escape")
            }
            value = value << 4 | digit
            index += 1
        }
        return value
    }

    /// Reads a string; invalid UTF-8 and lone surrogates become U+FFFD, as
    /// in Go.
    private mutating func parseString() throws(LiveJSONError) -> String {
        index += 1
        var buffer: [UInt8] = []
        while true {
            guard index < bytes.count else { throw fail("unterminated string") }
            let byte = bytes[index]
            switch byte {
            case UInt8(ascii: "\""):
                index += 1
                return String(decoding: buffer, as: UTF8.self)
            case UInt8(ascii: "\\"):
                index += 1
                guard index < bytes.count else { throw fail("invalid escape") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): buffer.append(0x22)
                case UInt8(ascii: "\\"): buffer.append(0x5C)
                case UInt8(ascii: "/"): buffer.append(0x2F)
                case UInt8(ascii: "b"): buffer.append(0x08)
                case UInt8(ascii: "f"): buffer.append(0x0C)
                case UInt8(ascii: "n"): buffer.append(0x0A)
                case UInt8(ascii: "r"): buffer.append(0x0D)
                case UInt8(ascii: "t"): buffer.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try parseHex4()
                    if (0xD800...0xDBFF).contains(scalar) {
                        let save = index
                        if index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") {
                            index += 2
                            let low = try parseHex4()
                            if (0xDC00...0xDFFF).contains(low) {
                                scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                            } else {
                                scalar = 0xFFFD
                                index = save
                            }
                        } else {
                            scalar = 0xFFFD
                        }
                    } else if (0xDC00...0xDFFF).contains(scalar) {
                        scalar = 0xFFFD
                    }
                    buffer.append(contentsOf: Array(String(Unicode.Scalar(scalar) ?? "\u{FFFD}").utf8))
                default:
                    throw fail("invalid escape")
                }
            default:
                guard byte >= 0x20 else { throw fail("control character in string") }
                buffer.append(byte)
                index += 1
            }
        }
    }
}
