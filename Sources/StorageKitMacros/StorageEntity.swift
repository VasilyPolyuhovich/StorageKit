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
/// 1. Conformance to `RegisteredEntity` protocol (which extends `StorageKitEntity`)
/// 2. A companion `UserRecord` struct conforming to GRDB's `FetchableRecord` & `PersistableRecord`
/// 3. A `Record` typealias pointing to the generated Record struct
///
/// The Record struct includes:
/// - All properties from the original struct
/// - An `updatedAt: Date` property for tracking
/// - `asEntity()` method to convert back to the entity
/// - `from(_:now:)` static method to create from entity
/// - `createTable(in:)` static method for migrations
///
/// ## Migrations
///
/// The generated Record includes a `createTable(in:)` method for easy migrations:
/// ```swift
/// schema.add(id: "2025-01-15_create_users", skipIfTableExists: "users") { db in
///     try UserRecord.createTable(in: db)
/// }
/// ```
///
/// Type mappings:
/// - `String`, `UUID`, `URL` → `.text`
/// - `Int`, `Int64`, etc. → `.integer`
/// - `Double`, `Float` → `.real`
/// - `Bool` → `.boolean`
/// - `Date` → `.datetime`
/// - `Data` → `.blob`
///
/// Requirements:
/// - Must be applied to a struct
/// - The struct must have an `id` property (any Hashable & Sendable type)
/// - All properties must be Codable and Sendable
@attached(extension, conformances: RegisteredEntity, names: named(Record))
@attached(peer, names: suffixed(Record))
public macro StorageEntity(table: String? = nil) = #externalMacro(
    module: "StorageKitMacrosPlugin",
    type: "StorageEntityMacro"
)
