/// Marks a property as a belongs-to relationship with a parent entity.
///
/// The foreign key column is stored in this entity's table.
///
/// - Parameter foreignKey: The column name storing the parent's id.
///   If not specified, uses propertyName + "Id" (e.g., "author" → "authorId")
///
/// Example:
/// ```swift
/// @StorageEntity
/// struct Post {
///     var id: String
///     var title: String
///     var authorId: String  // Foreign key (stored in posts table)
///
///     @StorageBelongsTo  // Uses "authorId" as foreignKey
///     var author: User?  // Not stored, lazy loaded
/// }
///
/// // Or with explicit foreign key:
/// @StorageEntity
/// struct Comment {
///     var id: String
///     var text: String
///     var createdBy: String  // Custom foreign key column
///
///     @StorageBelongsTo(foreignKey: "createdBy")
///     var user: User?
/// }
/// ```
///
/// Loading the parent:
/// ```swift
/// let post = try await storage.get(Post.self, id: "1")!
/// let author = try await storage.loadParent(User.self, id: post.authorId)
/// ```
///
/// Note: @StorageBelongsTo properties are NOT stored in the entity's table.
/// Only the foreign key column is stored. The relationship is lazy loaded.
@attached(peer)
public macro StorageBelongsTo(foreignKey: String? = nil) = #externalMacro(
    module: "StorageKitMacrosPlugin",
    type: "StorageBelongsToMacro"
)
