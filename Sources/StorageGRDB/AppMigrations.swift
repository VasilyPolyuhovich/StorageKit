import Foundation
@preconcurrency import GRDB
import StorageCore

/// Schema migration builder for StorageKit.
///
/// Supports two migration approaches:
/// 1. **Auto-schema**: Automatically sync entity schemas (CREATE TABLE + ADD COLUMN)
/// 2. **Manual migrations**: Custom SQL for indexes, data transforms, etc.
///
/// Example:
/// ```swift
/// let context = try StorageKit.start { schema in
///     schema.addKVCache()
///
///     // Auto-sync entity schemas
///     schema.autoSchema(
///         UserRecord.self,
///         PostRecord.self
///     )
///
///     // Custom migrations for indexes, data transforms
///     schema.migration("2026-01-15_add_email_index") { db in
///         try db.create(index: "idx_users_email", on: "users", columns: ["email"])
///     }
/// }
/// ```
public struct AppMigrations {

    // MARK: - Options

    public struct Options: Sendable {
        /// Erase database when schema changes (development only!)
        public var eraseDatabaseOnSchemaChange: Bool

        /// Logger for migration events
        public var logger: (@Sendable (String) -> Void)?

        public init(
            eraseDatabaseOnSchemaChange: Bool = false,
            logger: (@Sendable (String) -> Void)? = nil
        ) {
            self.eraseDatabaseOnSchemaChange = eraseDatabaseOnSchemaChange
            self.logger = logger
        }
    }

    // MARK: - Internal Types

    private enum Spec: Sendable {
        case kvCache(String)
        case autoSchema([TableSchema])
        case custom(id: String, skipIfTableExists: String?, body: @Sendable (Database) throws -> Void)
    }

    private var specs: [Spec] = []
    private var options: Options = .init()

    public init() {}

    // MARK: - KV Cache

    /// Add the key-value cache table (required for DiskCache).
    @discardableResult
    public mutating func addKVCache(tableName: String = "kv_cache") -> Self {
        specs.append(.kvCache(tableName))
        return self
    }

    // MARK: - Auto-Schema (Recommended)

    /// Auto-sync entity schemas with the database.
    ///
    /// This automatically:
    /// - Creates tables that don't exist
    /// - Adds columns that are missing
    /// - Does NOT delete columns (for safety)
    ///
    /// The migration is tracked by schema fingerprint - it only runs when schema changes.
    ///
    /// Example:
    /// ```swift
    /// schema.autoSchema(
    ///     UserRecord.self,
    ///     PostRecord.self,
    ///     CommentRecord.self
    /// )
    /// ```
    @discardableResult
    public mutating func autoSchema<each R: StorageKitEntityRecord>(
        _ records: repeat (each R).Type
    ) -> Self {
        var schemas: [TableSchema] = []
        func addSchema<T: StorageKitEntityRecord>(_ type: T.Type) {
            schemas.append(TableSchema.from(type))
        }
        repeat addSchema(each records)
        specs.append(.autoSchema(schemas))
        return self
    }

    // MARK: - Full-Text Search

    /// Add Full-Text Search (FTS5) for a table.
    ///
    /// Creates an FTS5 virtual table with auto-sync triggers.
    /// The FTS table uses external content mode (no data duplication).
    ///
    /// Example:
    /// ```swift
    /// schema.autoSchema(ArticleRecord.self)
    /// schema.addFullTextSearch(
    ///     table: "articles",
    ///     columns: ["title", "content"]
    /// )
    /// ```
    ///
    /// - Parameters:
    ///   - table: Source table name (must exist before FTS)
    ///   - columns: Columns to index for search
    ///   - tokenizer: FTS5 tokenizer (default: "porter" for stemming)
    @discardableResult
    public mutating func addFullTextSearch(
        table: String,
        columns: [String],
        tokenizer: String = "porter"
    ) -> Self {
        let ftsTable = "\(table)_fts"
        let columnList = columns.joined(separator: ", ")
        let newColumnList = columns.map { "new.\($0)" }.joined(separator: ", ")
        let oldColumnList = columns.map { "old.\($0)" }.joined(separator: ", ")

        migration("fts5_\(table)", skipIfTableExists: ftsTable) { db in
            // Create FTS5 virtual table with external content
            try db.execute(sql: """
                CREATE VIRTUAL TABLE "\(ftsTable)" USING fts5(
                    \(columnList),
                    content='\(table)',
                    content_rowid='rowid',
                    tokenize='\(tokenizer)'
                )
            """)

            // Populate FTS from existing data
            try db.execute(sql: """
                INSERT INTO "\(ftsTable)"("\(ftsTable)", rowid, \(columnList))
                SELECT 'rebuild', rowid, \(columnList) FROM "\(table)"
            """)

            // Sync trigger: INSERT
            try db.execute(sql: """
                CREATE TRIGGER "\(table)_fts_ai" AFTER INSERT ON "\(table)" BEGIN
                    INSERT INTO "\(ftsTable)"(rowid, \(columnList))
                    VALUES (new.rowid, \(newColumnList));
                END
            """)

            // Sync trigger: DELETE
            try db.execute(sql: """
                CREATE TRIGGER "\(table)_fts_ad" AFTER DELETE ON "\(table)" BEGIN
                    INSERT INTO "\(ftsTable)"("\(ftsTable)", rowid, \(columnList))
                    VALUES ('delete', old.rowid, \(oldColumnList));
                END
            """)

            // Sync trigger: UPDATE
            try db.execute(sql: """
                CREATE TRIGGER "\(table)_fts_au" AFTER UPDATE ON "\(table)" BEGIN
                    INSERT INTO "\(ftsTable)"("\(ftsTable)", rowid, \(columnList))
                    VALUES ('delete', old.rowid, \(oldColumnList));
                    INSERT INTO "\(ftsTable)"(rowid, \(columnList))
                    VALUES (new.rowid, \(newColumnList));
                END
            """)
        }
        return self
    }

