import Foundation

// swiftlint:disable:next blanket_disable_command
// swiftlint:disable all

@usableFromInline
nonisolated enum AnyCodableTypes {
    @usableFromInline
    nonisolated struct TypeDescriptor {
        let decode: (inout SingleValueDecodingContainer) -> Any?
        let encode: (Any, inout SingleValueEncodingContainer, Encoder) throws -> Bool
        let equals: (Any, Any) -> Bool?
        let hash: (Any, inout Hasher) -> Bool
    }

    @usableFromInline
    nonisolated static var scalarDescriptors: [TypeDescriptor] {
        [
            .scalar(Bool.self),
            .scalar(Int8.self),
            .scalar(Int16.self),
            .scalar(Int32.self),
            .scalar(Int64.self),
            .scalar(Int.self),
            .scalar(UInt8.self),
            .scalar(UInt16.self),
            .scalar(UInt32.self),
            .scalar(UInt64.self),
            .scalar(UInt.self),
            .scalar(Float.self),
            .scalar(Double.self),
            .scalar(Data.self),
            .scalar(Date.self),
            .scalar(String.self),
        ]
    }

    @usableFromInline
    nonisolated static func normalize(_ value: Any) -> Any {
        if let optional = unwrapOptional(value) {
            switch optional {
            case .none:
                return ()
            case let .some(unwrapped):
                return normalize(unwrapped)
            }
        }

        switch value {
        case is Void:
            return ()
        case let anyCodable as AnyCodable:
            return anyCodable.contentValue
        case let anyEncodable as AnyEncodable:
            return anyEncodable.contentValue
        case let anyDecodable as AnyDecodable:
            return anyDecodable.contentValue
        case let array as [AnyCodable]:
            return array
        case let array as [Any]:
            return array.map { AnyCodable($0) }
        case let array as [Any?]:
            return array.map { AnyCodable($0) }
        case let dictionary as [String: AnyCodable]:
            return dictionary
        case let dictionary as [String: Any]:
            return dictionary.reduce(into: [String: AnyCodable]()) { result, element in
                result[element.key] = AnyCodable(element.value)
            }
        case let dictionary as [String: Any?]:
            return dictionary.reduce(into: [String: AnyCodable]()) { result, element in
                result[element.key] = AnyCodable(element.value)
            }
        case let dictionary as [AnyHashable: AnyCodable]:
            return dictionary
        case let dictionary as [AnyHashable: Any]:
            return dictionary.reduce(into: [AnyHashable: AnyCodable]()) { result, element in
                result[element.key] = AnyCodable(element.value)
            }
        case let dictionary as [AnyHashable: Any?]:
            return dictionary.reduce(into: [AnyHashable: AnyCodable]()) { result, element in
                result[element.key] = AnyCodable(element.value)
            }
        default:
            return value
        }
    }

    @usableFromInline
    nonisolated static func decode(from container: inout SingleValueDecodingContainer) -> Any? {
        if container.decodeNil() {
            return ()
        }

        for descriptor in scalarDescriptors {
            if let value = descriptor.decode(&container) {
                return value
            }
        }

        if let array = try? container.decode([AnyCodable].self) {
            return array
        }

        if let dictionary = try? container.decode([String: AnyCodable].self) {
            return dictionary
        }

        assertionFailure("AnyCodableTypes.decode: unsupported value")
        return nil
    }

    @usableFromInline
    nonisolated static func encode(_ value: Any, into container: inout SingleValueEncodingContainer, encoder: Encoder) throws -> Bool {
        let normalized = normalize(value)

        if normalized is Void {
            try container.encodeNil()
            return true
        }

        for descriptor in scalarDescriptors {
            if try descriptor.encode(normalized, &container, encoder) {
                return true
            }
        }

        if let array = normalized as? [AnyCodable] {
            try container.encode(array)
            return true
        }

        if let dictionary = normalized as? [String: AnyCodable] {
            try container.encode(dictionary)
            return true
        }

        if let dictionary = normalized as? [AnyHashable: AnyCodable] {
            assertionFailure("AnyCodableTypes.encode: dictionary keys must be String to encode, got \(dictionary.keys.map { String(describing: $0) })")
            return false
        }

        if let encodable = normalized as? Encodable {
            try encodable.encode(to: encoder)
            return true
        }

        assertionFailure("AnyCodableTypes.encode: unsupported value of type \(type(of: normalized))")
        return false
    }

    @usableFromInline
    nonisolated static func equals(_ lhs: Any, _ rhs: Any) -> Bool? {
        let lhsNormalized = normalize(lhs)
        let rhsNormalized = normalize(rhs)

        if lhsNormalized is Void, rhsNormalized is Void {
            return true
        }

        for descriptor in scalarDescriptors {
            if let result = descriptor.equals(lhsNormalized, rhsNormalized) {
                return result
            }
        }

        if let lhsArray = lhsNormalized as? [AnyCodable], let rhsArray = rhsNormalized as? [AnyCodable] {
            return lhsArray == rhsArray
        }

        if let lhsDictionary = lhsNormalized as? [String: AnyCodable], let rhsDictionary = rhsNormalized as? [String: AnyCodable] {
            return lhsDictionary == rhsDictionary
        }

        if let lhsDictionary = lhsNormalized as? [AnyHashable: AnyCodable], let rhsDictionary = rhsNormalized as? [AnyHashable: AnyCodable] {
            return lhsDictionary == rhsDictionary
        }

        if let numeric = numericEquals(lhsNormalized, rhsNormalized) {
            return numeric
        }

        return nil
    }

    @discardableResult
    @usableFromInline
    nonisolated static func hash(_ value: Any, into hasher: inout Hasher) -> Bool {
        let normalized = normalize(value)

        if normalized is Void {
            hasher.combine(0)
            return true
        }

        for descriptor in scalarDescriptors {
            if descriptor.hash(normalized, &hasher) {
                return true
            }
        }

        if let array = normalized as? [AnyCodable] {
            hasher.combine(array.count)
            for element in array {
                hasher.combine(element)
            }
            return true
        }

        if let dictionary = normalized as? [String: AnyCodable] {
            hashDictionary(dictionary, into: &hasher)
            return true
        }

        if let dictionary = normalized as? [AnyHashable: AnyCodable] {
            hashDictionary(dictionary, into: &hasher)
            return true
        }

        if let numeric = asDecimal(normalized) {
            hasher.combine(numeric)
            return true
        }

        assertionFailure("AnyCodableTypes.hash: unsupported value of type \(type(of: normalized))")
        return false
    }

    private nonisolated static func hashDictionary(_ dictionary: [some Hashable: AnyCodable], into hasher: inout Hasher) {
        let entries = dictionary.map { (String(describing: $0.key), $0.value) }.sorted { $0.0 < $1.0 }
        hasher.combine(entries.count)
        for (key, value) in entries {
            hasher.combine(key)
            hasher.combine(value)
        }
    }
}

