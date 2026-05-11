import Foundation

@frozen
public nonisolated struct AnyCodable: Codable {
    @usableFromInline
    let contentValue: Any

    public init(_ value: (some Any)?) {
        contentValue = AnyCodableTypes.normalize(value ?? ())
    }

    public func decodingValue<T: Codable>(defaultValue: T) -> T {
        (try? decodingValue()) ?? defaultValue
    }

    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    public func decodingValue<T: Codable>() throws -> T? {
        if let value = contentValue as? T { return value }
        // code and decode the value for conversion
        let data = try Self.encoder.encode(self)
        return try Self.decoder.decode(T.self, from: data)
    }
}

nonisolated extension AnyCodable: _AnyEncodable, _AnyDecodable {}

nonisolated extension AnyCodable: Equatable {
    public static func == (lhs: AnyCodable, rhs: AnyCodable) -> Bool {
        AnyCodableTypes.equals(lhs.contentValue, rhs.contentValue) ?? false
    }
}

nonisolated extension AnyCodable: CustomStringConvertible {
    public var description: String {
        switch contentValue {
        case is Void:
            String(describing: nil as Any?)
        case let value as CustomStringConvertible:
            value.description
        default:
            String(describing: contentValue)
        }
    }
}

nonisolated extension AnyCodable: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch contentValue {
        case let value as CustomDebugStringConvertible:
            "AnyCodable(\(value.debugDescription))"
        default:
            "AnyCodable(\(description))"
        }
    }
}

nonisolated extension AnyCodable: ExpressibleByNilLiteral {}
nonisolated extension AnyCodable: ExpressibleByBooleanLiteral {}
nonisolated extension AnyCodable: ExpressibleByIntegerLiteral {}
nonisolated extension AnyCodable: ExpressibleByFloatLiteral {}
nonisolated extension AnyCodable: ExpressibleByStringLiteral {}
nonisolated extension AnyCodable: ExpressibleByStringInterpolation {}
nonisolated extension AnyCodable: ExpressibleByArrayLiteral {}
nonisolated extension AnyCodable: ExpressibleByDictionaryLiteral {}

nonisolated extension AnyCodable: Hashable {
    public func hash(into hasher: inout Hasher) {
        if !AnyCodableTypes.hash(contentValue, into: &hasher) {
            hasher.combine(String(describing: type(of: contentValue)))
        }
    }
}
