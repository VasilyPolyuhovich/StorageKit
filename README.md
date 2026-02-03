# StorageKit — Swift 6 SQLite Storage for SwiftUI

[![StorageKit 2.0.0](https://img.shields.io/badge/StorageKit-2.0.0-purple.svg)](https://github.com/nicklama/StorageKit)
[![Swift 6](https://img.shields.io/badge/Swift-6.0-orange.svg)](https://swift.org)
[![iOS 18+](https://img.shields.io/badge/iOS-18+-blue.svg)](https://developer.apple.com/ios/)
[![GRDB 7.6.1](https://img.shields.io/badge/GRDB-7.6.1-green.svg)](https://github.com/groue/GRDB.swift)

A modern, type-safe storage layer for SwiftUI apps with:

- **Zero boilerplate** — `@StorageEntity` macro generates all persistence code
- **Type-safe queries** — QueryBuilder with compile-time checked predicates
- **Nested structures** — `@StorageEmbedded` flattens value objects, `@StorageHasMany`/`@StorageBelongsTo` for relations
- **Auto-migrations** — Schema changes detected and applied automatically
- **Swift 6 ready** — Full Sendable conformance and actor isolation

---

## Table of Contents

- [Quick Start](#quick-start) — Simple models, default config
- [Basic Usage](#basic-usage) — Relations, filters, observations
- [Advanced Usage](#advanced-usage) — Complex models, embedded structs, auto-migrations
- [API Reference](#api-reference)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)

---

## Quick Start

### 1. Define Your Model

```swift
import StorageKit

@StorageEntity
struct Task {
    var id: String
    var title: String
    var isCompleted: Bool
}
```

The `@StorageEntity` macro generates:
- `TaskRecord` — GRDB record type
- `StorageKitEntity` conformance
- Automatic `updatedAt` timestamp

### 2. Start StorageKit

```swift
// Minimal setup — uses Application Support directory
let context = try StorageKit.start { schema in
    schema.addKVCache()
}
```

### 3. CRUD Operations

```swift
let storage = context.facade

// Create
let task = Task(id: UUID().uuidString, title: "Buy milk", isCompleted: false)
try await storage.save(task)

// Read
let fetched = try await storage.get(Task.self, id: task.id)

// Update
var updated = task
updated.isCompleted = true
try await storage.save(updated)

// Delete
try await storage.delete(Task.self, id: task.id)

// Get all
let allTasks = try await storage.all(Task.self)
```

### 4. Observe Changes (SwiftUI)

```swift
struct TaskListView: View {
    @State private var tasks: [Task] = []
    let storage: Storage

    var body: some View {
        List(tasks) { task in
            Text(task.title)
        }
        .task {
            // No await needed - observe returns AsyncStream directly
            for await items in storage.observeAll(Task.self) {
                tasks = items  // Safe - delivered on MainActor
            }
        }
    }
}
```

---

## Basic Usage

### Models with Relations

StorageKit supports one-to-many relationships with `@StorageHasMany` and `@StorageBelongsTo`:

```swift
@StorageEntity
struct Author {
    var id: String
    var name: String
    var email: String

    @StorageHasMany(foreignKey: "authorId")
    var posts: [Post]  // Not stored in authors table
}

@StorageEntity
struct Post {
    var id: String
    var title: String
    var content: String
    var authorId: String  // Foreign key

    @StorageBelongsTo
    var author: Author?  // Loaded on demand
}
```

**Loading relations:**

```swift
// Load author's posts
let posts = try await storage.loadChildren(
    Post.self,
    where: "authorId",
    equals: author.id
)

// Load post's author
let author = try await storage.loadParent(Author.self, id: post.authorId)
```

**GRDB Associations (Advanced):**

The `@StorageHasMany` and `@StorageBelongsTo` macros automatically generate native GRDB associations on the Record type, enabling JOINs and eager loading:

```swift
// Access the typed repository for GRDB-level queries
let repo = storage.repository(Author.self)

// The generated AuthorRecord has:
//   static let posts = hasMany(PostRecord.self, using: ForeignKey(["authorId"]))
// The generated PostRecord has:
//   static let author = belongsTo(AuthorRecord.self, using: ForeignKey(["authorId"]))
```

### Type-Safe Queries with QueryBuilder

Replace string-based queries with compile-time checked predicates:

```swift
// Filter with predicates
let completedTasks = try await storage.query(Task.self)
    .where { $0.isCompleted == true }
    .fetch()

// Multiple conditions
let urgentTasks = try await storage.query(Task.self)
    .where { $0.isCompleted == false && $0.priority >= 5 }
    .fetch()

// String matching
let searchResults = try await storage.query(Contact.self)
    .where { $0.name.contains("John") }
    .fetch()

// Sorting and pagination
let recentPosts = try await storage.query(Post.self)
    .orderBy("createdAt", .descending)
    .limit(10)
    .offset(20)
    .fetch()

// Count without loading
let activeCount = try await storage.query(Task.self)
    .where { $0.isCompleted == false }
    .count()

// Fetch single item
let firstMatch = try await storage.query(Task.self)
    .where { $0.title.hasPrefix("Important") }
    .fetchOne()
```

**Available predicates:**

| Operator | Example |
|----------|---------|
| `==`, `!=` | `$0.status == "active"` |
| `<`, `>`, `<=`, `>=` | `$0.age >= 18` |
| `&&`, `\|\|` | `$0.isActive && $0.isPremium` |
| `!` | `!$0.isArchived` |
| `.contains()` | `$0.name.contains("test")` |
| `.hasPrefix()` | `$0.email.hasPrefix("admin")` |
| `.hasSuffix()` | `$0.domain.hasSuffix(".com")` |

### Observation

Observations return `AsyncStream` directly (no `await` needed to create):

```swift
// Observe all items
for await tasks in storage.observeAll(Task.self) {
    updateUI(tasks)  // Delivered on MainActor
}

// Observe single item
for await task in storage.observe(Task.self, id: "task-123") {
    updateDetail(task)
}
```

### ContactBook Example

Here's a complete example from the ContactBook demo:

```swift
// Model
@StorageEntity
struct Contact {
    var id: String
    var name: String
    var email: String
    var phone: String
    var isFavorite: Bool
}

// Schema setup with auto-schema
let context = try StorageKit.start { schema in
    schema.addKVCache()
    schema.autoSchema(ContactRecord.self)  // Auto-creates 'contacts' table
}

// Usage
let storage = context.facade

// Get favorites sorted by name
let favorites = try await storage.query(Contact.self)
    .where { $0.isFavorite == true }
    .orderBy("name", .ascending)
    .fetch()

// Search contacts
let matches = try await storage.query(Contact.self)
    .where { $0.name.contains(searchText) || $0.email.contains(searchText) }
    .fetch()
```

---

## Advanced Usage

### Embedded Value Objects

Use `@StorageEmbedded` to flatten nested structs into the parent table:

```swift
// Value object (no ID, no separate table)
struct Address: Codable, Sendable {
    var street: String
    var city: String
    var zip: String
    var country: String
}

struct Money: Codable, Sendable {
    var amount: Decimal
    var currency: String
}

@StorageEntity
struct Customer {
    var id: String
    var name: String
    var email: String

    @StorageEmbedded(prefix: "shipping_")
    var shippingAddress: Address

    @StorageEmbedded(prefix: "billing_")
    var billingAddress: Address
}

@StorageEntity
struct Order {
    var id: String
    var customerId: String
    var status: String

    @StorageEmbedded(prefix: "total_")
    var total: Money

    @StorageEmbedded(prefix: "shipping_")
    var shippingAddress: Address
}
```

**Generated table for Customer:**

```sql
CREATE TABLE customers (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    email TEXT NOT NULL,
    shipping_street TEXT NOT NULL,
    shipping_city TEXT NOT NULL,
    shipping_zip TEXT NOT NULL,
    shipping_country TEXT NOT NULL,
    billing_street TEXT NOT NULL,
    billing_city TEXT NOT NULL,
    billing_zip TEXT NOT NULL,
    billing_country TEXT NOT NULL,
    updatedAt DATETIME NOT NULL
)
```

**Querying embedded fields:**

```swift
// Query on embedded fields works seamlessly
let localCustomers = try await storage.query(Customer.self)
    .where { $0.shippingCity == "Kyiv" }
    .fetch()
```

### JSON-Encoded Dynamic Data

For truly dynamic or unstructured data, use `@StorageJSON`:

```swift
@StorageEntity
struct Product {
    var id: String
    var name: String
    var price: Decimal

    @StorageJSON
    var attributes: [String: String]  // Stored as JSON TEXT

    @StorageJSON
    var tags: [String]
}
```

> ⚠️ **Note:** JSON fields cannot be filtered, indexed, or JOINed. Use sparingly for truly dynamic data.

### Complex Model Example

Combining all features:

```swift
struct ContactInfo: Codable, Sendable {
    var email: String
    var phone: String
    var website: String?
}

struct SocialLinks: Codable, Sendable {
    var twitter: String?
    var linkedin: String?
    var github: String?
}

@StorageEntity
struct Company {
    var id: String
    var name: String
    var industry: String
    var foundedYear: Int
    var isPublic: Bool

    @StorageEmbedded(prefix: "hq_")
    var headquarters: Address

    @StorageEmbedded(prefix: "contact_")
    var contactInfo: ContactInfo

    @StorageEmbedded(prefix: "social_")
    var socialLinks: SocialLinks

    @StorageJSON
    var metadata: [String: String]  // Flexible key-value pairs

    @StorageHasMany(foreignKey: "companyId")
    var employees: [Employee]
}

@StorageEntity
struct Employee {
    var id: String
    var name: String
    var title: String
    var department: String
    var salary: Decimal
    var companyId: String

    @StorageEmbedded(prefix: "")
    var contactInfo: ContactInfo

    @StorageBelongsTo
    var company: Company?
}
```

**Complex queries:**

```swift
// Find tech companies in Kyiv with high-paid engineers
let techCompanies = try await storage.query(Company.self)
    .where { $0.industry == "Technology" && $0.hqCity == "Kyiv" }
    .fetch()

for company in techCompanies {
    let engineers = try await storage.loadChildren(Employee.self, where: "companyId", equals: company.id)
    let highPaid = engineers.filter { $0.salary > 100000 }
    // ...
}
```

### Schema Migrations

StorageKit provides a unified migration API that combines auto-schema detection with manual migrations:

```swift
let context = try StorageKit.start { schema in
    schema.addKVCache()

    // Auto-schema: Creates tables, adds missing columns
    schema.autoSchema(
        UserRecord.self,
        PostRecord.self,
        CommentRecord.self
    )

    // Manual migrations: Indexes, data transforms
    schema.migration("2026-01-15_add_email_index") { db in
        try db.create(index: "idx_users_email", on: "users", columns: ["email"], unique: true)
    }
}
```

**How it works:**
- Auto-schema generates a fingerprint from your Record types
- Migration runs only when the fingerprint changes
- GRDB tracks which migrations have been applied

**What auto-schema handles:**
- ✅ CREATE TABLE for new entities
- ✅ ADD COLUMN for new fields
- ✅ Correct SQLite types (TEXT, INTEGER, REAL, BLOB, DATETIME)
- ✅ Version tracking via schema fingerprint

**What requires manual migration:**
- ❌ DROP COLUMN (data loss prevention)
- ❌ RENAME COLUMN (ambiguous intent)
- ❌ Type changes (requires data conversion)
- ❌ Index creation
- ❌ Data transformations

### Custom Database Location

```swift
// Custom file name in Application Support
let context = try StorageKit.start(
    fileName: "myapp.sqlite",
    cacheTTL: 600,          // 10 minutes
    diskQuota: 50_000_000   // 50 MB
) { schema in
    schema.addKVCache()
}

// Custom URL
let url = FileManager.default
    .urls(for: .documentDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("data.sqlite")

let context = try StorageKit.start(at: url) { schema in
    schema.addKVCache()
}
```

### Manual Migrations

For complex schema changes, use `migration()`:

```swift
let context = try StorageKit.start { schema in
    schema.addKVCache()

    // Auto-schema for your entities
    schema.autoSchema(UserRecord.self)

    // Create index
    schema.migration("2026-01-01_add_user_email_index") { db in
        try db.create(index: "idx_users_email", on: "users", columns: ["email"], unique: true)
    }

    // Data migration
    schema.migration("2026-02-01_normalize_emails") { db in
        try db.execute(sql: "UPDATE users SET email = LOWER(email)")
    }

    // Manual table creation (use skipIfTableExists for CREATE migrations)
    schema.migration("2026-03-01_create_analytics", skipIfTableExists: "analytics") { db in
        try db.create(table: "analytics") { t in
            t.column("id", .text).primaryKey()
            t.column("event", .text).notNull()
            t.column("timestamp", .datetime).notNull()
        }
    }
}
```

### Batch Operations

Efficient bulk operations in single transaction:

```swift
// Save many entities at once (100x faster than loop)
let users = (1...1000).map { User(id: "\($0)", name: "User \($0)") }
try await storage.save(users)  // Single transaction

// Delete all entities of a type
try await storage.deleteAll(User.self)

// Delete with condition
try await storage.deleteAll(User.self, where: "status", equals: "inactive")

// Delete via query builder
try await storage.query(User.self)
    .where { $0.lastLogin < thirtyDaysAgo }
    .deleteAll()
```

### Full-Text Search (FTS5)

Fast text search with SQLite FTS5:

```swift
// 1. Define entity
@StorageEntity
struct Article {
    var id: String
    var title: String
    var content: String
}

// 2. Setup with FTS
let context = try StorageKit.start { schema in
    schema.addKVCache()
    schema.autoSchema(ArticleRecord.self)

    // Add full-text search on title and content
    schema.addFullTextSearch(
        table: "articles",
        columns: ["title", "content"]
    )
}

// 3. Search
let results = try await storage.search(Article.self, query: "swift performance")
for result in results {
    print("\(result.entity.title) - rank: \(result.rank)")
}

// Search with highlighted snippets
let results = try await storage.searchWithSnippets(
    Article.self,
    query: "swift",
    snippetColumn: 1  // content column
)
for result in results {
    print(result.snippet ?? "")  // "...using <b>Swift</b> for..."
}
```

**FTS5 Query Syntax:**
- Simple: `"swift"` — matches "swift" anywhere
- Phrase: `"\"swift programming\""` — exact phrase
- Boolean: `"swift AND performance"`, `"swift OR kotlin"`
- Prefix: `"swi*"` — matches "swift", "swim", etc.
- Column: `"title:swift"` — search only in title

---

## API Reference

### Storage Facade

```swift
public actor Storage {
    // CRUD
    func save<E: RegisteredEntity>(_ entity: E) async throws
    func get<E: RegisteredEntity>(_ type: E.Type, id: String) async throws -> E?
    func delete<E: RegisteredEntity>(_ type: E.Type, id: String) async throws
    func all<E: RegisteredEntity>(_ type: E.Type) async throws -> [E]
    func count<E: RegisteredEntity>(_ type: E.Type) async throws -> Int

    // Queries
    func query<E: RegisteredEntity>(_ type: E.Type) -> Query<E>

    // Relations
    func loadParent<P: RegisteredEntity>(_ type: P.Type, id: String) async throws -> P?
    func loadChildren<C: RegisteredEntity>(_ type: C.Type, where foreignKey: String, equals parentId: String) async throws -> [C]

    // Observation (no await needed)
    func observe<E: RegisteredEntity>(_ type: E.Type, id: String) -> AsyncStream<E?>
    func observeAll<E: RegisteredEntity>(_ type: E.Type) -> AsyncStream<[E]>
}
```

### Query Builder

```swift
public struct Query<E: RegisteredEntity> {
    func `where`(_ predicate: (ColumnRef<E>) -> Predicate) -> Query<E>
    func orderBy(_ column: String, _ order: SortOrder = .ascending) -> Query<E>
    func limit(_ n: Int) -> Query<E>
    func offset(_ n: Int) -> Query<E>
    func fetch() async throws -> [E]
    func fetchOne() async throws -> E?
    func count() async throws -> Int
}
```

### Macros

| Macro | Purpose |
|-------|---------|
| `@StorageEntity` | Generates Record type and persistence code |
| `@StorageEmbedded(prefix:)` | Flattens nested struct into parent table |
| `@StorageHasMany(foreignKey:)` | One-to-many relation; generates `hasMany()` GRDB association |
| `@StorageBelongsTo` | Many-to-one relation; generates `belongsTo()` GRDB association |
| `@StorageJSON` | Stores property as JSON TEXT |

---

## Architecture

### Module Layout

```
StorageKit (facade)
    ├── StorageRepo (GenericRepository, pagination)
    ├── StorageGRDB (DatabaseActor, DiskCache, migrations, AutoMigration)
    └── StorageCore (MemoryCache, KeyBuilder, Clock, StorageConfig)
```

### Entity/Record Pattern

```swift
// Your domain model
@StorageEntity
struct User {
    var id: String
    var name: String
}

// Generated by macro:
struct UserRecord: StorageKitEntityRecord {
    var id: String
    var name: String
    var updatedAt: Date

    static let databaseTableName = "users"

    func asEntity() -> User { ... }
    static func from(_ entity: User, now: Date) -> UserRecord { ... }
}
```

### Cache Flow

```
get(id) →
  1. MemoryCache (LRU, TTL) → hit? return
  2. DiskCache (SQLite KV) → hit? fill RAM, return
  3. Database query → hit? fill caches, return

save(entity) →
  1. Database write
  2. DiskCache set
  3. MemoryCache set
```

### Swift 6 Concurrency

- All public types are `Sendable`
- `Storage` facade wraps thread-safe `DatabaseActor`
- Observations deliver on `MainActor` for UI safety
- `@preconcurrency import GRDB` for GRDB interop

---

## Troubleshooting

### "table already exists"

Use `autoSchema()` or add `skipIfTableExists:` to CREATE migrations:

```swift
// Recommended: autoSchema handles this automatically
schema.autoSchema(UserRecord.self)

// Manual: use skipIfTableExists guard
schema.migration("...", skipIfTableExists: "table_name") { db in
    try db.create(table: "table_name") { ... }
}
```

### "column X already exists"

This happens when you add a property and run both auto-schema and a manual ADD COLUMN migration. Choose one approach:

1. **Auto-schema only** (recommended): Let `autoSchema()` handle new columns
2. **Manual only**: Don't use `autoSchema()`, write explicit migrations
3. **Development reset**: Delete the database file and restart

### Observation not updating UI

Observations deliver on MainActor automatically — no manual dispatching needed:

```swift
// ✅ Correct - values delivered on MainActor
for await items in storage.observeAll(Task.self) {
    self.tasks = items  // Safe for SwiftUI
}
```

Note: `observe()` methods return `AsyncStream` directly — no `await` needed to create the stream.

### Query returns empty for existing data

Check that:
1. Table name matches (default: pluralized lowercase, e.g., `User` → `users`)
2. Column names match property names exactly (case-sensitive)
3. Entity was saved with `storage.save()`, not raw SQL
4. Migration was applied (check with `autoSchema()` or verify table exists)

### Migration runs every app launch

If using `autoSchema()`, ensure schema fingerprint is deterministic. The fingerprint should only change when Record types change. If you see unexpected re-runs:

1. Check that Record types haven't changed
2. Verify no dynamic column names in schemas

---

## Requirements

- iOS 18+
- Swift 6.0
- GRDB 7.6.1

## License

MIT

---

## Contributing

Contributions welcome! Please read the contributing guidelines first.
