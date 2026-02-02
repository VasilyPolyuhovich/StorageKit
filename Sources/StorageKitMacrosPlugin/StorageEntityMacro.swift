import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftCompilerPlugin

/// Macro that generates StorageKitEntity conformance + companion Record struct.
public struct StorageEntityMacro: ExtensionMacro, PeerMacro {

    // MARK: - ExtensionMacro (adds RegisteredEntity conformance with Record typealias)

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
        guard properties.contains(where: { $0.name == "id" && $0.embedded == nil }) else {
            return []
        }

        let structName = structDecl.name.text
        let recordName = "\(structName)Record"

        // Generate extension with RegisteredEntity conformance and Record typealias
        let ext = try ExtensionDeclSyntax(
            """
            extension \(type.trimmed): RegisteredEntity {
                public typealias Record = \(raw: recordName)
            }
            """
        )
        return [ext]
    }

    // MARK: - Property Extraction

    private static func extractProperties(from structDecl: StructDeclSyntax) -> [PropertyInfo] {
        // First, extract nested structs for @Embedded type resolution
        let nestedStructs = extractNestedStructs(from: structDecl)

        var properties: [PropertyInfo] = []
        for member in structDecl.memberBlock.members {
            guard let varDecl = member.decl.as(VariableDeclSyntax.self),
                  varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
                continue
            }

            // Check for @Embedded attribute
            let embeddedInfo = extractEmbeddedInfo(from: varDecl.attributes)

            for binding in varDecl.bindings {
                guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                      let typeAnnotation = binding.typeAnnotation else {
                    continue
                }

                let propName = identifier.identifier.text
                let typeName = typeAnnotation.type.trimmedDescription

                if let embedded = embeddedInfo {
                    // This is an @Embedded property - look up nested struct
                    let prefix = embedded.prefix ?? (propName + "_")
                    if let nestedStruct = nestedStructs[typeName] {
                        properties.append(PropertyInfo(
                            name: propName,
                            type: typeName,
                            embedded: EmbeddedPropertyInfo(
                                prefix: prefix,
                                nestedProperties: nestedStruct
                            )
                        ))
                    } else {
                        // Nested struct not found in same declaration - treat as unknown type
                        // Could emit a warning here in the future
                        properties.append(PropertyInfo(name: propName, type: typeName, embedded: nil))
                    }
                } else {
                    properties.append(PropertyInfo(name: propName, type: typeName, embedded: nil))
                }
            }
        }
        return properties
    }

    /// Extract nested struct declarations and their properties
    private static func extractNestedStructs(from structDecl: StructDeclSyntax) -> [String: [PropertyInfo]] {
        var result: [String: [PropertyInfo]] = [:]

        for member in structDecl.memberBlock.members {
            guard let nestedStruct = member.decl.as(StructDeclSyntax.self) else {
                continue
            }

            let structName = nestedStruct.name.text
            var props: [PropertyInfo] = []

            for nestedMember in nestedStruct.memberBlock.members {
                guard let varDecl = nestedMember.decl.as(VariableDeclSyntax.self),
                      varDecl.bindingSpecifier.tokenKind == .keyword(.var) else {
                    continue
                }

                for binding in varDecl.bindings {
                    guard let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                          let typeAnnotation = binding.typeAnnotation else {
                        continue
                    }
                    props.append(PropertyInfo(
                        name: identifier.identifier.text,
                        type: typeAnnotation.type.trimmedDescription,
                        embedded: nil
                    ))
                }
            }

            result[structName] = props
        }

        return result
    }

    /// Extract @Embedded attribute info from property attributes
    private static func extractEmbeddedInfo(from attributes: AttributeListSyntax) -> (prefix: String?, found: Bool)? {
        for attr in attributes {
            guard let attribute = attr.as(AttributeSyntax.self),
                  let identifier = attribute.attributeName.as(IdentifierTypeSyntax.self),
                  identifier.name.text == "Embedded" else {
                continue
            }

            // Extract prefix if specified
            let prefix = EmbeddedMacro.extractPrefix(from: attribute)
            return (prefix: prefix, found: true)
        }
        return nil
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

        // Extract stored properties (including embedded info)
        let properties = extractProperties(from: structDecl)

        guard !properties.isEmpty else {
            throw MacroError.noProperties
        }

        // Find the id property (must not be embedded)
        guard properties.contains(where: { $0.name == "id" && $0.embedded == nil }) else {
            throw MacroError.noIdProperty
        }

        // Flatten properties for Record generation
        let flattenedProperties = flattenProperties(properties)

        // Generate record struct
        let recordDecl = try generateRecordDecl(
            recordName: recordName,
            entityName: structName,
            tableName: tableName,
            originalProperties: properties,
            flattenedProperties: flattenedProperties
        )

        return [recordDecl]
    }

    /// Flatten embedded properties into individual columns
    private static func flattenProperties(_ properties: [PropertyInfo]) -> [FlattenedProperty] {
        var result: [FlattenedProperty] = []

        for prop in properties {
            if let embedded = prop.embedded {
                // Expand embedded property into prefixed columns
                for nestedProp in embedded.nestedProperties {
                    result.append(FlattenedProperty(
                        columnName: embedded.prefix + nestedProp.name,
                        type: nestedProp.type,
                        sourcePath: "\(prop.name).\(nestedProp.name)",
                        embeddedIn: prop.name,
                        nestedPropertyName: nestedProp.name
                    ))
                }
            } else {
                // Regular property
                result.append(FlattenedProperty(
                    columnName: prop.name,
                    type: prop.type,
                    sourcePath: prop.name,
                    embeddedIn: nil,
                    nestedPropertyName: nil
                ))
            }
        }

        return result
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
        originalProperties: [PropertyInfo],
        flattenedProperties: [FlattenedProperty]
    ) throws -> DeclSyntax {
        // Build property declarations (flattened)
        let propertyDecls = flattenedProperties.map { prop in
            "public var \(prop.columnName): \(prop.type)"
        }.joined(separator: "\n    ")

        // Build entity initializer - reconstruct nested structs
        let entityInitArgs = generateEntityInitArgs(originalProperties: originalProperties, flattenedProperties: flattenedProperties)

        // Build record initializer arguments from entity - extract from nested structs
        let recordInitArgs = flattenedProperties.map { prop in
            "\(prop.columnName): e.\(prop.sourcePath)"
        }.joined(separator: ", ")

        // Build createTable column definitions
        let columnDefs = generateColumnDefinitions(flattenedProperties: flattenedProperties)

        // Build memberwise initializer parameters
        let initParams = flattenedProperties.map { prop in
            "\(prop.columnName): \(prop.type)"
        }.joined(separator: ", ")

        let initAssignments = flattenedProperties.map { prop in
            "self.\(prop.columnName) = \(prop.columnName)"
        }.joined(separator: "; ")

        let code = """
        public struct \(recordName): StorageKitEntityRecord, Codable {
            public typealias E = \(entityName)
            public static let databaseTableName = "\(tableName)"

            \(propertyDecls)
            public var updatedAt: Date

            public init(\(initParams), updatedAt: Date) {
                \(initAssignments); self.updatedAt = updatedAt
            }

            public func asEntity() -> \(entityName) {
                \(entityName)(\(entityInitArgs))
            }

            public static func from(_ e: \(entityName), now: Date) -> Self {
                Self(\(recordInitArgs), updatedAt: now)
            }

            /// Creates the database table for this record type.
            /// Call this from your migration: `try \(recordName).createTable(in: db)`
            public static func createTable(in db: Database) throws {
                try db.create(table: databaseTableName) { t in
        \(columnDefs)
                    t.column("updatedAt", .datetime).notNull()
                }
            }
        }
        """

        return DeclSyntax(stringLiteral: code)
    }

    /// Generate entity init arguments, reconstructing nested structs
    private static func generateEntityInitArgs(
        originalProperties: [PropertyInfo],
        flattenedProperties: [FlattenedProperty]
    ) -> String {
        originalProperties.map { prop in
            if let embedded = prop.embedded {
                // Reconstruct nested struct from flattened columns
                let nestedArgs = embedded.nestedProperties.map { nestedProp in
                    let columnName = embedded.prefix + nestedProp.name
                    return "\(nestedProp.name): \(columnName)"
                }.joined(separator: ", ")
                return "\(prop.name): \(prop.type)(\(nestedArgs))"
            } else {
                return "\(prop.name): \(prop.name)"
            }
        }.joined(separator: ", ")
    }

    private static func generateColumnDefinitions(flattenedProperties: [FlattenedProperty]) -> String {
        flattenedProperties.map { prop in
            let propInfo = PropertyInfo(name: prop.columnName, type: prop.type, embedded: nil)
            let notNull = prop.columnName == "id" || !propInfo.isOptional
            let primaryKey = prop.columnName == "id"

            var def = "            t.column(\"\(prop.columnName)\", \(propInfo.columnType))"

            if primaryKey {
                def += ".primaryKey()"
            } else if notNull {
                def += ".notNull()"
            }

            return def
        }.joined(separator: "\n")
    }
}

