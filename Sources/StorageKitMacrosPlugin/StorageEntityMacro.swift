import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

/// Macro that generates StorageKitEntity conformance + companion Record struct.
public struct StorageEntityMacro: ExtensionMacro, PeerMacro {

    // MARK: - ExtensionMacro (adds StorageKitEntity conformance)

    public static func expansion(
        of node: AttributeSyntax,
        attachedTo declaration: some DeclGroupSyntax,
        providingExtensionsOf type: some TypeSyntaxProtocol,
        conformingTo protocols: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [ExtensionDeclSyntax] {
        // Only generate extension if struct has id property
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            return []
        }
        let properties = extractProperties(from: structDecl)
        guard properties.contains(where: { $0.name == "id" }) else {
            return []
        }

        let ext = try ExtensionDeclSyntax("extension \(type.trimmed): StorageKitEntity {}")
        return [ext]
    }

    private static func extractProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
                continue
            }
            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation else {
                    continue
                }
                properties.append(PropertyInfo(name: identifier.identifier.text, type: typeAnnotation.type.trimmedDescription))
            }
        }
        return properties
    }

    // MARK: - PeerMacro (generates companion Record struct)

    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let structDecl = declaration.as(StructDeclSyntax.self) else {
            throw MacroError.notAStruct
        }

        let structName = structDecl.name.text
        let recordName = "\(structName)Record"

        // Extract table name from attribute
        let tableName = extractTableName(from: node) ?? structName.lowercased() + "s"

        // Extract stored properties
        let properties = extractProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw MacroError.noProperties
        }

        // Find the id property
        guard properties.contains(where: { $0.name == "id" }) else {
            throw MacroError.noIdProperty
        }

        // Generate record struct using DeclSyntax string interpolation
        let recordDecl = try generateRecordDecl(
            recordName: recordName,
            entityName: structName,
            tableName: tableName,
            properties: properties
        )

        return [recordDecl]
    }

    private static func extractTableName(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        for arg in arguments {
            if arg.label?.text == "table",
               let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        return nil
    }

    private static func generateRecordDecl(
        recordName: String,
        entityName: String,
        tableName: String,
        properties: [PropertyInfo]
    ) throws -> DeclSyntax {
        // Build property declarations
        let propertyDecls = properties.map { prop in
            "public var \(prop.name): \(prop.type)"
        }.joined(separator: "\n    ")

        // Build entity initializer arguments
        let entityInitArgs = properties.map { prop in
            "\(prop.name): \(prop.name)"
        }.joined(separator: ", ")

        // Build record initializer arguments from entity
        let recordInitArgs = properties.map { prop in
            "\(prop.name): e.\(prop.name)"
        }.joined(separator: ", ")

        let code = """
        public struct \(recordName): StorageKitEntityRecord {
            public typealias E = \(entityName)
            public static let databaseTableName = "\(tableName)"

            \(propertyDecls)
            public var updatedAt: Date

            public func asEntity() -> \(entityName) {
                \(entityName)(\(entityInitArgs))
            }

            public static func from(_ e: \(entityName), now: Date) -> Self {
                Self(\(recordInitArgs), updatedAt: now)
            }
        }
        """

        return DeclSyntax(stringLiteral: code)
    }
}

struct PropertyInfo {
    let name: String
    let type: String
}

enum MacroError: Error, CustomStringConvertible {
    case notAStruct
    case noProperties
    case noIdProperty

    var description: String {
        switch self {
        case .notAStruct:
            return "@StorageEntity can only be applied to structs"
        case .noProperties:
            return "@StorageEntity requires at least one stored property"
        case .noIdProperty:
            return "@StorageEntity requires an 'id' property"
        }
    }
}

@main
struct StorageKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StorageEntityMacro.self,
    ]
}
