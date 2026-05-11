import Foundation

@frozen
public nonisolated struct AnyDecodable: Decodable {
    public let contentValue: Any

    public init(_ value: (some Any)?) {
        contentValue = AnyCodableTypes.normalize(value ?? ())
    }
}

@usableFromInline
// swiftlint:disable:next type_name
nonisolated protocol _AnyDecodable {
    var contentValue: Any { get }
    init(_ value: (some Any)?)
}

nonisolated extension AnyDecodable: _AnyDecodable {}

nonisolated extension _AnyDecodable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.singleValueContainer()

        if let value = AnyCodableTypes.decode(from: &container) {
            self.init(value)
            return
        }

        assertionFailure("AnyDecodable.decode: unsupported value at codingPath \(container.codingPath)")
        throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyDecodable value cannot be decoded")
    }
}

nonisolated extension AnyDecodable: Equatable {
    public static func == (lhs: AnyDecodable, rhs: AnyDecodable) -> Bool {
        AnyCodableTypes.equals(lhs.contentValue, rhs.contentValue) ?? false
    }
}

nonisolated extension AnyDecodable: CustomStringConvertible {
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

nonisolated extension AnyDecodable: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch contentValue {
        case let value as CustomDebugStringConvertible:
            "AnyDecodable(\(value.debugDescription))"
        default:
            "AnyDecodable(\(description))"
        }
    }
}

nonisolated extension AnyDecodable: Hashable {
    public func hash(into hasher: inout Hasher) {
        if !AnyCodableTypes.hash(contentValue, into: &hasher) {
            hasher.combine(String(describing: type(of: contentValue)))
        }
    }
}
