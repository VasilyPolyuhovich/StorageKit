import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for belongs-to relationships.
///
/// This macro doesn't generate any code itself - it marks properties
/// that should be skipped by `@StorageEntity` macro (not stored in this table).
public struct StorageBelongsToMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no code generation
        // StorageEntityMacro reads @StorageBelongsTo and skips these properties
        return []
    }

    /// Extract foreignKey from @StorageBelongsTo(foreignKey: "xxx") attribute
    /// Returns nil if not specified (will default to propertyName + "Id")
    static func extractForeignKey(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        for arg in arguments {
            if arg.label?.text == "foreignKey",
               let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        return nil
    }
}
