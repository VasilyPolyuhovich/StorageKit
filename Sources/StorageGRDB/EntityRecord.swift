import Foundation
@preconcurrency import GRDB
import StorageCore

public protocol StorageKitEntityRecord: FetchableRecord, PersistableRecord, Sendable {
    associatedtype E: StorageKitEntity
    static var databaseTableName: String { get }
    func asEntity() -> E
    static func from(_ e: E, now: Date) -> Self
}
