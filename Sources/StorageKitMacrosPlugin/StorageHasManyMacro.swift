import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for one-to-many relationships.
///
/// This macro doesn't generate any code itself - it marks properties
/// that should be skipped by `@StorageEntity` macro (not stored in this table).
public struct StorageHasManyMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no code generation
        // StorageEntityMacro reads @StorageHasMany and skips these properties
        return []
    }

    /// Extract foreignKey from @StorageHasMany(foreignKey: "xxx") attribute
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
