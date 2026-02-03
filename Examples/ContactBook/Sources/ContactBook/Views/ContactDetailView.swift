import SwiftUI

/// Contact detail view
public struct ContactDetailView: View {
    let contact: Contact
    let store: ContactStore
    @State private var showingEditSheet = false
    @Environment(\.dismiss) private var dismiss

    public init(contact: Contact, store: ContactStore) {
        self.contact = contact
        self.store = store
    }

    public var body: some View {
        List {
            Section {
                if !contact.phone.isEmpty {
                    LabeledContent("Phone", value: contact.phone)
                }
                if !contact.email.isEmpty {
                    LabeledContent("Email", value: contact.email)
                }
            }

            if !contact.notes.isEmpty {
                Section("Notes") {
                    Text(contact.notes)
                }
            }

            Section {
                Button("Delete Contact", role: .destructive) {
                    store.delete(id: contact.id)
                    dismiss()
                }
            }
        }
        .navigationTitle(contact.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") {
                    showingEditSheet = true
                }
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            ContactEditView(contact: contact, store: store)
        }
    }
}
