import Testing
import Foundation
@testable import ContactBook

@Suite
struct ContactStorageTests {

    @Test("Contact CRUD operations work end-to-end")
    func testContactCRUD() async throws {
        // Initialize storage for tests (in-memory or temp file)
        let context = try AppStorage.initializeForTesting()
        let storage = context.facade

        // Create a contact
        let contact = Contact(
            name: "Test User",
            phone: "+1 555-0000",
            email: "test@example.com"
        )

        // Save (no record: parameter needed!)
        try await storage.save(contact)

        // Fetch by ID
        let fetched: Contact? = try await storage.get(Contact.self, id: contact.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Test User")
        #expect(fetched?.phone == "+1 555-0000")
        #expect(fetched?.email == "test@example.com")

        // Update
        var updated = contact
        updated.name = "Updated User"
        try await storage.save(updated)

        let refetched: Contact? = try await storage.get(Contact.self, id: contact.id)
        #expect(refetched?.name == "Updated User")

        // Count
        let count = try await storage.count(Contact.self)
        #expect(count == 1)

        // Delete
        try await storage.delete(Contact.self, id: contact.id)

        let deleted: Contact? = try await storage.get(Contact.self, id: contact.id)
        #expect(deleted == nil)

        // Count after delete
        let finalCount = try await storage.count(Contact.self)
        #expect(finalCount == 0)
    }

    @Test("Multiple contacts can be fetched")
    func testMultipleContacts() async throws {
        let context = try AppStorage.initializeForTesting()
        let storage = context.facade

        // Add multiple contacts
        let contacts = [
            Contact(name: "Alice", phone: "+1 111-1111", email: "alice@example.com"),
            Contact(name: "Bob", phone: "+2 222-2222", email: "bob@example.com"),
            Contact(name: "Charlie", phone: "+3 333-3333", email: "charlie@example.com"),
        ]

        for contact in contacts {
            try await storage.save(contact)
        }

        // Fetch all
        let allContacts: [Contact] = try await storage.all(Contact.self, orderBy: "name")
        #expect(allContacts.count == 3)
        #expect(allContacts[0].name == "Alice")
        #expect(allContacts[1].name == "Bob")
        #expect(allContacts[2].name == "Charlie")
    }
}
