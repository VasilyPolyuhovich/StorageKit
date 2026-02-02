import StorageKit
import Foundation

enum AppStorage {
    static let context: StorageKit.Context = {
        do {
            return try StorageKit.start(fileName: "contacts.sqlite") { schema in
                schema.addKVCache()
                schema.add(id: "v1_create_contacts", skipIfTableExists: "contacts") { db in
                    try ContactRecord.createTable(in: db)
                }
            }
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }
    }()

    static var storage: Storage { context.facade }

    /// Initialize storage for testing with isolated temp database
    static func initializeForTesting() throws -> StorageKit.Context {
        let tempDir = FileManager.default.temporaryDirectory
        let testDB = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite")

        return try StorageKit.start(at: testDB, migrations: { schema in
            schema.addKVCache()
            schema.add(id: "v1_create_contacts", skipIfTableExists: "contacts") { db in
                try ContactRecord.createTable(in: db)
            }
        })
    }
}
