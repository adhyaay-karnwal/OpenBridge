import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct JSBridgeMacro: MemberMacro, ExtensionMacro {
    // MARK: - MemberMacro (add name and evaluator properties)

    public static func expansion(
        of _: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            throw JSBridgeError("@JSBridge can only be applied to class")
        }

        let typeName = getTypeName(from: declaration)

        return [
            "var name: String { \"\(raw: typeName)\" }",
            "var evaluator: JSEvaluator?",
        ]
    }

    // MARK: - ExtensionMacro (add protocol conformance)

    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(ClassDeclSyntax.self) else {
            throw JSBridgeError("@JSBridge can only be applied to class")
        }

        // Find all methods (excluding @EmitEvent, private, static)
        let regularMethods = declaration.memberBlock.members.compactMap { member -> FunctionDeclSyntax? in
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else { return nil }
            // Skip @EmitEvent methods
            if hasAttribute(funcDecl.attributes, named: "EmitEvent") { return nil }
            // Skip private/fileprivate
            if funcDecl.modifiers.contains(where: { $0.name.text == "private" || $0.name.text == "fileprivate" }) { return nil }
            // Skip static
            if funcDecl.modifiers.contains(where: { $0.name.text == "static" }) { return nil }
            return funcDecl
        }

        let functionDefinitions = try regularMethods.map { try FunctionDefinition($0) }

        // Build jsBridgeCall method
        let paramsTypes = functionDefinitions.map { $0.jsBridgeParamsType() }.joined(separator: "\n")
        let bridgeCalls = functionDefinitions.map { $0.jsBridgeCall() }.joined(separator: "\n")

        return try [ExtensionDeclSyntax("""
        extension \(raw: type.trimmed): JSBridge {
            \(raw: paramsTypes)

           func jsBridgeCall(name: String, args: String) async throws -> String? {
                \(raw: bridgeCalls)
                return nil
           }
        }
        """)]
    }

    private static func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
        for attribute in attributes {
            guard case let .attribute(attr) = attribute else { continue }
            if let identifier = attr.attributeName.as(IdentifierTypeSyntax.self),
               identifier.name.text == name
            {
                return true
            }
        }
        return false
    }
}

// MARK: - Shared Helpers

private func getTypeName(from declaration: some DeclGroupSyntax) -> String {
    if let classDecl = declaration.as(ClassDeclSyntax.self) {
        return classDecl.name.text
    }
    return "Unknown"
}

public struct JSBridgeTypeMacro: ExtensionMacro {
    public static func expansion(
        of _: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo _: [TypeSyntax],
        in _: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Check if declaration is a struct
        guard declaration.is(StructDeclSyntax.self) else {
            throw JSBridgeError("@JSBridgeType can only be applied to struct")
        }

        return try [ExtensionDeclSyntax("""
        extension \(raw: type.trimmed): JSBridgeType {
        }
        """)]
    }
}

// MARK: - EmitEvent Macro (Body Macro)

public struct EmitEventMacro: BodyMacro {
    public static func expansion(
        of _: AttributeSyntax,
        providingBodyFor declaration: some DeclSyntaxProtocol & WithOptionalCodeBlockSyntax,
        in _: some MacroExpansionContext
    ) throws -> [CodeBlockItemSyntax] {
        guard let funcDecl = declaration.as(FunctionDeclSyntax.self) else {
            throw JSBridgeError("@EmitEvent can only be applied to functions")
        }

        let methodName = funcDecl.name.text
        let params = funcDecl.signature.parameterClause.parameters

        // Build the emit call (fire-and-forget, no await/try needed)
        if params.count == 0 {
            return [
                "_emit(\"\(raw: methodName)\")",
            ]
        } else if params.count == 1 {
            let param = params.first!
            let paramName = param.firstName.text == "_"
                ? (param.secondName?.text ?? "value")
                : param.firstName.text
            return [
                "_emit(\"\(raw: methodName)\", data: \(raw: paramName))",
            ]
        } else {
            // Multiple params - emit as array
            let paramNames = params.map { param -> String in
                param.firstName.text == "_"
                    ? (param.secondName?.text ?? "value")
                    : param.firstName.text
            }
            return [
                "_emit(\"\(raw: methodName)\", data: [\(raw: paramNames.joined(separator: ", "))])",
            ]
        }
    }
}

struct FunctionDefinition {
    let name: String
    let parameters: FunctionParameterListSyntax
    let returnType: TypeSyntax?
    let isAsync: Bool
    let isThrowing: Bool

    init(_ from: FunctionDeclSyntax) throws {
        name = from.name.text
        parameters = from.signature.parameterClause.parameters
        for parameter in parameters {
            if parameter.defaultValue != nil {
                throw JSBridgeError("Default value is not supported for JSBridge parameters")
            }
        }
        returnType = from.signature.returnClause?.type
        isAsync = from.signature.effectSpecifiers?.asyncSpecifier != nil
        isThrowing = from.signature.effectSpecifiers?.throwsClause != nil
    }

    func jsBridgeParamsType() -> String {
        let paramsTypeVarList = parameters.map {
            let name = $0.firstName.text
            let isUnnamed = name == "_"
            return "var \(isUnnamed ? "unnamed" : name): \($0.type)"
        }.joined(separator: "\n")
        let paramsTypeInit = """
        init(from decoder: Decoder) throws {
            var container = try decoder.unkeyedContainer()
            \(parameters.map {
                let name = $0.firstName.text
                let isUnnamed = name == "_"
                return "self.\(isUnnamed ? "unnamed" : name) = try container.decode(\($0.type).self)"
            }.joined(separator: "\n"))
        }
        """
        return parameters.count > 0 ? """
        struct JSBridgeParams_\(name): Decodable {
           \(paramsTypeVarList) 
           \(paramsTypeInit)
        }
        """ : ""
    }

    func jsBridgeCall() -> String {
        let callFunc = """
        \(isThrowing ? "try " : "")\(isAsync ? "await " : "")\(name)(\(
            parameters.map {
                let name = $0.firstName.text
                let isUnnamed = name == "_"
                if isUnnamed {
                    return "params.unnamed"
                }
                return "\(name): params.\(name)"
            }.joined(separator: ", ")
        ))
        """

        let hasReturnType = returnType != nil

        return """
        if name == "\(name)" {
            \(parameters.count > 0 ? "let params = try jsBridgeDecodeJSON(args, as: JSBridgeParams_\(name).self)" : "")
            \(hasReturnType ?
            "return try jsBridgeEncodeJSON(\(callFunc))" : "\(callFunc)\nreturn nil")
        }
        """
    }
}

private struct JSBridgeError: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

@main
struct JSBridgePlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        JSBridgeMacro.self,
        JSBridgeTypeMacro.self,
        EmitEventMacro.self,
    ]
}
