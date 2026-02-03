import SwiftUI

/// Edit or create a contact
public struct ContactEditView: View {
    @Environment(\.dismiss) private var dismiss
    let store: ContactStore
    let existingContact: Contact?

    @State private var name: String
    @State private var phone: String
    @State private var email: String
    @State private var notes: String

    public init(contact: Contact? = nil, store: ContactStore) {
        self.store = store
        self.existingContact = contact
        _name = State(initialValue: contact?.name ?? "")
        _phone = State(initialValue: contact?.phone ?? "")
        _email = State(initialValue: contact?.email ?? "")
        _notes = State(initialValue: contact?.notes ?? "")
    }

    private var isEditing: Bool { existingContact != nil }

    public var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                    TextField("Phone", text: $phone)
                        #if os(iOS)
                        .keyboardType(.phonePad)
                        #endif
                    TextField("Email", text: $email)
                        #if os(iOS)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        #endif
                }

                Section("Notes") {
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(isEditing ? "Edit Contact" : "New Contact")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveContact()
                        dismiss()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }

    private func saveContact() {
        if let existing = existingContact {
            // Update existing contact
            var updated = existing
            updated.name = name
            updated.phone = phone
            updated.email = email
            updated.notes = notes
            store.update(updated)
        } else {
            // Create new contact
            let contact = Contact(
                name: name,
                phone: phone,
                email: email,
                notes: notes
            )
            store.add(contact)
        }
    }
}
