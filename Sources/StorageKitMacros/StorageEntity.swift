@_exported import StorageCore
@_exported import StorageGRDB
@_exported import GRDB

/// Macro that transforms a simple struct into a StorageKit entity with auto-generated Record.
///
/// Usage:
/// ```swift
/// @StorageEntity(table: "users")
/// struct User {
///     var id: String
///     var name: String
///     var email: String
/// }
/// ```
///
/// This generates:
/// 1. Conformance to `StorageKitEntity` protocol
/// 2. A companion `UserRecord` struct conforming to GRDB's `FetchableRecord` & `PersistableRecord`
///
/// The Record struct includes:
/// - All properties from the original struct
/// - An `updatedAt: Date` property for tracking
/// - `asEntity()` method to convert back to the entity
/// - `from(_:now:)` static method to create from entity
///
/// Requirements:
/// - Must be applied to a struct
/// - The struct must have an `id` property (any Hashable & Sendable type)
/// - All properties must be Codable and Sendable
@attached(extension, conformances: StorageKitEntity)
@attached(peer, names: suffixed(Record))
public macro StorageEntity(table: String? = nil) = #externalMacro(
    module: "StorageKitMacrosPlugin",
    type: "StorageEntityMacro"
)
