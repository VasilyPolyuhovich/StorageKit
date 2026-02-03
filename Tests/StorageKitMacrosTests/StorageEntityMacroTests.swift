import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

#if canImport(StorageKitMacrosPlugin)
import StorageKitMacrosPlugin

let testMacros: [String: Macro.Type] = [
    "StorageEntity": StorageEntityMacro.self,
    "StorageEmbedded": StorageEmbeddedMacro.self,
    "StorageHasMany": StorageHasManyMacro.self,
    "StorageBelongsTo": StorageBelongsToMacro.self,
    "StorageJSON": StorageJSONMacro.self,
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

            public struct UserRecord: StorageKitEntityRecord, Codable {
                public typealias E = User
                public static let databaseTableName = "users"

                public var id: String
                public var name: String
                public var email: String
                public var updatedAt: Date

                public init(id: String, name: String, email: String, updatedAt: Date) {
                    self.id = id;
                    self.name = name;
                    self.email = email;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> User {
                    User(id: id, name: name, email: email)
                }

                public static func from(_ e: User, now: Date) -> Self {
                    Self(id: e.id, name: e.name, email: e.email, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "name", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "email", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
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

            extension User: RegisteredEntity {
                public typealias Record = UserRecord
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

            public struct TaskRecord: StorageKitEntityRecord, Codable {
                public typealias E = Task
                public static let databaseTableName = "tasks"

                public var id: String
                public var title: String
                public var updatedAt: Date

                public init(id: String, title: String, updatedAt: Date) {
                    self.id = id;
                    self.title = title;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> Task {
                    Task(id: id, title: title)
                }

                public static func from(_ e: Task, now: Date) -> Self {
                    Self(id: e.id, title: e.title, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "title", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
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

            extension Task: RegisteredEntity {
                public typealias Record = TaskRecord
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

            public struct ProfileRecord: StorageKitEntityRecord, Codable {
                public typealias E = Profile
                public static let databaseTableName = "profiles"

                public var id: String
                public var age: Int
                public var score: Double
                public var isActive: Bool
                public var createdAt: Date
                public var avatar: Data?
                public var updatedAt: Date

                public init(id: String, age: Int, score: Double, isActive: Bool, createdAt: Date, avatar: Data?, updatedAt: Date) {
                    self.id = id;
                    self.age = age;
                    self.score = score;
                    self.isActive = isActive;
                    self.createdAt = createdAt;
                    self.avatar = avatar;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> Profile {
                    Profile(id: id, age: age, score: score, isActive: isActive, createdAt: createdAt, avatar: avatar)
                }

                public static func from(_ e: Profile, now: Date) -> Self {
                    Self(id: e.id, age: e.age, score: e.score, isActive: e.isActive, createdAt: e.createdAt, avatar: e.avatar, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "age", type: "INTEGER", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "score", type: "REAL", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "isActive", type: "BOOLEAN", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "createdAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "avatar", type: "BLOB", notNull: false, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
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

            extension Profile: RegisteredEntity {
                public typealias Record = ProfileRecord
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

            public struct ItemRecord: StorageKitEntityRecord, Codable {
                public typealias E = Item
                public static let databaseTableName = "items"

                public var id: String
                public var name: String?
                public var data: Optional<Data>
                public var updatedAt: Date

                public init(id: String, name: String?, data: Optional<Data>, updatedAt: Date) {
                    self.id = id;
                    self.name = name;
                    self.data = data;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> Item {
                    Item(id: id, name: name, data: data)
                }

                public static func from(_ e: Item, now: Date) -> Self {
                    Self(id: e.id, name: e.name, data: e.data, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "name", type: "TEXT", notNull: false, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "data", type: "BLOB", notNull: false, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
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

            extension Item: RegisteredEntity {
                public typealias Record = ItemRecord
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityWithEmbedded() throws {
        #if canImport(StorageKitMacrosPlugin)
        assertMacroExpansion(
            """
            @StorageEntity(table: "users")
            struct User {
                var id: String
                var name: String

                struct Address: Embeddable {
                    var street: String
                    var city: String
                }

                @StorageEmbedded(prefix: "home_")
                var homeAddress: Address
            }
            """,
            expandedSource: """
            struct User {
                var id: String
                var name: String

                struct Address: Embeddable {
                    var street: String
                    var city: String
                }
                var homeAddress: Address
            }

            public struct UserRecord: StorageKitEntityRecord, Codable {
                public typealias E = User
                public static let databaseTableName = "users"

                public var id: String
                public var name: String
                public var home_street: String
                public var home_city: String
                public var updatedAt: Date

                public init(id: String, name: String, home_street: String, home_city: String, updatedAt: Date) {
                    self.id = id;
                    self.name = name;
                    self.home_street = home_street;
                    self.home_city = home_city;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> User {
                    User(id: id, name: name, homeAddress: Address(street: home_street, city: home_city))
                }

                public static func from(_ e: User, now: Date) -> Self {
                    Self(id: e.id, name: e.name, home_street: e.homeAddress.street, home_city: e.homeAddress.city, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "name", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "home_street", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "home_city", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try UserRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("name", .text).notNull()
                        t.column("home_street", .text).notNull()
                        t.column("home_city", .text).notNull()
                        t.column("updatedAt", .datetime).notNull()
                    }
                }
            }

            extension User: RegisteredEntity {
                public typealias Record = UserRecord
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityWithRelations() throws {
        #if canImport(StorageKitMacrosPlugin)
        // Test that @StorageHasMany and @StorageBelongsTo properties are skipped in Record
        // AND that GRDB associations are generated
        assertMacroExpansion(
            """
            @StorageEntity(table: "posts")
            struct Post {
                var id: String
                var title: String
                var authorId: String

                @StorageBelongsTo
                var author: User?

                @StorageHasMany(foreignKey: "postId")
                var comments: [Comment]
            }
            """,
            expandedSource: """
            struct Post {
                var id: String
                var title: String
                var authorId: String
                var author: User?
                var comments: [Comment]
            }

            public struct PostRecord: StorageKitEntityRecord, Codable {
                public typealias E = Post
                public static let databaseTableName = "posts"

                public var id: String
                public var title: String
                public var authorId: String
                public var updatedAt: Date

                public init(id: String, title: String, authorId: String, updatedAt: Date) {
                    self.id = id;
                    self.title = title;
                    self.authorId = authorId;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> Post {
                    Post(id: id, title: title, authorId: authorId)
                }

                public static func from(_ e: Post, now: Date) -> Self {
                    Self(id: e.id, title: e.title, authorId: e.authorId, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "title", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "authorId", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try PostRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("title", .text).notNull()
                        t.column("authorId", .text).notNull()
                        t.column("updatedAt", .datetime).notNull()
                    }
                }

                // MARK: - Associations
                public static let author = belongsTo(UserRecord.self, using: ForeignKey(["authorId"]))
                public static let comments = hasMany(CommentRecord.self, using: ForeignKey(["postId"]))
            }

            extension Post: RegisteredEntity {
                public typealias Record = PostRecord
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityWithExplicitBelongsToForeignKey() throws {
        #if canImport(StorageKitMacrosPlugin)
        // Test @StorageBelongsTo with explicit foreignKey parameter
        assertMacroExpansion(
            """
            @StorageEntity(table: "comments")
            struct Comment {
                var id: String
                var text: String
                var postId: String

                @StorageBelongsTo(foreignKey: "postId")
                var post: Post?
            }
            """,
            expandedSource: """
            struct Comment {
                var id: String
                var text: String
                var postId: String
                var post: Post?
            }

            public struct CommentRecord: StorageKitEntityRecord, Codable {
                public typealias E = Comment
                public static let databaseTableName = "comments"

                public var id: String
                public var text: String
                public var postId: String
                public var updatedAt: Date

                public init(id: String, text: String, postId: String, updatedAt: Date) {
                    self.id = id;
                    self.text = text;
                    self.postId = postId;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> Comment {
                    Comment(id: id, text: text, postId: postId)
                }

                public static func from(_ e: Comment, now: Date) -> Self {
                    Self(id: e.id, text: e.text, postId: e.postId, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "text", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "postId", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try CommentRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("text", .text).notNull()
                        t.column("postId", .text).notNull()
                        t.column("updatedAt", .datetime).notNull()
                    }
                }

                // MARK: - Associations
                public static let post = belongsTo(PostRecord.self, using: ForeignKey(["postId"]))
            }

            extension Comment: RegisteredEntity {
                public typealias Record = CommentRecord
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testStorageEntityWithJSONEncoded() throws {
        #if canImport(StorageKitMacrosPlugin)
        // Test that @StorageJSON properties are stored as TEXT with JSON encoding
        assertMacroExpansion(
            """
            @StorageEntity(table: "products")
            struct Product {
                var id: String
                var name: String

                @StorageJSON
                var attributes: [String: String]
            }
            """,
            expandedSource: """
            struct Product {
                var id: String
                var name: String
                var attributes: [String: String]
            }

            public struct ProductRecord: StorageKitEntityRecord, Codable {
                public typealias E = Product
                public static let databaseTableName = "products"

                public var id: String
                public var name: String
                public var attributes: String
                public var updatedAt: Date

                public init(id: String, name: String, attributes: String, updatedAt: Date) {
                    self.id = id;
                    self.name = name;
                    self.attributes = attributes;
                    self.updatedAt = updatedAt
                }

                public func asEntity() -> Product {
                    Product(id: id, name: name, attributes: try! JSONDecoder().decode([String: String].self, from: attributes.data(using: .utf8)!))
                }

                public static func from(_ e: Product, now: Date) -> Self {
                    Self(id: e.id, name: e.name, attributes: String(data: try! JSONEncoder().encode(e.attributes), encoding: .utf8)!, updatedAt: now)
                }

                /// Schema columns for auto-migration
                public static var schemaColumns: [ColumnSchema] {
                    [
                        ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true, defaultValue: nil),
                        ColumnSchema(name: "name", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "attributes", type: "TEXT", notNull: true, primaryKey: false, defaultValue: nil),
                        ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true, primaryKey: false, defaultValue: nil)
                    ]
                }

                /// Creates the database table for this record type.
                /// Call this from your migration: `try ProductRecord.createTable(in: db)`
                public static func createTable(in db: Database) throws {
                    try db.create(table: databaseTableName) { t in
                        t.column("id", .text).primaryKey()
                        t.column("name", .text).notNull()
                        t.column("attributes", .text).notNull()
                        t.column("updatedAt", .datetime).notNull()
                    }
                }
            }

            extension Product: RegisteredEntity {
                public typealias Record = ProductRecord
            }
            """,
            macros: testMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
