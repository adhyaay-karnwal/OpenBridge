import Foundation
import SwiftParser
import SwiftSyntax

// swiftlint:disable cyclomatic_complexity function_body_length
@main
struct JSBridgeBuildTool {
    static func main() throws {
        let startTime = Date()
        let arguments = CommandLine.arguments

        guard arguments.count >= 4,
              let outputFlagIndex = arguments.firstIndex(of: "-o"),
              outputFlagIndex + 1 < arguments.count
        else {
            printUsage()
            exit(1)
        }

        let searchPath = arguments[1]
        let outputFile = arguments[outputFlagIndex + 1]

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: searchPath, isDirectory: &isDirectory),
              isDirectory.boolValue
        else {
            fputs("Error: Search path does not exist or is not a directory: \(searchPath)\n", stderr)
            exit(1)
        }

        // Find all Swift files in the directory
        let swiftFiles = findSwiftFiles(in: searchPath)

        if swiftFiles.isEmpty {
            print("No Swift files found in: \(searchPath)")
            try "".write(toFile: outputFile, atomically: true, encoding: .utf8)
            return
        }

        print("Found \(swiftFiles.count) Swift files to process...")

        // Collect all JSBridge types from all files
        var allJsBridgeTypes: [JSBridgeTypeInfo] = []
        var allJsBridgeDataTypes: [JSBridgeDataTypeInfo] = []

        for swiftFile in swiftFiles {
            let sourceCode = try String(contentsOfFile: swiftFile, encoding: .utf8)

            // Skip files without @JSBridge or @JSBridgeType
            guard sourceCode.contains("@JSBridge") else {
                continue
            }

            let sourceFile = Parser.parse(source: sourceCode)
            let visitor = JSBridgeVisitor(viewMode: .sourceAccurate)
            visitor.walk(sourceFile)

            let foundCount = visitor.jsBridgeTypes.count + visitor.jsBridgeDataTypes.count
            if foundCount > 0 {
                print("  Processing: \(swiftFile) - found \(foundCount) types")
                allJsBridgeTypes.append(contentsOf: visitor.jsBridgeTypes)
                allJsBridgeDataTypes.append(contentsOf: visitor.jsBridgeDataTypes)
            }
        }

        // Create output directory if needed
        let outputURL = URL(fileURLWithPath: outputFile)
        let outputDirURL = outputURL.deletingLastPathComponent()

        if !FileManager.default.fileExists(atPath: outputDirURL.path) {
            try FileManager.default.createDirectory(
                at: outputDirURL,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        let totalCount = allJsBridgeTypes.count + allJsBridgeDataTypes.count
        if totalCount == 0 {
            print("No @JSBridge or @JSBridgeType types found in any files.")
            try "".write(toFile: outputFile, atomically: true, encoding: .utf8)
            return
        }

        // Generate output: data types first, then bridge types
        var outputParts: [String] = []
        outputParts.append(contentsOf: allJsBridgeDataTypes.map { $0.toTypeScript() })

        // Generate interfaces for @JSBridge types (both methods and events)
        for typeInfo in allJsBridgeTypes {
            var interfaceMembers: [String] = []

            // Add JS → Swift methods
            for method in typeInfo.methods {
                interfaceMembers.append("  \(method.name): \(method.tsFunction())")
            }

            // Add Swift → JS event subscriptions
            for event in typeInfo.events {
                let capitalizedName = event.name.prefix(1).uppercased() + event.name.dropFirst()
                let eventType = event.tsEventType()
                interfaceMembers.append("  on\(capitalizedName): (listener: (data: \(eventType)) => void) => () => void")
            }

            if !interfaceMembers.isEmpty {
                outputParts.append("""
                export interface \(typeInfo.name) {
                \(interfaceMembers.joined(separator: "\n"))
                }
                """)
            }
        }

        // Generate global declarations
        let hasJsbTypes = !allJsBridgeTypes.isEmpty
        let hasEvents = allJsBridgeTypes.contains { !$0.events.isEmpty }

        if hasJsbTypes {
            var jsbMembers: [String] = []
            jsbMembers.append(contentsOf: allJsBridgeTypes.map { "\($0.name): \($0.name)" })

            var windowMembers: [String] = []
            windowMembers.append("""
                jsb: {
                  \(jsbMembers.joined(separator: "\n      "))
                }
            """)

            // jsbEvents is internal, used by Swift to emit events
            if hasEvents {
                windowMembers.append("""
                    jsbEvents: {
                      emit: (event: string, data: unknown) => void
                    }
                """)
            }

            outputParts.append("""
            declare global {
              interface Window {
            \(windowMembers.joined(separator: "\n"))
              }
            }
            """)
        }

        let output = outputParts.joined(separator: "\n\n")
        try output.write(toFile: outputFile, atomically: true, encoding: .utf8)

        print("\nFound \(totalCount) types total:")
        for typeInfo in allJsBridgeDataTypes {
            print("  - \(typeInfo.name) (@JSBridgeType, \(typeInfo.properties.count) properties)")
        }
        for typeInfo in allJsBridgeTypes {
            let methodsDesc = typeInfo.methods.isEmpty ? "" : "\(typeInfo.methods.count) methods"
            let eventsDesc = typeInfo.events.isEmpty ? "" : "\(typeInfo.events.count) events"
            let parts = [methodsDesc, eventsDesc].filter { !$0.isEmpty }
            print("  - \(typeInfo.name) (@JSBridge, \(parts.joined(separator: ", ")))")
        }
        print("Output written to: \(outputFile)")

        let elapsed = Date().timeIntervalSince(startTime)
        print("Total time: \(String(format: "%.2f", elapsed * 1000))ms")
    }

    static func findSwiftFiles(in directory: String) -> [String] {
        var swiftFiles: [String] = []
        let fileManager = FileManager.default

        guard let enumerator = fileManager.enumerator(atPath: directory) else {
            return swiftFiles
        }

        while let file = enumerator.nextObject() as? String {
            if file.hasSuffix(".swift") {
                let fullPath = (directory as NSString).appendingPathComponent(file)
                swiftFiles.append(fullPath)
            }
        }

        return swiftFiles.sorted()
    }

    static func printUsage() {
        fputs("Usage: JSBridgeBuildTool <search_path> -o <output_file>\n", stderr)
    }
}

// MARK: - Type Information

struct JSBridgeTypeInfo {
    let name: String
    let methods: [FunctionDefinition] // Regular methods (JS → Swift)
    let events: [EventDefinition] // @EmitEvent methods (Swift → JS)
}

struct JSBridgeDataTypeInfo {
    let name: String
    let properties: [PropertyDefinition]

