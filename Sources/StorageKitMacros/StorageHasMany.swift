/// Marks a property as a one-to-many relationship with another entity.
///
/// The related entities are stored in a separate table with a foreign key
/// pointing back to this entity's id.
///
/// - Parameter foreignKey: The column name in the child table that references this entity's id
///
/// Example:
/// ```swift
/// @StorageEntity
/// struct User {
///     var id: String
///     var name: String
///
///     @StorageHasMany(foreignKey: "authorId")
///     var posts: [Post]  // Not stored in users table
/// }
///
/// @StorageEntity
/// struct Post {
///     var id: String
///     var title: String
///     var authorId: String  // Foreign key to User
///
///     @StorageBelongsTo
///     var author: User?  // Lazy loaded
/// }
/// ```
///
/// Loading related entities:
/// ```swift
/// let user = try await storage.get(User.self, id: "1")!
/// let posts = try await storage.loadChildren(Post.self, where: "authorId", equals: user.id)
/// ```
///
/// Note: @StorageHasMany properties are NOT stored in the entity's table.
/// They represent a virtual relationship loaded from another table.
@attached(peer)
public macro StorageHasMany(foreignKey: String) = #externalMacro(
    module: "StorageKitMacrosPlugin",
    type: "StorageHasManyMacro"
)
