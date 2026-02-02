import Foundation
@preconcurrency import GRDB
import StorageCore
import StorageGRDB
import StorageRepo

// MARK: - Column Reference

/// Type-safe column reference for building predicates
public struct Column<T>: Sendable {
    public let name: String

    public init(_ name: String) {
        self.name = name
    }

    /// Returns the column name properly quoted for SQL
    var quoted: String {
        // SQLite uses double quotes for identifiers
        // Escape any double quotes in the name by doubling them
        let escaped = name.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }
}

// MARK: - Predicate

/// SQL predicate for WHERE clauses
public struct Predicate: Sendable {
    let sql: String
    let arguments: [DatabaseValue]

    init(sql: String, arguments: [DatabaseValue] = []) {
        self.sql = sql
        self.arguments = arguments
    }
}

// MARK: - Column Operators

// String comparisons
public func == (lhs: Column<String>, rhs: String) -> Predicate {
    Predicate(sql: "\(lhs.quoted) = ?", arguments: [rhs.databaseValue])
}

public func != (lhs: Column<String>, rhs: String) -> Predicate {
    Predicate(sql: "\(lhs.quoted) != ?", arguments: [rhs.databaseValue])
}

// Optional String comparisons
public func == (lhs: Column<String?>, rhs: String?) -> Predicate {
    if let value = rhs {
        return Predicate(sql: "\(lhs.quoted) = ?", arguments: [value.databaseValue])
    } else {
        return Predicate(sql: "\(lhs.quoted) IS NULL")
    }
}

public func != (lhs: Column<String?>, rhs: String?) -> Predicate {
    if let value = rhs {
        return Predicate(sql: "\(lhs.quoted) != ?", arguments: [value.databaseValue])
    } else {
        return Predicate(sql: "\(lhs.quoted) IS NOT NULL")
    }
}

// Int comparisons
public func == (lhs: Column<Int>, rhs: Int) -> Predicate {
    Predicate(sql: "\(lhs.quoted) = ?", arguments: [rhs.databaseValue])
}

public func != (lhs: Column<Int>, rhs: Int) -> Predicate {
    Predicate(sql: "\(lhs.quoted) != ?", arguments: [rhs.databaseValue])
}

public func < (lhs: Column<Int>, rhs: Int) -> Predicate {
    Predicate(sql: "\(lhs.quoted) < ?", arguments: [rhs.databaseValue])
}

public func > (lhs: Column<Int>, rhs: Int) -> Predicate {
    Predicate(sql: "\(lhs.quoted) > ?", arguments: [rhs.databaseValue])
}

public func <= (lhs: Column<Int>, rhs: Int) -> Predicate {
    Predicate(sql: "\(lhs.quoted) <= ?", arguments: [rhs.databaseValue])
}

public func >= (lhs: Column<Int>, rhs: Int) -> Predicate {
    Predicate(sql: "\(lhs.quoted) >= ?", arguments: [rhs.databaseValue])
}

// Double comparisons
public func == (lhs: Column<Double>, rhs: Double) -> Predicate {
    Predicate(sql: "\(lhs.quoted) = ?", arguments: [rhs.databaseValue])
}

public func < (lhs: Column<Double>, rhs: Double) -> Predicate {
    Predicate(sql: "\(lhs.quoted) < ?", arguments: [rhs.databaseValue])
}

public func > (lhs: Column<Double>, rhs: Double) -> Predicate {
    Predicate(sql: "\(lhs.quoted) > ?", arguments: [rhs.databaseValue])
}

public func <= (lhs: Column<Double>, rhs: Double) -> Predicate {
    Predicate(sql: "\(lhs.quoted) <= ?", arguments: [rhs.databaseValue])
}

public func >= (lhs: Column<Double>, rhs: Double) -> Predicate {
    Predicate(sql: "\(lhs.quoted) >= ?", arguments: [rhs.databaseValue])
}

