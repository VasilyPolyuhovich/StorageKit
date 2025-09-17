import Foundation

public protocol StorageKitEntity: Codable, Sendable, Equatable {
    associatedtype Id: Hashable & Sendable
    var id: Id { get }
}
