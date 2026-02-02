import Foundation

/// Errors thrown by StorageKit operations
public enum StorageError: Error, Sendable {
    // MARK: - Database Errors
    case databaseNotFound(path: String)
    case migrationFailed(id: String, underlying: Error)
    case transactionFailed(underlying: Error)

    // MARK: - Cache Errors
    case cacheReadFailed(key: String, underlying: Error)
    case cacheWriteFailed(key: String, underlying: Error)
    case cacheDecodingFailed(key: String, type: String, underlying: Error)
    case cacheEncodingFailed(key: String, type: String, underlying: Error)

    // MARK: - Entity Errors
    case entityNotFound(type: String, id: String)
    case entityEncodingFailed(type: String, underlying: Error)
    case entityDecodingFailed(type: String, underlying: Error)

    // MARK: - Configuration Errors
    case invalidTableName(String)
    case invalidConfiguration(message: String)

    // MARK: - Query Errors
    case queryFailed(sql: String?, underlying: Error)
}

extension StorageError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .databaseNotFound(let path):
            return "Database not found at path: \(path)"
        case .migrationFailed(let id, let error):
            return "Migration '\(id)' failed: \(error.localizedDescription)"
        case .transactionFailed(let error):
            return "Transaction failed: \(error.localizedDescription)"
        case .cacheReadFailed(let key, let error):
            return "Cache read failed for key '\(key)': \(error.localizedDescription)"
        case .cacheWriteFailed(let key, let error):
            return "Cache write failed for key '\(key)': \(error.localizedDescription)"
        case .cacheDecodingFailed(let key, let type, let error):
            return "Failed to decode \(type) from cache key '\(key)': \(error.localizedDescription)"
        case .cacheEncodingFailed(let key, let type, let error):
            return "Failed to encode \(type) for cache key '\(key)': \(error.localizedDescription)"
        case .entityNotFound(let type, let id):
            return "\(type) with id '\(id)' not found"
        case .entityEncodingFailed(let type, let error):
            return "Failed to encode \(type): \(error.localizedDescription)"
        case .entityDecodingFailed(let type, let error):
            return "Failed to decode \(type): \(error.localizedDescription)"
        case .invalidTableName(let name):
            return "Invalid table name: '\(name)'. Use only alphanumeric characters and underscores."
        case .invalidConfiguration(let message):
            return "Invalid configuration: \(message)"
        case .queryFailed(let sql, let error):
            if let sql {
                return "Query failed (\(sql)): \(error.localizedDescription)"
            }
            return "Query failed: \(error.localizedDescription)"
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .databaseNotFound:
            return "Check if the database file path is correct and accessible."
        case .migrationFailed:
            return "Review the migration code or delete the database and restart."
        case .transactionFailed:
            return "Retry the operation or check for database locks."
        case .cacheReadFailed, .cacheWriteFailed:
            return "This is a non-critical cache error. The operation may still succeed from database."
        case .cacheDecodingFailed, .cacheEncodingFailed:
            return "Check if the model's Codable conformance is correct."
        case .entityNotFound:
            return "Verify the entity ID is correct or check if the entity was deleted."
        case .entityEncodingFailed, .entityDecodingFailed:
            return "Check if all properties are Codable compatible."
        case .invalidTableName:
            return "Use only letters, numbers, and underscores. Start with a letter or underscore."
        case .invalidConfiguration:
            return "Review your StorageKit configuration parameters."
        case .queryFailed:
            return "Check your query syntax and ensure the table/columns exist."
        }
    }
}
