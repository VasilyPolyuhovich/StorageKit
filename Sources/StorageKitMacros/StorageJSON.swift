/// Marks a property to be stored as JSON-encoded TEXT in the database.
///
/// Use this as an **escape hatch** for truly dynamic or unstructured data.
/// Prefer `@StorageEmbedded` for structured value objects or separate tables for entities.
///
/// **Limitations:**
/// - Cannot filter/search on JSON fields
/// - Cannot index JSON fields
/// - Cannot JOIN on JSON fields
///
/// Example:
/// ```swift
/// @StorageEntity
/// struct Product {
///     var id: String
///     var name: String
///
///     @StorageJSON
///     var attributes: [String: String]  // Dynamic product attributes
/// }
/// ```
///
/// The property type must conform to `Codable`.
@attached(peer)
public macro StorageJSON() = #externalMacro(
    module: "StorageKitMacrosPlugin",
    type: "StorageJSONMacro"
)
