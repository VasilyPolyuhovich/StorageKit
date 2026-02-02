import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for embedded properties.
///
/// This macro doesn't generate any code itself - it marks properties
/// that should be flattened by `@StorageEntity` macro.
///
/// The prefix is extracted by `StorageEntityMacro` when processing the parent struct.
public struct EmbeddedMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // This macro is a marker only - no code generation
        // The @StorageEntity macro reads @Embedded attributes and handles flattening
        return []
    }

    /// Extract prefix from @Embedded(prefix: "xxx") attribute
    static func extractPrefix(from node: AttributeSyntax) -> String? {
        guard let arguments = node.arguments?.as(LabeledExprListSyntax.self) else {
            return nil
        }

        for arg in arguments {
            if arg.label?.text == "prefix",
               let stringLiteral = arg.expression.as(StringLiteralExprSyntax.self),
               let segment = stringLiteral.segments.first?.as(StringSegmentSyntax.self) {
                return segment.content.text
            }
        }
        return nil
    }
}
