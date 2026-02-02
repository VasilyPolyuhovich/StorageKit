import StorageKit

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
}