private nonisolated extension AnyCodableTypes.TypeDescriptor {
    nonisolated static func scalar<T: Codable & Equatable & Hashable>(_: T.Type) -> AnyCodableTypes.TypeDescriptor {
        AnyCodableTypes.TypeDescriptor(
            decode: { container in try? container.decode(T.self) },
            encode: { value, container, _ in
                guard let casted = value as? T else { return false }
                try container.encode(casted)
                return true
            },
            equals: { lhs, rhs in
                guard let lhs = lhs as? T, let rhs = rhs as? T else { return nil }
                return lhs == rhs
            },
            hash: { value, hasher in
                guard let casted = value as? T else { return false }
                hasher.combine(casted)
                return true
            }
        )
    }
}

private nonisolated extension AnyCodableTypes {
    nonisolated enum OptionalValue {
        case none
        case some(Any)
    }

    nonisolated static func unwrapOptional(_ value: Any) -> OptionalValue? {
        let mirror = Mirror(reflecting: value)
        guard mirror.displayStyle == .optional else { return nil }
        guard let child = mirror.children.first else {
            return OptionalValue.none
        }
        return OptionalValue.some(child.value)
    }

    nonisolated static func numericEquals(_ lhs: Any, _ rhs: Any) -> Bool? {
        guard let lhsValue = asDecimal(lhs), let rhsValue = asDecimal(rhs) else { return nil }
        return lhsValue == rhsValue
    }

    nonisolated static func asDecimal(_ value: Any) -> Decimal? {
        if let integer = value as? any BinaryInteger {
            return Decimal(string: String(describing: integer))
        }
        if let floating = value as? any BinaryFloatingPoint {
            return Decimal(string: String(describing: floating))
        }
        return nil
    }
}
