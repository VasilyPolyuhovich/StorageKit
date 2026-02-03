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

    @Test("AutoMigrate creates tables automatically")
    func testAutoMigrate() async throws {
        // Create a fresh context without any migrations
        let context = try AppStorage.initializeForTesting()

        // Auto-migrate should create the contacts table
        let result = try context.autoMigrate(ContactRecord.self)

        // Table was already created by initializeForTesting, so no operations needed
        // But result should be successful
        #expect(result.success)

        // Verify we can still use the storage after autoMigrate
        let storage = context.facade
        let contact = Contact(name: "Test", phone: "123", email: "test@test.com")
        try await storage.save(contact)

        let fetched = try await storage.get(Contact.self, id: contact.id)
        #expect(fetched != nil)
        #expect(fetched?.name == "Test")
    }

    @Test("QueryBuilder filters and orders correctly")
    func testQueryBuilder() async throws {
        let context = try AppStorage.initializeForTesting()
        let storage = context.facade

        // Add contacts with various names
        let contacts = [
            Contact(name: "Alice", phone: "+1 111-1111", email: "alice@example.com"),
            Contact(name: "Bob", phone: "+2 222-2222", email: "bob@example.com"),
            Contact(name: "Charlie", phone: "+3 333-3333", email: "charlie@example.com"),
            Contact(name: "Alice Smith", phone: "+4 444-4444", email: "alice.smith@example.com"),
        ]

        for contact in contacts {
            try await storage.save(contact)
        }

        // Test filter with contains
        let aliceContacts = try await storage.query(Contact.self)
            .where { $0.name.contains("Alice") }
            .orderBy("name")
            .fetch()

        #expect(aliceContacts.count == 2)
        #expect(aliceContacts[0].name == "Alice")
        #expect(aliceContacts[1].name == "Alice Smith")

        // Test limit
        let limitedContacts = try await storage.query(Contact.self)
            .orderBy("name")
            .limit(2)
            .fetch()

        #expect(limitedContacts.count == 2)
        #expect(limitedContacts[0].name == "Alice")
        #expect(limitedContacts[1].name == "Alice Smith")

        // Test count
        let totalCount = try await storage.query(Contact.self).count()
        #expect(totalCount == 4)

        // Test fetchOne
        let firstContact = try await storage.query(Contact.self)
            .orderBy("name")
            .fetchOne()

        #expect(firstContact?.name == "Alice")

        // Test descending order
        let descContacts = try await storage.query(Contact.self)
            .orderBy("name", .descending)
            .limit(2)
            .fetch()

        #expect(descContacts[0].name == "Charlie")
        #expect(descContacts[1].name == "Bob")
    }
}
