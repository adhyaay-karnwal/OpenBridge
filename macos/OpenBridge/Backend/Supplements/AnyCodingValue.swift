import Foundation

nonisolated enum AnyCodingValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([AnyCodingValue])
    case object([String: AnyCodingValue])

    var bool: Bool? {
        get { if case let .bool(b) = self { b } else { nil } }
        set { if let newValue { self = .bool(newValue) } else { self = nil } }
    }

    var double: Double? {
        get { if case let .number(n) = self { n } else { nil } }
        set { if let newValue { self = .number(newValue) } else { self = nil } }
    }

    var int: Int? {
        get {
            if case let .number(n) = self {
                let rounded = n.rounded()
                return rounded == n ? Int(rounded) : nil
            }
            if case let .string(s) = self {
                return Int(s)
            }
            return nil
        }
        set {
            if let newValue {
                self = .number(Double(newValue))
            } else {
                self = nil
            }
        }
    }

    var string: String? {
        get { if case let .string(s) = self { s } else { nil } }
        set { if let newValue { self = .string(newValue) } else { self = nil } }
    }

    var array: [AnyCodingValue]? {
        get { if case let .array(a) = self { a } else { nil } }
        set { if let newValue { self = .array(newValue) } else { self = nil } }
    }

    var object: [String: AnyCodingValue]? {
        get { if case let .object(o) = self { o } else { nil } }
        set { if let newValue { self = .object(newValue) } else { self = nil } }
    }

    var isNull: Bool {
        if case .null = self { true } else { false }
    }

    subscript(_ key: String) -> AnyCodingValue? {
        get { object?[key] }
        set {
            guard case var .object(o) = self, let newValue else { return }
            o[key] = newValue
            self = .object(o)
        }
    }

    subscript(_ index: Int) -> AnyCodingValue? {
        get {
            // check the index is within the bounds of the array, prevent out of bounds access crash
            if let array, array.indices.contains(index) {
                return array[index]
            }
            return nil
        }
        set {
            guard case var .array(a) = self, let newValue, a.indices.contains(index) else { return }
            a[index] = newValue
            self = .array(a)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
        } else if let b = try? c.decode(Bool.self) {
            self = .bool(b)
        } else if let n = try? c.decode(Double.self) {
            self = .number(n)
        } else if let s = try? c.decode(String.self) {
            self = .string(s)
        } else if let a = try? c.decode([AnyCodingValue].self) {
            self = .array(a)
        } else if let o = try? c.decode([String: AnyCodingValue].self) {
            self = .object(o)
        } else {
            throw DecodingError.dataCorrupted(
                .init(codingPath: c.codingPath, debugDescription: "Invalid JSON")
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(b): try c.encode(b)
        case let .number(n): try c.encode(n)
        case let .string(s): try c.encode(s)
        case let .array(a): try c.encode(a)
        case let .object(o): try c.encode(o)
        }
    }

    /// Convert the AnyCodingValue to a JSON string.
    func toString() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try? encoder.encode(self)
        guard let data else {
            // should never happen
            return "<invalid json>"
        }
        return String(data: data, encoding: .utf8)
            ?? "<invalid json>" // should never happen
    }

    /// Convert the AnyCodingValue to a JSON data.
    func toData() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try? encoder.encode(self)
        guard let data else {
            // should never happen
            return Data()
        }
        return data
    }
}

nonisolated extension AnyCodingValue: CustomStringConvertible {
    var description: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        if let data = try? encoder.encode(self), let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "<invalid json>"
    }
}

nonisolated extension AnyCodingValue: ExpressibleByNilLiteral {
    init(nilLiteral _: ()) {
        self = .null
    }
}

nonisolated extension AnyCodingValue: ExpressibleByBooleanLiteral {
    init(booleanLiteral value: Bool) {
        self = .bool(value)
    }
}

nonisolated extension AnyCodingValue: ExpressibleByFloatLiteral {
    init(floatLiteral value: Double) {
        self = .number(value)
    }
}

nonisolated extension AnyCodingValue: ExpressibleByIntegerLiteral {
    init(integerLiteral value: Int) {
        self = .number(Double(value))
    }
}

nonisolated extension AnyCodingValue: ExpressibleByStringLiteral {
    init(stringLiteral value: String) {
        self = .string(value)
    }
}

nonisolated extension AnyCodingValue: ExpressibleByArrayLiteral {
    init(arrayLiteral elements: AnyCodingValue...) {
        self = .array(elements)
    }
}

nonisolated extension AnyCodingValue: ExpressibleByDictionaryLiteral {
    init(dictionaryLiteral elements: (String, AnyCodingValue)...) {
        self = .object(.init(uniqueKeysWithValues: elements))
    }
}

nonisolated enum JSONConversionError: Error {
    case unsupportedType(typeName: String)
}

nonisolated extension AnyCodingValue {
    init(jsonObject: Any) throws {
        switch jsonObject {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else {
                self = .number(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let array as [Any]:
            self = try .array(array.map { try AnyCodingValue(jsonObject: $0) })
        case let dictionary as [String: Any]:
            let converted = try dictionary.reduce(into: [String: AnyCodingValue]()) {
                result, element in
                result[element.key] = try AnyCodingValue(jsonObject: element.value)
            }
            self = .object(converted)
        default:
            throw JSONConversionError.unsupportedType(
                typeName: String(describing: type(of: jsonObject))
            )
        }
    }

    static func decoded(from data: Data) throws -> AnyCodingValue {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        return try AnyCodingValue(jsonObject: object)
    }
}
