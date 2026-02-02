/// Marks a property to be embedded (flattened) into the parent entity's database table.
///
/// Use this attribute on properties of types conforming to `Embeddable` to store their
/// fields directly in the parent table rather than in a separate table.
///
/// - Parameter prefix: Column name prefix for the embedded fields (default: property name + "_")
///
/// Example:
/// ```swift
/// struct Address: Embeddable {
///     var street: String
///     var city: String
/// }
///
/// @StorageEntity
/// struct User {
///     var id: String
///
///     @StorageEmbedded(prefix: "home_")
///     var homeAddress: Address
///     // Generates columns: home_street, home_city
///
///     @StorageEmbedded  // Uses "workAddress_" as prefix
///     var workAddress: Address
///     // Generates columns: workAddress_street, workAddress_city
/// }
/// ```
///
/// Benefits over separate tables:
/// - No JOINs needed for queries
/// - Can filter/sort on embedded fields
/// - Atomic updates with parent entity
///
/// When to use:
/// - Value objects without their own identity (Address, Money, DateRange)
/// - Data that's always loaded with the parent
/// - Properties that need to be queryable
///
/// When NOT to use:
/// - Entities with their own ID (use `@StorageHasMany`/`@StorageBelongsTo` instead)
/// - Large nested structures (consider separate table)
/// - Data shared between multiple parents
@attached(peer)
public macro StorageEmbedded(prefix: String? = nil) = #externalMacro(
    module: "StorageKitMacrosPlugin",
    type: "StorageEmbeddedMacro"
)
