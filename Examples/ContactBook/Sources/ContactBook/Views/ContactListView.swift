import SwiftUI

/// Main list of contacts
public struct ContactListView: View {
    @State private var store = ContactStore()
    @State private var showingAddSheet = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                ForEach(store.contacts) { contact in
                    NavigationLink(value: contact) {
                        ContactRow(contact: contact)
                    }
                }
                .onDelete(perform: deleteContacts)
            }
            .navigationTitle("Contacts")
            .navigationDestination(for: Contact.self) { contact in
                ContactDetailView(contact: contact, store: store)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                ContactEditView(store: store)
            }
        }
    }

    private func deleteContacts(at offsets: IndexSet) {
        for index in offsets {
            let contact = store.contacts[index]
            store.delete(id: contact.id)
        }
    }
}

struct ContactRow: View {
    let contact: Contact

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(contact.name)
                .font(.headline)
            if !contact.phone.isEmpty {
                Text(contact.phone)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