    func toTypeScript() -> String {
        let propertyDefinitions = properties.map { prop in
            "  \(prop.name)\(prop.isOptional ? "?" : ""): \(prop.tsType)"
        }.joined(separator: "\n")

        return """
        export interface \(name) {
        \(propertyDefinitions)
        }
        """
    }
}

struct EventDefinition {
    let name: String
    let parameters: FunctionParameterListSyntax

    init(_ from: FunctionDeclSyntax) {
        name = from.name.text
        parameters = from.signature.parameterClause.parameters
    }

    func tsEventType() -> String {
        if parameters.count == 0 {
            return "void"
        } else if parameters.count == 1 {
            return swiftTypeToTsType(type: parameters.first!.type)
        } else {
            // Multiple params as tuple
            let types = parameters.map { swiftTypeToTsType(type: $0.type) }
            return "[\(types.joined(separator: ", "))]"
        }
    }
}

struct PropertyDefinition {
    let name: String
    let tsType: String
    let isOptional: Bool

    init(_ from: VariableDeclSyntax, typeAliases: [String: String] = [:]) {
        // Get the first binding (e.g., `let name: String`)
        let binding = from.bindings.first!
        let pattern = binding.pattern

        // Extract name
        if let identifier = pattern.as(IdentifierPatternSyntax.self) {
            name = identifier.identifier.text
        } else {
            name = pattern.description.trimmingCharacters(in: .whitespaces)
        }

        // Extract type
        if let typeAnnotation = binding.typeAnnotation {
            let type = typeAnnotation.type
            if let optional = type.as(OptionalTypeSyntax.self) {
                tsType = swiftTypeToTsType(type: optional.wrappedType, typeAliases: typeAliases)
                isOptional = true
            } else {
                tsType = swiftTypeToTsType(type: type, typeAliases: typeAliases)
                isOptional = false
            }
        } else {
            tsType = "any"
            isOptional = false
        }
    }
}

struct FunctionDefinition {
    let name: String
    let parameters: FunctionParameterListSyntax
    let returnType: TypeSyntax?
    let isAsync: Bool
    let isThrowing: Bool

    init(_ from: FunctionDeclSyntax) {
        name = from.name.text
        parameters = from.signature.parameterClause.parameters
        returnType = from.signature.returnClause?.type
        isAsync = from.signature.effectSpecifiers?.asyncSpecifier != nil
        isThrowing = from.signature.effectSpecifiers?.throwsClause != nil
    }

