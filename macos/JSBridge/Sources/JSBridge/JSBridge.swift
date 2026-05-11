// The Swift Programming Language
// https://docs.swift.org/swift-book

import Foundation

// MARK: - JSBridge Macro

/// Marks a class as a JSBridge for bidirectional JavaScript ↔ Swift communication.
///
/// The macro automatically generates:
/// - `name` property matching the type name
/// - `evaluator` property for Swift → JS event emission
/// - `jsBridgeCall(name:args:)` method for JS → Swift calls
/// - Conformance to `JSBridge` protocol
/// - TypeScript interface in `index.d.ts` (via JSBridgeBuildTool)
///
/// **Important:** `@JSBridge` can only be applied to classes. This is because the bridge
/// holds a reference to the evaluator, and value types (structs) would copy the evaluator
/// instead of sharing it.
///
/// **Usage:**
/// ```swift
/// @JSBridge
/// class ActionBridge {
///     func openURL(urlString: String) async throws { ... }
/// }
///
/// // With Swift → JS events
/// @JSBridge
/// class NotificationBridge {
///     @EmitEvent
///     func newMessage(content: String)
/// }
///
/// // JavaScript:
/// await window.jsb.ActionBridge.openURL("https://example.com");
/// window.jsb.NotificationBridge.onNewMessage((content) => console.log(content));
/// ```
@attached(member, names: named(name), named(evaluator))
@attached(extension, conformances: JSBridge, names: named(jsBridgeCall), arbitrary)
public macro JSBridge() = #externalMacro(module: "JSBridgeMacros", type: "JSBridgeMacro")

/// Marks a struct as a data type to be exposed to TypeScript.
///
/// The macro generates a TypeScript interface for the struct in `index.d.ts`.
/// Use this for return types or parameter types that need TypeScript definitions.
///
/// **Usage:**
/// ```swift
/// @JSBridgeType
/// struct UserInfo {
///     let id: String
///     let name: String
///     let age: Int?
/// }
/// ```
///
/// **Generated TypeScript:**
/// ```typescript
/// export interface UserInfo {
///     id: string;
///     name: string;
///     age: number | undefined | null;
/// }
/// ```
@attached(extension, conformances: JSBridgeType)
public macro JSBridgeType() = #externalMacro(module: "JSBridgeMacros", type: "JSBridgeTypeMacro")

/// Closure type for evaluating JavaScript
public typealias JSEvaluator = @MainActor (String) async throws -> Void

// MARK: - JSBridge Protocol (Bidirectional JS ↔ Swift)

@MainActor
public protocol JSBridge {
    var name: String { get }
    var evaluator: JSEvaluator? { get set }
    func jsBridgeCall(name: String, args: String) async throws -> String?
}

public protocol JSBridgeType {}

// MARK: - Event Emission (Swift → JS)

public extension JSBridge {
    /// Emit an event with encoded JSON data (fire-and-forget)
    func _emit(_ eventName: String, json: String) {
        let bridgeName = name
        let eval = evaluator
        Task { @MainActor in
            let script = "window.jsbEvents?.emit('\(bridgeName).\(eventName)', \(json))"
            try? await eval?(script)
        }
    }

    /// Emit an event with encodable data (fire-and-forget)
    func _emit(_ eventName: String, data: some Encodable) {
        guard let json = try? jsBridgeEncodeJSON(data) else { return }
        _emit(eventName, json: json)
    }

    /// Emit an event with no data (fire-and-forget)
    func _emit(_ eventName: String) {
        _emit(eventName, json: "null")
    }
}

// MARK: - EmitEvent Macro

/// Marks a method as an event emitter within a `@JSBridge` type.
///
/// The method parameters become the event payload:
/// - No parameters → emits `null`
/// - Single parameter → emits the value directly
/// - Multiple parameters → emits as array `[param1, param2, ...]`
///
/// Events are fire-and-forget (non-blocking) and silently fail if evaluator is nil.
///
/// **Usage:**
/// ```swift
/// @JSBridge
/// class NotificationBridge {
///     @EmitEvent
///     func newMessage(content: String)
/// }
///
/// // After binding to BridgeView, evaluator is set automatically
/// bridge.newMessage(content: "Hi!")  // Fire-and-forget
/// ```
///
/// **JavaScript side:**
/// ```typescript
/// window.jsb.NotificationBridge.onNewMessage((content) => console.log(content));
/// ```
@attached(body)
public macro EmitEvent() = #externalMacro(module: "JSBridgeMacros", type: "EmitEventMacro")

public func jsBridgeDecodeJSON<T: Decodable>(
    _ json: String,
    as _: T.Type
) throws -> T {
    guard let data = json.data(using: .utf8) else {
        throw InvalidJSONError()
    }
    return try JSONDecoder().decode(T.self, from: data)
}

public func jsBridgeEncodeJSON(
    _ value: some Encodable
) throws -> String {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(value)
    guard let string = String(data: data, encoding: .utf8) else {
        throw InvalidJSONError()
    }
    return string
}

public struct InvalidJSONError: Error, CustomStringConvertible {
    public var description: String {
        "Invalid JSON string"
    }
}
