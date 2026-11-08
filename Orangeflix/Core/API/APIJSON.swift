import Foundation

// JSON decoding that behaves like Go's encoding/json for the API answers:
// a missing field or `null` yields the zero value of the field, a value of
// the wrong type is an error.

/// A type with a zero value, used for fields that are missing or `null`.
protocol APIZeroValue {
    init()
}

extension String: APIZeroValue {}
extension Int: APIZeroValue {}
extension Int64: APIZeroValue {}
extension Double: APIZeroValue {}
extension Bool: APIZeroValue {}
extension Array: APIZeroValue {}
extension Dictionary: APIZeroValue {}

/// A coding key made from a plain string.
struct APIKey: CodingKey {
    let stringValue: String
    let intValue: Int? = nil

    init(_ string: String) { stringValue = string }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { return nil }
}

extension KeyedDecodingContainer where Key == APIKey {
    /// Decodes a field; a missing field or `null` gives the zero value.
    func zero<T: Decodable & APIZeroValue>(_ key: String) throws -> T {
        try decodeIfPresent(T.self, forKey: APIKey(key)) ?? T()
    }

    /// Decodes a field that may be missing or `null`.
    func optional<T: Decodable>(_ key: String) throws -> T? {
        try decodeIfPresent(T.self, forKey: APIKey(key))
    }

    /// Decodes a field and swallows a wrong shape: a field of another type
    /// gives nil instead of an error, so one unknown field does not spoil the
    /// whole answer.
    func tolerant<T: Decodable>(_ key: String) -> T? {
        let codingKey = APIKey(key)
        guard contains(codingKey) else { return nil }
        return try? decodeIfPresent(T.self, forKey: codingKey)
    }

    /// The container of a nested object; `nil` when it is missing or `null`.
    func nested(_ key: String) throws -> KeyedDecodingContainer<APIKey>? {
        let codingKey = APIKey(key)
        guard contains(codingKey), try !decodeNil(forKey: codingKey) else { return nil }
        return try nestedContainer(keyedBy: APIKey.self, forKey: codingKey)
    }
}

extension Decoder {
    /// The keyed container of an API object.
    func apiContainer() throws -> KeyedDecodingContainer<APIKey> {
        try container(keyedBy: APIKey.self)
    }
}

/// An arbitrary JSON value, for fields whose shape the API does not fix
/// (tags that are strings or objects, raw nested answers).
enum JSONValue: Sendable, Hashable, Codable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    /// The string of a `.string` value.
    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    /// The member of an `.object` value.
    subscript(key: String) -> JSONValue? {
        if case .object(let members) = self { return members[key] }
        return nil
    }

    /// The members of an `.object` value.
    var objectValue: [String: JSONValue]? {
        if case .object(let members) = self { return members }
        return nil
    }

    /// The elements of an `.array` value.
    var arrayValue: [JSONValue]? {
        if case .array(let elements) = self { return elements }
        return nil
    }

    /// The number of an `.number` value.
    var intValue: Int? {
        switch self {
        case .number(let number): return Int(number)
        case .string(let text): return Int(text)
        default: return nil
        }
    }

    /// The flag of a `.bool` value.
    var boolValue: Bool? {
        if case .bool(let flag) = self { return flag }
        return nil
    }

    /// The member of an `.object` value, as a string.
    func string(_ key: String) -> String? {
        switch self[key] {
        case .string(let text): return text
        default: return nil
        }
    }

    /// The member of an `.object` value, as a number. A string that holds a
    /// number counts too.
    func int(_ key: String) -> Int? {
        switch self[key] {
        case .number(let number): return Int(number)
        case .string(let text): return Int(text)
        default: return nil
        }
    }

    /// The member of an `.object` value, as a flag. A number counts as a
    /// flag too, so 0 is false and 1 is true.
    func bool(_ key: String) -> Bool? {
        switch self[key] {
        case .bool(let flag): return flag
        case .number(let number): return number != 0
        default: return nil
        }
    }

    /// The member of an `.object` value, as a list.
    func array(_ key: String) -> [JSONValue]? {
        self[key]?.arrayValue
    }

    /// The member of an `.object` value, as an object.
    func object(_ key: String) -> [String: JSONValue]? {
        self[key]?.objectValue
    }

    /// The first member that is a string, out of the named ones.
    func firstString(of keys: [String]) -> String? {
        for key in keys {
            if let text = string(key), !text.isEmpty { return text }
        }
        return nil
    }

    /// The first member that is a number, out of the named ones.
    func firstInt(of keys: [String]) -> Int? {
        for key in keys {
            if let number = int(key) { return number }
        }
        return nil
    }

    /// The first member that is a flag, out of the named ones.
    func firstBool(of keys: [String]) -> Bool? {
        for key in keys {
            if let flag = bool(key) { return flag }
        }
        return nil
    }

    /// Decodes the value into a type; it fails when the shape does not fit.
    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try APIJSON.decode(type, from: APIJSON.encode(self))
    }
}

/// Encodes and decodes the bodies of the API.
enum APIJSON {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw APIError.decoding(String(describing: error))
        }
    }
}