// Bool comparisons
public func == (lhs: Column<Bool>, rhs: Bool) -> Predicate {
    Predicate(sql: "\(lhs.quoted) = ?", arguments: [rhs.databaseValue])
}

// Date comparisons
public func == (lhs: Column<Date>, rhs: Date) -> Predicate {
    Predicate(sql: "\(lhs.quoted) = ?", arguments: [rhs.databaseValue])
}

public func < (lhs: Column<Date>, rhs: Date) -> Predicate {
    Predicate(sql: "\(lhs.quoted) < ?", arguments: [rhs.databaseValue])
}

public func > (lhs: Column<Date>, rhs: Date) -> Predicate {
    Predicate(sql: "\(lhs.quoted) > ?", arguments: [rhs.databaseValue])
}

public func <= (lhs: Column<Date>, rhs: Date) -> Predicate {
    Predicate(sql: "\(lhs.quoted) <= ?", arguments: [rhs.databaseValue])
}

public func >= (lhs: Column<Date>, rhs: Date) -> Predicate {
    Predicate(sql: "\(lhs.quoted) >= ?", arguments: [rhs.databaseValue])
}

// MARK: - Compound Predicates

public func && (lhs: Predicate, rhs: Predicate) -> Predicate {
    Predicate(
        sql: "(\(lhs.sql)) AND (\(rhs.sql))",
        arguments: lhs.arguments + rhs.arguments
    )
}

public func || (lhs: Predicate, rhs: Predicate) -> Predicate {
    Predicate(
        sql: "(\(lhs.sql)) OR (\(rhs.sql))",
        arguments: lhs.arguments + rhs.arguments
    )
}

public prefix func ! (predicate: Predicate) -> Predicate {
    Predicate(sql: "NOT (\(predicate.sql))", arguments: predicate.arguments)
}

// MARK: - String Contains/Like

extension Column where T == String {
    public func contains(_ value: String) -> Predicate {
        Predicate(sql: "\(quoted) LIKE ?", arguments: ["%\(value)%".databaseValue])
    }

    public func hasPrefix(_ value: String) -> Predicate {
        Predicate(sql: "\(quoted) LIKE ?", arguments: ["\(value)%".databaseValue])
    }

    public func hasSuffix(_ value: String) -> Predicate {
        Predicate(sql: "\(quoted) LIKE ?", arguments: ["%\(value)".databaseValue])
    }
}

extension Column where T == String? {
    public func contains(_ value: String) -> Predicate {
        Predicate(sql: "\(quoted) LIKE ?", arguments: ["%\(value)%".databaseValue])
    }

    public func hasPrefix(_ value: String) -> Predicate {
        Predicate(sql: "\(quoted) LIKE ?", arguments: ["\(value)%".databaseValue])
    }

    public func hasSuffix(_ value: String) -> Predicate {
        Predicate(sql: "\(quoted) LIKE ?", arguments: ["%\(value)".databaseValue])
    }

    public var isNull: Predicate {
        Predicate(sql: "\(quoted) IS NULL")
    }

    public var isNotNull: Predicate {
        Predicate(sql: "\(quoted) IS NOT NULL")
    }
}

// MARK: - Sort Order

public enum SortOrder: Sendable {
    case ascending
    case descending
}

public struct OrderBy: Sendable {
    let column: String
    let order: SortOrder
}

// MARK: - Query Builder

/// Type-safe query builder for StorageKit entities
///
/// Usage:
/// ```swift
/// let adults = try await storage.query(User.self)
///     .where { $0.age >= 18 }
///     .orderBy(\.name)
///     .limit(20)
///     .fetch()
/// ```
public struct Query<E: RegisteredEntity>: Sendable {
    private let db: DatabaseActor
    private let config: StorageConfig
    private let predicates: [Predicate]
    private let orders: [OrderBy]
    private let limitValue: Int?
    private let offsetValue: Int

    init(db: DatabaseActor, config: StorageConfig) {
        self.db = db
        self.config = config
        self.predicates = []
        self.orders = []
        self.limitValue = nil
        self.offsetValue = 0
    }