    func tsFunction() -> String {
        let tsParameters = parameters.map {
            let hasDefaultValue = $0.defaultValue != nil
            let isUnnamed = $0.firstName.text == "_"
            return "\(isUnnamed ? $0.secondName?.text ?? "_" : $0.firstName.text)\(hasDefaultValue ? "?" : ""): \(swiftTypeToTsType(type: $0.type))"
        }.joined(separator: ", ")
        let tsReturnType = returnType.map { swiftTypeToTsType(type: $0) } ?? "void"
        let wrappedReturnType = "Promise<\(tsReturnType)>" // All functions return Promise
        return "(\(tsParameters)) => \(wrappedReturnType)"
    }
}

// MARK: - Swift to TypeScript Type Conversion

func swiftTypeToTsType(type: TypeSyntax, typeAliases: [String: String] = [:]) -> String {
    if let array = type.as(ArrayTypeSyntax.self) {
        return "\(swiftTypeToTsType(type: array.element, typeAliases: typeAliases))[]"
    }
    if let dictionary = type.as(DictionaryTypeSyntax.self) {
        return "{[key: \(swiftTypeToTsType(type: dictionary.key, typeAliases: typeAliases))]: \(swiftTypeToTsType(type: dictionary.value, typeAliases: typeAliases))}"
    }
    if let member = type.as(MemberTypeSyntax.self) {
        // e.g., SessionHistoryMessage.Content → SessionHistoryMessageContent
        return swiftTypeToTsType(type: TypeSyntax(member.baseType), typeAliases: typeAliases) + member.name.text
    }
    if let identifier = type.as(IdentifierTypeSyntax.self) {
        if identifier.name.text == "Set",
           let genericArgs = identifier.genericArgumentClause?.arguments,
           let firstArg = genericArgs.first,
           case let .type(argType) = firstArg.argument
        {
            return "\(swiftTypeToTsType(type: argType, typeAliases: typeAliases))[]"
        }
        if let aliased = typeAliases[identifier.name.text] {
            return aliased
        }
        return swiftPrimitiveTypeToTsType(identifier) ?? identifier.name.text
    }
    if let tuple = type.as(TupleTypeSyntax.self) {
        return "[" + tuple.elements.map { swiftTypeToTsType(type: $0.type, typeAliases: typeAliases) }.joined(separator: ", ") + "]"
    }
    if let optional = type.as(OptionalTypeSyntax.self) {
        return "\(swiftTypeToTsType(type: optional.wrappedType, typeAliases: typeAliases)) | undefined | null"
    }
    return type.description.trimmingCharacters(in: .whitespaces)
}

func swiftPrimitiveTypeToTsType(_ type: IdentifierTypeSyntax) -> String? {
    switch type.name.text {
    case "String", "UUID", "Date":
        "string"
    case "Int", "Int64", "Int32", "Int16", "Int8",
         "UInt64", "UInt32", "UInt16", "UInt8", "UInt",
         "Double", "Float", "CGFloat":
        "number"
    case "Bool":
        "boolean"
    case "Void":
        "void"
    case "Any":
        "any"
    default:
        nil
    }
}

// MARK: - Syntax Visitor

class JSBridgeVisitor: SyntaxVisitor {
    var jsBridgeTypes: [JSBridgeTypeInfo] = []
    var jsBridgeDataTypes: [JSBridgeDataTypeInfo] = []
    private var parentNameStack: [String] = []
    private var nestedTypeAliasStack: [[String: String]] = []

    private func qualifiedName(_ name: String) -> String {
        parentNameStack.joined() + name
    }

    private var currentTypeAliases: [String: String] {
        nestedTypeAliasStack.last ?? [:]
    }

    /// Scan a type's member block for nested @JSBridgeType structs and build short→qualified name map.
    private func collectNestedTypeAliases(from memberBlock: MemberBlockSyntax, parentQualifiedName: String) -> [String: String] {
        var aliases: [String: String] = [:]
        for member in memberBlock.members {
            guard let structDecl = member.decl.as(StructDeclSyntax.self),
                  hasAttribute(structDecl.attributes, named: "JSBridgeType") else { continue }
            aliases[structDecl.name.text] = parentQualifiedName + structDecl.name.text
        }
        return aliases
    }

    override func visit(_ node: StructDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let qName = qualifiedName(name)
        let nestedAliases = collectNestedTypeAliases(from: node.memberBlock, parentQualifiedName: qName)

        if hasAttribute(node.attributes, named: "JSBridge") {
            let methods = extractMethods(from: node.memberBlock)
            let events = extractEvents(from: node.memberBlock)
            jsBridgeTypes.append(JSBridgeTypeInfo(name: qName, methods: methods, events: events))
        }
        if hasAttribute(node.attributes, named: "JSBridgeType") {
            let combinedAliases = currentTypeAliases.merging(nestedAliases) { _, new in new }
            let properties = extractProperties(from: node.memberBlock, typeAliases: combinedAliases)
            jsBridgeDataTypes.append(JSBridgeDataTypeInfo(name: qName, properties: properties))
        }

        parentNameStack.append(name)
        nestedTypeAliasStack.append(nestedAliases)
        return .visitChildren
    }

    override func visitPost(_: StructDeclSyntax) {
        parentNameStack.removeLast()
        nestedTypeAliasStack.removeLast()
    }

