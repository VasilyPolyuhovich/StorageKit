import StorageCore

/// Entity with known Record type for simplified API.
///
/// This protocol bridges StorageKitEntity (StorageCore) with StorageKitEntityRecord (StorageGRDB)
/// to enable type inference without specifying record: parameter.
///
/// The @StorageEntity macro automatically generates conformance:
/// ```swift
/// @StorageEntity
/// struct Contact {
///     var id: String
///     var name: String
/// }
///
/// // Generates:
/// extension Contact: RegisteredEntity {
///     public typealias Record = ContactRecord
/// }
/// ```
///
/// This enables simplified API:
/// ```swift
/// try await storage.save(contact)           // infers ContactRecord
/// let c = try await storage.get(Contact.self, id: "1")  // infers ContactRecord
/// ```
public protocol RegisteredEntity: StorageKitEntity {
    associatedtype Record: StorageKitEntityRecord where Record.E == Self
}
