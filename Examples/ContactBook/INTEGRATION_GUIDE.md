# Інтеграція StorageKit в ContactBook

Ця інструкція показує як додати persistence до SwiftUI застосунку за допомогою StorageKit.

**Початковий стан:** In-memory ContactStore з масивом контактів
**Кінцевий стан:** SQLite persistence через StorageKit

---

## Крок 1: Додати залежність (1 хв)

**Package.swift:**
```swift
dependencies: [
    .package(path: "../.."),  // StorageKit
],
targets: [
    .target(
        name: "ContactBook",
        dependencies: [
            .product(name: "StorageKit", package: "StorageKit"),
        ]
    ),
]
```

---

## Крок 2: Додати @StorageEntity до моделі (2 хв)

**Contact.swift:**
```swift
import StorageKit  // Додати імпорт

@StorageEntity(table: "contacts")  // Додати макрос
public struct Contact: Identifiable, Hashable, Equatable, Sendable, Codable {
    public var id: String
    public var name: String
    // ... решта без змін
}
```

Макрос автоматично згенерує `ContactRecord` з методами:
- `asEntity()` - конвертація Record → Contact
- `from(_:now:)` - конвертація Contact → Record
- `createTable(in:)` - SQL для створення таблиці

---

## Крок 3: Ініціалізувати StorageKit (3 хв)

**Створити новий файл `StorageSetup.swift`:**
```swift
import StorageKit

enum AppStorage {
    static let context: StorageKit.Context = {
        do {
            return try StorageKit.start(fileName: "contacts.sqlite") { schema in
                schema.addKVCache()
                schema.add(id: "v1_create_contacts", skipIfTableExists: "contacts") { db in
                    try ContactRecord.createTable(in: db)
                }
            }
        } catch {
            fatalError("Failed to initialize storage: \(error)")
        }
    }()

    static var storage: Storage { context.facade }
}
```

---

## Крок 4: Оновити ContactStore (5 хв)

**ContactStore.swift - замінити весь вміст:**
```swift
import Foundation
import Observation
import StorageKit

@Observable
@MainActor
public final class ContactStore {
    public private(set) var contacts: [Contact] = []
    private var observationTask: Task<Void, Never>?

    public init() {
        startObserving()
    }

    deinit {
        observationTask?.cancel()
    }

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
```

---

## Готово!

**Що змінилось:**
- Contact.swift: +2 рядки (import + макрос)
- StorageSetup.swift: новий файл ~20 рядків
- ContactStore.swift: оновлено для async operations

**Що отримали:**
- Дані зберігаються між запусками
- Автоматичне оновлення UI при змінах в базі
- Міграції для схеми бази даних

---

## Опціонально: Sample Data

Якщо база пуста при першому запуску, додайте sample data:

```swift
public init() {
    startObserving()
    Task {
        await addSampleDataIfNeeded()
    }
}

private func addSampleDataIfNeeded() async {
    let count = try? await AppStorage.storage.count(Contact.self, record: ContactRecord.self)
    guard count == 0 else { return }

    let samples = [
        Contact(name: "John Doe", phone: "+1 555-1234", email: "john@example.com"),
        Contact(name: "Jane Smith", phone: "+1 555-5678", email: "jane@example.com"),
    ]
    for contact in samples {
        try? await AppStorage.storage.save(contact, record: ContactRecord.self)
    }
}
```