    // MARK: - Manual Migrations

    /// Add a custom migration for complex operations.
    ///
    /// Use this for:
    /// - Creating indexes
    /// - Data transformations
    /// - Complex schema changes
    ///
    /// - Parameters:
    ///   - id: Unique migration identifier (use date prefix: "2026-01-15_description")
    ///   - skipIfTableExists: Skip if table exists (for CREATE migrations)
    ///   - body: Migration code
    @discardableResult
    public mutating func migration(
        _ id: String,
        skipIfTableExists: String? = nil,
        body: @escaping @Sendable (Database) throws -> Void
    ) -> Self {
        specs.append(.custom(id: id, skipIfTableExists: skipIfTableExists, body: body))
        return self
    }

    /// Alias for `migration(_:skipIfTableExists:body:)` for backwards compatibility.
    @discardableResult
    public mutating func add(
        id: String,
        skipIfTableExists: String? = nil,
        body: @escaping @Sendable (Database) throws -> Void
    ) -> Self {
        migration(id, skipIfTableExists: skipIfTableExists, body: body)
    }

    // MARK: - Options

    @discardableResult
    public mutating func setOptions(_ options: Options) -> Self {
        self.options = options
        return self
    }

    // MARK: - Execution

    /// Run all migrations on the database.
    public func run(on writer: any DatabaseWriter) throws {
        var migrator = DatabaseMigrator()
        migrator.eraseDatabaseOnSchemaChange = options.eraseDatabaseOnSchemaChange

        for spec in specs {
            switch spec {
            case .kvCache(let table):
                registerKVCacheMigration(table: table, migrator: &migrator)

            case .autoSchema(let schemas):
                registerAutoSchemaMigration(schemas: schemas, migrator: &migrator)

            case .custom(let id, let skipIfTableExists, let body):
                registerCustomMigration(id: id, skipIfTableExists: skipIfTableExists, body: body, migrator: &migrator)
            }
        }

        do {
            try migrator.migrate(writer)
        } catch {
            let migrationId = (error as NSError).userInfo["migrationIdentifier"] as? String ?? "unknown"
            throw StorageError.migrationFailed(id: migrationId, underlying: error)
        }
    }

    // MARK: - Migration Registration

    private func registerKVCacheMigration(table: String, migrator: inout DatabaseMigrator) {
        let id = "storage_kv_cache_v1:\(table)"
        let log = options.logger

        migrator.registerMigration(id) { db in
            if try !db.tableExists(table) {
                try db.create(table: table) { t in
                    t.column("key", .text).primaryKey()
                    t.column("blob", .blob).notNull()
                    t.column("updatedAt", .datetime).notNull()
                    t.column("expiresAt", .datetime)
                    t.column("size", .integer).notNull().defaults(to: 0)
                }
            }

            // Create indexes if missing
            for (idx, col) in [("idx_\(table)_expiresAt", "expiresAt"), ("idx_\(table)_updatedAt", "updatedAt")] {
                if try !Self.indexExists(idx, in: db) {
                    try db.create(index: idx, on: table, columns: [col])
                }
            }

            log?("[Migration] Applied \(id)")
        }
    }

