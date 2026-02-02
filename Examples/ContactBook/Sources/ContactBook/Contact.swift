import Foundation
import StorageKit

/// Contact model for the address book
@StorageEntity(table: "contacts")
public struct Contact: Identifiable, Hashable, Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    public var phone: String
    public var email: String
    public var notes: String

    public init(
        id: String = UUID().uuidString,
        name: String = "",
        phone: String = "",
        email: String = "",
        notes: String = ""
    ) {
        self.id = id
        self.name = name
        self.phone = phone
        self.email = email
        self.notes = notes
    }
}
