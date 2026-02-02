/// Marker protocol for value objects that can be embedded (flattened) into a parent entity's table.
///
/// Use `@Embedded` attribute on properties of types conforming to `Embeddable` to flatten
/// their fields into the parent table with an optional prefix.
///
/// Example:
/// ```swift
/// struct Address: Embeddable {
///     var street: String
///     var city: String
///     var zip: String
/// }
///
/// @StorageEntity
/// struct User {
///     var id: String
///     var name: String
///
///     @Embedded(prefix: "shipping_")
///     var shippingAddress: Address
///     // Generates columns: shipping_street, shipping_city, shipping_zip
///
///     @Embedded(prefix: "billing_")
///     var billingAddress: Address
///     // Generates columns: billing_street, billing_city, billing_zip
/// }
/// ```
///
/// This allows querying on embedded fields:
/// ```swift
/// let kyivUsers = try await storage.all(User.self, orderBy: "shipping_city")
/// ```
///
/// Requirements:
/// - All properties must be Codable primitive types (String, Int, Date, etc.)
/// - Nested Embeddable types are not supported (only one level of flattening)
public protocol Embeddable: Codable, Sendable, Equatable {}
