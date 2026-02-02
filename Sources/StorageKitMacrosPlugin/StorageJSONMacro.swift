import SwiftSyntax
import SwiftSyntaxMacros

/// Marker macro for JSON-encoded properties.
///
/// This macro marks properties that should be stored as JSON TEXT.
/// The actual JSON encoding/decoding logic is handled by StorageEntityMacro.
public struct StorageJSONMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Marker only - no code generation
        // StorageEntityMacro reads @StorageJSON and generates appropriate code
        return []
    }
}