// MARK: - Supporting Types

struct PropertyInfo {
    let name: String
    let type: String
    let embedded: EmbeddedPropertyInfo?

    init(name: String, type: String, embedded: EmbeddedPropertyInfo? = nil) {
        self.name = name
        self.type = type
        self.embedded = embedded
    }

    /// Check if type is optional (handles both `T?` and `Optional<T>` syntax)
    var isOptional: Bool {
        type.hasSuffix("?") || type.hasPrefix("Optional<")
    }

    /// Extract base type without optional wrapper
    var baseType: String {
        if type.hasSuffix("?") {
            return String(type.dropLast())
        }
        if type.hasPrefix("Optional<") && type.hasSuffix(">") {
            return String(type.dropFirst(9).dropLast())
        }
        return type
    }

    /// Maps Swift type to GRDB column type string
    var columnType: String {
        switch baseType {
        case "String", "UUID", "URL":
            return ".text"
        case "Int", "Int64", "Int32", "Int16", "Int8", "UInt", "UInt64", "UInt32", "UInt16", "UInt8":
            return ".integer"
        case "Double", "Float", "CGFloat":
            return ".real"
        case "Bool":
            return ".boolean"
        case "Date":
            return ".datetime"
        case "Data":
            return ".blob"
        default:
            // For custom types or unknown, assume JSON-encoded text
            return ".text"
        }
    }
}

struct EmbeddedPropertyInfo {
    let prefix: String
    let nestedProperties: [PropertyInfo]
}

struct FlattenedProperty {
    let columnName: String
    let type: String
    let sourcePath: String  // e.g., "address.street" or just "name"
    let embeddedIn: String?  // Parent property name if embedded
    let nestedPropertyName: String?  // Property name within nested struct
}

enum MacroError: Error, CustomStringConvertible {
    case notAStruct
    case noProperties
    case noIdProperty
    case embeddedTypeNotFound(String)

    var description: String {
        switch self {
        case .notAStruct:
            return "@StorageEntity can only be applied to structs"
        case .noProperties:
            return "@StorageEntity requires at least one stored property"
        case .noIdProperty:
            return "@StorageEntity requires an 'id' property"
        case .embeddedTypeNotFound(let type):
            return "@Embedded type '\(type)' must be declared as a nested struct within the same entity"
        }
    }
}

@main
struct StorageKitMacrosPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        StorageEntityMacro.self,
        EmbeddedMacro.self,
    ]
}