    private init(
        db: DatabaseActor,
        config: StorageConfig,
        predicates: [Predicate],
        orders: [OrderBy],
        limit: Int?,
        offset: Int
    ) {
        self.db = db
        self.config = config
        self.predicates = predicates
        self.orders = orders
        self.limitValue = limit
        self.offsetValue = offset
    }

    // MARK: - Filter

    /// Add a WHERE clause using column references
    ///
    /// ```swift
    /// .where { $0.age >= 18 }
    /// .where { $0.name.contains("John") }
    /// ```
    public func `where`(_ predicate: (ColumnRef<E>) -> Predicate) -> Query<E> {
        let ref = ColumnRef<E>()
        let pred = predicate(ref)
        return Query(
            db: db,
            config: config,
            predicates: predicates + [pred],
            orders: orders,
            limit: limitValue,
            offset: offsetValue
        )
    }

    // MARK: - Order

    /// Order results by column name
    public func orderBy(_ column: String, _ order: SortOrder = .ascending) -> Query<E> {
        Query(
            db: db,
            config: config,
            predicates: predicates,
            orders: orders + [OrderBy(column: column, order: order)],
            limit: limitValue,
            offset: offsetValue
        )
    }

    // MARK: - Pagination

    /// Limit number of results
    public func limit(_ n: Int) -> Query<E> {
        Query(
            db: db,
            config: config,
            predicates: predicates,
            orders: orders,
            limit: n,
            offset: offsetValue
        )
    }

    /// Skip first N results
    public func offset(_ n: Int) -> Query<E> {
        Query(
            db: db,
            config: config,
            predicates: predicates,
            orders: orders,
            limit: limitValue,
            offset: n
        )
    }

    // MARK: - Execute

    /// Fetch all matching entities
    public func fetch() async throws -> [E] {
        try await db.read { db in
            try self.buildRequest().fetchAll(db).map { $0.asEntity() }
        }
    }

    /// Fetch first matching entity
    public func fetchOne() async throws -> E? {
        try await db.read { db in
            try self.buildRequest().fetchOne(db)?.asEntity()
        }
    }

    /// Count matching entities
    public func count() async throws -> Int {
        try await db.read { db in
            try self.buildRequest().fetchCount(db)
        }
    }

    // MARK: - Private

    private func buildRequest() -> QueryInterfaceRequest<E.Record> {
        var request = E.Record.all()

        // Apply predicates
        for predicate in predicates {
            request = request.filter(sql: predicate.sql, arguments: StatementArguments(predicate.arguments))
        }

        // Apply ordering
        for orderBy in orders {
            let column = GRDB.Column(orderBy.column)
            switch orderBy.order {
            case .ascending:
                request = request.order(column.asc)
            case .descending:
                request = request.order(column.desc)
            }
        }

        // Apply limit/offset
        if let limit = limitValue {
            request = request.limit(limit, offset: offsetValue > 0 ? offsetValue : nil)
        }

        return request
    }
}

// MARK: - Column Reference (Dynamic Member Lookup)

/// Provides type-safe column access via dynamic member lookup
@dynamicMemberLookup
public struct ColumnRef<E: RegisteredEntity>: Sendable {
    public init() {}

    public subscript<T>(dynamicMember keyPath: KeyPath<E, T>) -> Column<T> {
        // Extract property name from keyPath
        // Note: This is a simplified implementation using keyPath string description
        // In production, consider generating column metadata in the macro
        let keyPathString = String(describing: keyPath)
        let columnName = extractPropertyName(from: keyPathString)
        return Column<T>(columnName)
    }

    private func extractPropertyName(from keyPathString: String) -> String {
        // KeyPath description format: \Type.propertyName
        // Extract the last component after the dot
        if let lastDot = keyPathString.lastIndex(of: ".") {
            return String(keyPathString[keyPathString.index(after: lastDot)...])
        }
        return keyPathString
    }
}
