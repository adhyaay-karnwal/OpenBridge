@testable import OpenBridge
import Foundation
import Testing

struct AnyCodableTests {
    @Test
    func `scalar round trip`() throws {
        let encoder = makeJSONEncoder()
        let decoder = makeJSONDecoder()

        let sampleDate = Date(timeIntervalSince1970: 1_234_567)
        let sampleData = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let samples: [(label: String, value: Any?)] = [
            ("nil", Int?.none),
            ("void", ()),
            ("bool", true),
            ("int", Int(-42)),
            ("int8", Int8(-8)),
            ("int16", Int16(-16)),
            ("int32", Int32(-32)),
            ("int64", Int64(-64)),
            ("uint", UInt(42)),
            ("uint8", UInt8(8)),
            ("uint16", UInt16(16)),
            ("uint32", UInt32(32)),
            ("uint64", UInt64(64)),
            ("float", Float(1.5)),
            ("double", 2.25),
            ("data", sampleData),
            ("date", sampleDate),
            ("string", "string value"),
        ]

        for sample in samples {
            let any = AnyCodable(sample.value)
            let encoded = try encoder.encode(any)
            let decoded = try decoder.decode(AnyCodable.self, from: encoded)
            #expect(decoded == any, "Round-trip failed for \(sample.label)")
        }
    }

    @Test
    func `collection round trip`() throws {
        let encoder = makeJSONEncoder()
        let decoder = makeJSONDecoder()

        let sampleDate = Date(timeIntervalSince1970: 987_654)
        let sampleData = Data("collection".utf8)
        let array: [Any?] = [1, nil, "three", sampleDate, sampleData]
        let dictionary: [String: Any?] = [
            "nil": nil,
            "bool": true,
            "int": 7,
            "float": Float(3.5),
            "date": sampleDate,
            "data": sampleData,
            "array": array,
            "nested": ["flag": false, "value": 99],
        ]

        let value = AnyCodable(dictionary)
        let encoded = try encoder.encode(value)
        let decoded = try decoder.decode(AnyCodable.self, from: encoded)

        #expect(decoded == value)
    }

    @Test
    func `bridges between any encodable and any decodable`() throws {
        let encoder = makeJSONEncoder()
        let decoder = makeJSONDecoder()

        let sampleDate = Date(timeIntervalSince1970: 456_789)
        let sampleData = Data([0xAA, 0xBB, 0xCC])

        let payload: [String: AnyEncodable] = [
            "nil": AnyEncodable(nil as Any?),
            "bool": AnyEncodable(true),
            "int16": AnyEncodable(Int16(-12)),
            "uint32": AnyEncodable(UInt32(1234)),
            "double": AnyEncodable(3.14159),
            "float": AnyEncodable(Float(2.5)),
            "string": AnyEncodable("encodable"),
            "data": AnyEncodable(sampleData),
            "date": AnyEncodable(sampleDate),
            "array": AnyEncodable([1, nil, "three"]),
            "dictionary": AnyEncodable(["nested": 1, "flag": false]),
        ]

        let data = try encoder.encode(payload)
        let decoded = try decoder.decode([String: AnyDecodable].self, from: data)

        #expect(decoded["nil"] == AnyDecodable(nil as Any?))
        #expect(decoded["bool"] == AnyDecodable(true))
        #expect(decoded["int16"] == AnyDecodable(Int16(-12)))
        #expect(decoded["uint32"] == AnyDecodable(UInt32(1234)))
        #expect(decoded["double"] == AnyDecodable(3.14159))
        #expect(decoded["float"] == AnyDecodable(Float(2.5)))
        #expect(decoded["string"] == AnyDecodable("encodable"))
        #expect(decoded["data"] == AnyDecodable(sampleData))
        #expect(decoded["date"] == AnyDecodable(sampleDate))
        #expect(decoded["array"] == AnyDecodable([1, nil, "three"]))
        #expect(decoded["dictionary"] == AnyDecodable(["nested": 1, "flag": false]))
    }

    @Test
    func `parses mixed JSON`() throws {
        let decoder = makeJSONDecoder()
        let sampleDate = Date(timeIntervalSince1970: 321_654)
        let isoString = ISO8601DateFormatter().string(from: sampleDate)
        let sampleData = Data([0x00, 0x11, 0x22])
        let base64String = sampleData.base64EncodedString()

        // swiftlint:disable:next non_optional_string_data_conversion
        let json = """
        {
            "nil": null,
            "bool": true,
            "int": 42,
            "double": 6.28,
            "string": "value",
            "data": "\(base64String)",
            "date": "\(isoString)",
            "array": [1, null, "three"],
            "object": {"nested": false}
        }
        """.data(using: .utf8)!

        let decoded = try decoder.decode([String: AnyDecodable].self, from: json)

        #expect(decoded["nil"] == AnyDecodable(nil as Any?))
        #expect(decoded["bool"] == AnyDecodable(true))
        #expect(decoded["int"] == AnyDecodable(42))
        #expect(decoded["double"] == AnyDecodable(6.28))
        #expect(decoded["string"] == AnyDecodable("value"))
        #expect(decoded["data"] == AnyDecodable(sampleData))
        #expect(decoded["date"] == AnyDecodable(sampleDate))
        #expect(decoded["array"] == AnyDecodable([1, nil, "three"]))
        #expect(decoded["object"] == AnyDecodable(["nested": false]))
    }

    @Test
    func `hashable support`() {
        let first = AnyCodable(["a": 1, "b": [true, false]])
        let second = AnyCodable(["b": [true, false], "a": 1])
        let third = AnyCodable(123)

        #expect(first == second)

        var set = Set([first, third])
        let (inserted, _) = set.insert(second)
        #expect(inserted == false)
        #expect(set.count == 2)
    }

    private func makeJSONEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        encoder.dataEncodingStrategy = .base64
        return encoder
    }

    private func makeJSONDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.dataDecodingStrategy = .base64
        return decoder
    }
}