    override func visit(_ node: ClassDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let qName = qualifiedName(name)
        let nestedAliases = collectNestedTypeAliases(from: node.memberBlock, parentQualifiedName: qName)

        if hasAttribute(node.attributes, named: "JSBridge") {
            let methods = extractMethods(from: node.memberBlock)
            let events = extractEvents(from: node.memberBlock)
            jsBridgeTypes.append(JSBridgeTypeInfo(name: qName, methods: methods, events: events))
        }

        parentNameStack.append(name)
        nestedTypeAliasStack.append(nestedAliases)
        return .visitChildren
    }

    override func visitPost(_: ClassDeclSyntax) {
        parentNameStack.removeLast()
        nestedTypeAliasStack.removeLast()
    }

    override func visit(_ node: EnumDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let qName = qualifiedName(name)
        let nestedAliases = collectNestedTypeAliases(from: node.memberBlock, parentQualifiedName: qName)

        if hasAttribute(node.attributes, named: "JSBridge") {
            let methods = extractMethods(from: node.memberBlock)
            let events = extractEvents(from: node.memberBlock)
            jsBridgeTypes.append(JSBridgeTypeInfo(name: qName, methods: methods, events: events))
        }

        parentNameStack.append(name)
        nestedTypeAliasStack.append(nestedAliases)
        return .visitChildren
    }

    override func visitPost(_: EnumDeclSyntax) {
        parentNameStack.removeLast()
        nestedTypeAliasStack.removeLast()
    }

    override func visit(_ node: ActorDeclSyntax) -> SyntaxVisitorContinueKind {
        let name = node.name.text
        let qName = qualifiedName(name)
        let nestedAliases = collectNestedTypeAliases(from: node.memberBlock, parentQualifiedName: qName)

        if hasAttribute(node.attributes, named: "JSBridge") {
            let methods = extractMethods(from: node.memberBlock)
            let events = extractEvents(from: node.memberBlock)
            jsBridgeTypes.append(JSBridgeTypeInfo(name: qName, methods: methods, events: events))
        }

        parentNameStack.append(name)
        nestedTypeAliasStack.append(nestedAliases)
        return .visitChildren
    }

    override func visitPost(_: ActorDeclSyntax) {
        parentNameStack.removeLast()
        nestedTypeAliasStack.removeLast()
    }

    private func hasAttribute(_ attributes: AttributeListSyntax, named name: String) -> Bool {
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

    /// Extract regular methods (without @EmitEvent) for @JSBridge types
    private func extractMethods(from memberBlock: MemberBlockSyntax) -> [FunctionDefinition] {
        memberBlock.members.compactMap { member -> FunctionDefinition? in
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else {
                return nil
            }
            // Skip private/fileprivate methods
            let isPrivate = funcDecl.modifiers.contains { modifier in
                modifier.name.text == "private" || modifier.name.text == "fileprivate"
            }
            if isPrivate { return nil }
            // Skip @EmitEvent methods (they are events, not methods)
            if hasAttribute(funcDecl.attributes, named: "EmitEvent") { return nil }
            return FunctionDefinition(funcDecl)
        }
    }

    /// Extract @EmitEvent methods for @JSBridge types
    private func extractEvents(from memberBlock: MemberBlockSyntax) -> [EventDefinition] {
        memberBlock.members.compactMap { member -> EventDefinition? in
            guard let funcDecl = member.decl.as(FunctionDeclSyntax.self) else {
                return nil
            }
            // Skip private/fileprivate methods
            let isPrivate = funcDecl.modifiers.contains { modifier in
                modifier.name.text == "private" || modifier.name.text == "fileprivate"
            }
            if isPrivate { return nil }
            // Only include @EmitEvent methods
            guard hasAttribute(funcDecl.attributes, named: "EmitEvent") else { return nil }
            return EventDefinition(funcDecl)
        }
    }

    private func extractProperties(from memberBlock: MemberBlockSyntax, typeAliases: [String: String] = [:]) -> [PropertyDefinition] {
        memberBlock.members.compactMap { member -> PropertyDefinition? in
            guard let varDecl = member.decl.as(VariableDeclSyntax.self) else {
                return nil
            }
            // Skip private/fileprivate properties
            let isPrivate = varDecl.modifiers.contains { modifier in
                modifier.name.text == "private" || modifier.name.text == "fileprivate"
            }
            if isPrivate {
                return nil
            }
            // Skip computed properties (those without type annotation but with accessors)
            guard let binding = varDecl.bindings.first,
                  binding.typeAnnotation != nil
            else {
                return nil
            }
            // Skip computed properties (shorthand getter or explicit get/set)
            if binding.accessorBlock != nil {
                return nil
            }
            return PropertyDefinition(varDecl, typeAliases: typeAliases)
        }
    }
}

// swiftlint:enable cyclomatic_complexity function_body_length