    private func registerAutoSchemaMigration(schemas: [TableSchema], migrator: inout DatabaseMigrator) {
        // Generate fingerprint from schema content
        let fingerprint = Self.schemaFingerprint(schemas)
        let id = "auto_schema_\(fingerprint)"
        let log = options.logger

        migrator.registerMigration(id) { db in
            let currentSchemas = try SchemaIntrospector.allSchemas(in: db)
            let operations = SchemaDiff.diff(expected: schemas, current: currentSchemas)

            guard !operations.isEmpty else {
                log?("[Migration] Schema up-to-date (\(id))")
                return
            }

            for operation in operations {
                try Self.executeOperation(operation, in: db)

                switch operation {
                case .createTable(let schema):
                    log?("[Migration] Created table '\(schema.name)'")
                case .addColumn(let table, let column):
                    log?("[Migration] Added column '\(column.name)' to '\(table)'")
                }
            }

            log?("[Migration] Applied \(id)")
        }
    }

    private func registerCustomMigration(
        id: String,
        skipIfTableExists: String?,
        body: @escaping @Sendable (Database) throws -> Void,
        migrator: inout DatabaseMigrator
    ) {
        let log = options.logger

        migrator.registerMigration(id) { db in
            if let table = skipIfTableExists, try db.tableExists(table) {
                log?("[Migration] Skipped \(id): table '\(table)' exists")
                return
            }
            try body(db)
            log?("[Migration] Applied \(id)")
        }
    }

    // MARK: - Schema Operations

    private static func executeOperation(_ operation: SchemaOperation, in db: Database) throws {
        switch operation {
        case .createTable(let schema):
            try createTable(schema, in: db)

        case .addColumn(let table, let column):
            try addColumn(column, to: table, in: db)
        }
    }

    private static func createTable(_ schema: TableSchema, in db: Database) throws {
        var columnDefs: [String] = []

        for column in schema.columns {
            var def = "\"\(column.name)\" \(column.type)"

            if column.primaryKey {
                def += " PRIMARY KEY"
            } else if column.notNull {
                def += " NOT NULL"
            }

            if let defaultValue = column.defaultValue {
                def += " DEFAULT \(defaultValue)"
            }

            columnDefs.append(def)
        }

        let sql = """
            CREATE TABLE IF NOT EXISTS "\(schema.name)" (
                \(columnDefs.joined(separator: ",\n    "))
            )
            """

        try db.execute(sql: sql)
    }

    private static func addColumn(_ column: ColumnSchema, to table: String, in db: Database) throws {
        var sql = "ALTER TABLE \"\(table)\" ADD COLUMN \"\(column.name)\" \(column.type)"

        // SQLite requires default for NOT NULL when adding column
        if column.notNull {
            let defaultValue = column.defaultValue ?? defaultValueForType(column.type)
            sql += " NOT NULL DEFAULT \(defaultValue)"
        } else if let defaultValue = column.defaultValue {
            sql += " DEFAULT \(defaultValue)"
        }

        try db.execute(sql: sql)
    }

    private static func defaultValueForType(_ type: String) -> String {
        switch type.uppercased() {
        case "TEXT": return "''"
        case "INTEGER": return "0"
        case "REAL": return "0.0"
        case "BOOLEAN": return "0"
        case "DATETIME": return "CURRENT_TIMESTAMP"
        case "BLOB": return "X''"
        default: return "''"
        }
    }

    // MARK: - Helpers

    /// Generate a stable, deterministic fingerprint for a set of schemas.
    /// Uses DJB2 hash algorithm which is consistent across process restarts.
    private static func schemaFingerprint(_ schemas: [TableSchema]) -> String {
        var parts: [String] = []
        for schema in schemas.sorted(by: { $0.name < $1.name }) {
            let cols = schema.columns
                .sorted(by: { $0.name < $1.name })
                .map { "\($0.name):\($0.type)" }
                .joined(separator: ",")
            parts.append("\(schema.name)[\(cols)]")
        }
        let combined = parts.joined(separator: ";")
        // DJB2 hash - deterministic across process restarts (unlike Swift's Hasher)
        let hash = combined.utf8.reduce(5381) { ($0 &<< 5) &+ $0 &+ Int($1) }
        return String(format: "%08x", abs(hash) & 0xFFFFFFFF)
    }

    private static func indexExists(_ name: String, in db: Database) throws -> Bool {
        try Bool.fetchOne(
            db,
            sql: "SELECT EXISTS(SELECT 1 FROM sqlite_master WHERE type='index' AND name = ?)",
            arguments: [name]
        ) ?? false
    }
}
