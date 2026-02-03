import Foundation
@preconcurrency import GRDB

// MARK: - Schema Types

/// Represents a column in a database table.
public struct ColumnSchema: Sendable, Equatable {
    public let name: String
    public let type: String
    public let notNull: Bool
    public let primaryKey: Bool
    public let defaultValue: String?

    public init(
        name: String,
        type: String,
        notNull: Bool = false,
        primaryKey: Bool = false,
        defaultValue: String? = nil
    ) {
        self.name = name
        self.type = type
        self.notNull = notNull
        self.primaryKey = primaryKey
        self.defaultValue = defaultValue
    }
}

/// Represents a database table schema.
public struct TableSchema: Sendable, Equatable {
    public let name: String
    public let columns: [ColumnSchema]

    public init(name: String, columns: [ColumnSchema]) {
        self.name = name
        self.columns = columns
    }

    public func column(named: String) -> ColumnSchema? {
        columns.first { $0.name == named }
    }
}

// MARK: - Schema Introspector

/// Reads current database schema using SQLite PRAGMA commands.
public struct SchemaIntrospector: Sendable {

    /// Get all table names in the database (excluding system tables).
    public static func tableNames(in db: Database) throws -> [String] {
        let rows = try Row.fetchAll(db, sql: """
            SELECT name FROM sqlite_master
            WHERE type = 'table' AND name NOT LIKE 'sqlite_%' AND name NOT LIKE 'grdb_%'
            ORDER BY name
            """)
        return rows.map { $0["name"] as String }
    }

    /// Get schema for a specific table.
    public static func tableSchema(named tableName: String, in db: Database) throws -> TableSchema? {
        let rows = try Row.fetchAll(db, sql: "PRAGMA table_info(\(tableName))")

        guard !rows.isEmpty else { return nil }

        let columns = rows.map { row -> ColumnSchema in
            ColumnSchema(
                name: row["name"] as String,
                type: (row["type"] as String).uppercased(),
                notNull: (row["notnull"] as Int) == 1,
                primaryKey: (row["pk"] as Int) > 0,
                defaultValue: row["dflt_value"] as String?
            )
        }

        return TableSchema(name: tableName, columns: columns)
    }

    /// Get all table schemas in the database.
    public static func allSchemas(in db: Database) throws -> [TableSchema] {
        let names = try tableNames(in: db)
        return try names.compactMap { try tableSchema(named: $0, in: db) }
    }
}

// MARK: - Schema Diff

/// Represents a schema migration operation.
public enum SchemaOperation: Sendable, Equatable {
    case createTable(TableSchema)
    case addColumn(table: String, column: ColumnSchema)
}

/// Compares schemas and generates migration operations.
public struct SchemaDiff: Sendable {

    /// Compare expected schema with current database schema.
    /// Returns operations needed to migrate from current to expected.
    public static func diff(expected: [TableSchema], current: [TableSchema]) -> [SchemaOperation] {
        var operations: [SchemaOperation] = []

        let currentByName = Dictionary(uniqueKeysWithValues: current.map { ($0.name, $0) })

        for expectedTable in expected {
            if let currentTable = currentByName[expectedTable.name] {
                // Table exists - check for missing columns
                let currentColumnNames = Set(currentTable.columns.map { $0.name })

                for column in expectedTable.columns {
                    if !currentColumnNames.contains(column.name) {
                        operations.append(.addColumn(table: expectedTable.name, column: column))
                    }
                }
            } else {
                // Table doesn't exist - create it
                operations.append(.createTable(expectedTable))
            }
        }

        return operations
    }
}

// MARK: - TableSchema from Record Type

extension TableSchema {
    /// Create TableSchema from a StorageKitEntityRecord type.
    public static func from<R: StorageKitEntityRecord>(_ recordType: R.Type) -> TableSchema {
        TableSchema(
            name: recordType.databaseTableName,
            columns: recordType.schemaColumns
        )
    }
}
