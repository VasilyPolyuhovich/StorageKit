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
}
