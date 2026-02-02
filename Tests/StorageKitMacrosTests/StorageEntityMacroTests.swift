import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(StorageKitMacrosPlugin)
import StorageKitMacrosPlugin

let testMacros: [String: Macro.Type] = [
    "StorageEntity": StorageEntityMacro.self,
]
#endif

final class StorageEntityMacroTests: XCTestCase {

    func testStorageEntityMacro() throws {
        #if canImport(StorageKitMacrosPlugin)
        assertMacroExpansion(
            """
            @StorageEntity(table: "users")
            struct User {
                var id: String
                var name: String
                var email: String
            }
            """,
            expandedSource: """
            struct User {
                var id: String
                var name: String
                var email: String
            }

            public struct UserRecord: StorageKitEntityRecord {
                public typealias E = User
                public static let databaseTableName = "users"

                public var id: String
                public var name: String
                public var email: String
                public var updatedAt: Date

                public func asEntity() -> User {
                    User(id: id, name: name, email: email)
                }

                public static func from(_ e: User, now: Date) -> Self {
                    Self(id: e.id, name: e.name, email: e.email, updatedAt: now)
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try UserRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("name", .text).notNull()
                        t.column("email", .text).notNull()
                        t.column("updatedAt", .datetime).notNull()
                    }
                }
            }

            extension User: StorageKitEntity {
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityWithDefaultTableName() throws {
        #if canImport(StorageKitMacrosPlugin)
        assertMacroExpansion(
            """
            @StorageEntity()
            struct Task {
                var id: String
                var title: String
            }
            """,
            expandedSource: """
            struct Task {
                var id: String
                var title: String
            }

            public struct TaskRecord: StorageKitEntityRecord {
                public typealias E = Task
                public static let databaseTableName = "tasks"

                public var id: String
                public var title: String
                public var updatedAt: Date

                public func asEntity() -> Task {
                    Task(id: id, title: title)
                }

                public static func from(_ e: Task, now: Date) -> Self {
                    Self(id: e.id, title: e.title, updatedAt: now)
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try TaskRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("title", .text).notNull()
                        t.column("updatedAt", .datetime).notNull()
                    }
                }
            }

            extension Task: StorageKitEntity {
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityRequiresIdProperty() throws {
        #if canImport(StorageKitMacrosPlugin)
        // When no id property exists, the macro throws error and generates nothing
        assertMacroExpansion(
            """
            @StorageEntity(table: "items")
            struct Item {
                var name: String
            }
            """,
            expandedSource: """
            struct Item {
                var name: String
            }
            """,
            diagnostics: [
                DiagnosticSpec(message: "@StorageEntity requires an 'id' property", line: 1, column: 1)
            ],
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityColumnTypeMapping() throws {
        #if canImport(StorageKitMacrosPlugin)
        assertMacroExpansion(
            """
            @StorageEntity(table: "profiles")
            struct Profile {
                var id: String
                var age: Int
                var score: Double
                var isActive: Bool
                var createdAt: Date
                var avatar: Data?
            }
            """,
            expandedSource: """
            struct Profile {
                var id: String
                var age: Int
                var score: Double
                var isActive: Bool
                var createdAt: Date
                var avatar: Data?
            }

            public struct ProfileRecord: StorageKitEntityRecord {
                public typealias E = Profile
                public static let databaseTableName = "profiles"

                public var id: String
                public var age: Int
                public var score: Double
                public var isActive: Bool
                public var createdAt: Date
                public var avatar: Data?
                public var updatedAt: Date

                public func asEntity() -> Profile {
                    Profile(id: id, age: age, score: score, isActive: isActive, createdAt: createdAt, avatar: avatar)
                }

                public static func from(_ e: Profile, now: Date) -> Self {
                    Self(id: e.id, age: e.age, score: e.score, isActive: e.isActive, createdAt: e.createdAt, avatar: e.avatar, updatedAt: now)
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try ProfileRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("age", .integer).notNull()
                        t.column("score", .real).notNull()
                        t.column("isActive", .boolean).notNull()
                        t.column("createdAt", .datetime).notNull()
                        t.column("avatar", .blob)
                        t.column("updatedAt", .datetime).notNull()
                    }
                }
            }

            extension Profile: StorageKitEntity {
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityOptionalSyntax() throws {
        #if canImport(StorageKitMacrosPlugin)
        // Test that both `T?` and `Optional<T>` syntax work correctly
        assertMacroExpansion(
            """
            @StorageEntity(table: "items")
            struct Item {
                var id: String
                var name: String?
                var data: Optional<Data>
            }
            """,
            expandedSource: """
            struct Item {
                var id: String
                var name: String?
                var data: Optional<Data>
            }

            public struct ItemRecord: StorageKitEntityRecord {
                public typealias E = Item
                public static let databaseTableName = "items"

                public var id: String
                public var name: String?
                public var data: Optional<Data>
                public var updatedAt: Date

                public func asEntity() -> Item {
                    Item(id: id, name: name, data: data)
                }

                public static func from(_ e: Item, now: Date) -> Self {
                    Self(id: e.id, name: e.name, data: e.data, updatedAt: now)
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try ItemRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("name", .text)
                        t.column("data", .blob)
                        t.column("updatedAt", .datetime).notNull()
                    }
                }
            }

            extension Item: StorageKitEntity {
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
