import Foundation
import Observation
import StorageKit

/// Contact store with SQLite persistence via StorageKit
@Observable
@MainActor
public final class ContactStore {
    public private(set) var contacts: [Contact] = []
    private var observationTask: Task<Void, Never>?

    public init() {
        startObserving()
        Task {
            await addSampleDataIfNeeded()
        }
    }

    // Note: Task cancellation happens automatically when ContactStore is deallocated
    // since observationTask holds a reference to self

    private func startObserving() {
        observationTask = Task {
            let stream = await AppStorage.storage.observeAll(
                Contact.self,
                record: ContactRecord.self,
                orderBy: "name"
            )
            for await updatedContacts in stream {
                self.contacts = updatedContacts
            }
        }
    }

    private func addSampleDataIfNeeded() async {
        let count = try? await AppStorage.storage.count(Contact.self, record: ContactRecord.self)
        guard count == 0 else { return }

        let samples = [
            Contact(name: "John Doe", phone: "+1 555-1234", email: "john@example.com"),
            Contact(name: "Jane Smith", phone: "+1 555-5678", email: "jane@example.com"),
            Contact(name: "Bob Wilson", phone: "+1 555-9999", email: "bob@example.com"),
        ]
        for contact in samples {
            try? await AppStorage.storage.save(contact, record: ContactRecord.self)
        }
    }

    // MARK: - CRUD Operations

    public func add(_ contact: Contact) {
        Task {
            try? await AppStorage.storage.save(contact, record: ContactRecord.self)
        }
    }

    public func update(_ contact: Contact) {
        Task {
            try? await AppStorage.storage.save(contact, record: ContactRecord.self)
        }
    }

    public func delete(id: String) {
        Task {
            try? await AppStorage.storage.delete(Contact.self, id: id, record: ContactRecord.self)
        }
    }

    public func get(id: String) -> Contact? {
        contacts.first { $0.id == id }
    }
}
