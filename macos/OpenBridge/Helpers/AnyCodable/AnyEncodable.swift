import Foundation

@frozen
public nonisolated struct AnyEncodable: Encodable {
    public let contentValue: Any

    public init(_ value: (some Any)?) {
        contentValue = AnyCodableTypes.normalize(value ?? ())
    }
}

@usableFromInline
// swiftlint:disable:next type_name
nonisolated protocol _AnyEncodable {
    var contentValue: Any { get }
    init(_ value: (some Any)?)
}

nonisolated extension AnyEncodable: _AnyEncodable {}

nonisolated extension _AnyEncodable {
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        if try AnyCodableTypes.encode(contentValue, into: &container, encoder: encoder) {
            return
        }

        assertionFailure("AnyEncodable.encode: unsupported value of type \(type(of: contentValue))")
        let context = EncodingError.Context(codingPath: container.codingPath, debugDescription: "AnyEncodable value cannot be encoded")
        throw EncodingError.invalidValue(contentValue, context)
    }
}

nonisolated extension AnyEncodable: Equatable {
    public static func == (lhs: AnyEncodable, rhs: AnyEncodable) -> Bool {
        AnyCodableTypes.equals(lhs.contentValue, rhs.contentValue) ?? false
    }
}

nonisolated extension AnyEncodable: CustomStringConvertible {
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

nonisolated extension AnyEncodable: CustomDebugStringConvertible {
    public var debugDescription: String {
        switch contentValue {
        case let value as CustomDebugStringConvertible:
            "AnyEncodable(\(value.debugDescription))"
        default:
            "AnyEncodable(\(description))"
        }
    }
}

nonisolated extension AnyEncodable: ExpressibleByNilLiteral {}
nonisolated extension AnyEncodable: ExpressibleByBooleanLiteral {}
nonisolated extension AnyEncodable: ExpressibleByIntegerLiteral {}
nonisolated extension AnyEncodable: ExpressibleByFloatLiteral {}
nonisolated extension AnyEncodable: ExpressibleByStringLiteral {}
nonisolated extension AnyEncodable: ExpressibleByStringInterpolation {}
nonisolated extension AnyEncodable: ExpressibleByArrayLiteral {}
nonisolated extension AnyEncodable: ExpressibleByDictionaryLiteral {}

nonisolated extension _AnyEncodable {
    public init(nilLiteral _: ()) {
        self.init(nil as Any?)
    }

    public init(booleanLiteral value: Bool) {
        self.init(value)
    }

    public init(integerLiteral value: Int) {
        self.init(value)
    }

    public init(floatLiteral value: Double) {
        self.init(value)
    }

    public init(extendedGraphemeClusterLiteral value: String) {
        self.init(value)
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    public init(arrayLiteral elements: Any...) {
        self.init(elements)
    }

    public init(dictionaryLiteral elements: (AnyHashable, Any)...) {
        self.init([AnyHashable: Any](elements, uniquingKeysWith: { first, _ in first }))
    }
}

nonisolated extension AnyEncodable: Hashable {
    public func hash(into hasher: inout Hasher) {
        if !AnyCodableTypes.hash(contentValue, into: &hasher) {
            hasher.combine(String(describing: type(of: contentValue)))
        }
    }
}
