# StorageKit Technical Documentation

**Version:** 1.0
**Swift Version:** 6.0
**Platform Requirements:** iOS 18+, macOS 15+

## Table of Contents

1. [Overview](#1-overview)
2. [Getting Started](#2-getting-started)
3. [Macros Reference](#3-macros-reference)
4. [Storage Facade API](#4-storage-facade-api)
5. [QueryBuilder API](#5-querybuilder-api)
6. [Migrations API](#6-migrations-api)
7. [Repository Layer](#7-repository-layer)
8. [Core Types](#8-core-types)
9. [Observation & Reactivity](#9-observation--reactivity)
10. [Configuration & Advanced](#10-configuration--advanced)

---

## 1. Overview

StorageKit is a Swift 6 concurrency-ready storage layer for SwiftUI apps with GRDB-backed persistence. It provides a type-safe, macro-driven approach to SQLite database management with automatic schema migrations, reactive observations, and multi-layer caching.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────┐
│                     StorageKit                          │
│                    (Facade Layer)                       │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │   Storage    │  │ QueryBuilder │  │  @Macros     │   │
│  │   Facade     │  │   Type-safe  │  │  Code Gen    │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
└────────────┬────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────┐
│                  StorageRepo                            │
│              (Repository Pattern)                       │
│  ┌──────────────────┐  ┌──────────────────┐             │
│  │ GenericRepository│  │  AnyRepository   │             │
│  │  CRUD + Observe  │  │  (Type-erased)   │             │
│  └──────────────────┘  └──────────────────┘             │
└────────────┬────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────┐
│                  StorageGRDB                            │
│               (GRDB Integration)                        │
│  ┌─────────────┐ ┌──────────────┐ ┌─────────────────┐   │
│  │DatabaseActor│ │  DiskCache   │ │ AppMigrations   │   │
│  │ Async I/O   │ │  TTL+Quota   │ │  Auto-schema    │   │
│  └─────────────┘ └──────────────┘ └─────────────────┘   │
│  ┌─────────────────────────────────────────────────┐    │
│  │        ObservationBridge (AsyncStream)          │    │
│  └─────────────────────────────────────────────────┘    │
└────────────┬────────────────────────────────────────────┘
             │
┌────────────▼────────────────────────────────────────────┐
│                  StorageCore                            │
│            (Foundation Layer - No GRDB)                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ MemoryCache  │  │  KeyBuilder  │  │ StorageConfig│   │
│  │  LRU + TTL   │  │  Namespaced  │  │   Settings   │   │
│  └──────────────┘  └──────────────┘  └──────────────┘   │
│  ┌──────────────────────────────────────────────────┐   │
│  │  Entity Protocols: StorageKitEntity, Embeddable  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Module Responsibilities

#### StorageKit (Facade)
- **Primary Entry Point:** `StorageKit.start()` configures and initializes the entire stack
- **Simplified API:** `Storage` class provides convenient CRUD operations
- **Type-safe Queries:** `Query<E>` builder with compile-time safety
- **Macro Exports:** Re-exports `@StorageEntity` and other macros

#### StorageRepo (Repository Pattern)
- **Generic Repository:** `GenericRepository<E, R>` implements full CRUD with caching
- **Type Erasure:** `AnyRepository<E>` for dependency injection scenarios
- **Pagination:** `RepoPage<T>` for cursor-based paging
- **Observation Streams:** Reactive AsyncStream support with MainActor delivery

#### StorageGRDB (GRDB Integration)
- **Database Actor:** `DatabaseActor` wraps `DatabasePool` for async/await read/write
- **Disk Caching:** `DiskCache` implements TTL + quota-based pruning on `kv_cache` table
- **Auto-Migrations:** `AppMigrations` provides migration DSL with fingerprint-based tracking
- **Observation Bridge:** Converts GRDB `ValueObservation` to Swift `AsyncStream`
- **Entity-Record Protocol:** `StorageKitEntityRecord` defines database representation

#### StorageCore (Foundation)
- **Entity Protocol:** `StorageKitEntity` defines domain model requirements
- **Memory Cache:** `MemoryCache` actor implements LRU + TTL eviction
- **Configuration:** `StorageConfig` manages encoder/decoder factories for Swift 6
- **Clock Abstraction:** `Clock` protocol enables testable time-based logic
- **Key Generation:** `KeyBuilder` creates namespaced cache keys

### Key Patterns

**Entity/Record Separation**
- Domain models conform to `StorageKitEntity` (Codable, Sendable, Equatable)
- GRDB records conform to `StorageKitEntityRecord` with `asEntity()`/`from(_:now:)` converters
- `@StorageEntity` macro generates Record type automatically

**Swift 6 Concurrency**
- All GRDB imports use `@preconcurrency import GRDB`
- `StorageContext` is `@unchecked Sendable` (wraps thread-safe `DatabasePool`)
- Config uses encoder/decoder factories instead of shared instances

**Cache Flow**
```
get(id, policy: .localFirst):
  1. MemoryCache.get (actor) → hit? return
  2. DiskCache.get (actor, checks TTL) → hit? fill RAM, return
  3. DatabaseActor.read → hit? fill Disk + RAM, return

put(entity):
  1. DatabaseActor.write
  2. DiskCache.set (with TTL + quota prune)
  3. MemoryCache.set
```

**Observation Pattern**
- GRDB `ValueObservation` converted to Swift `AsyncStream`
- MainActor delivery option for UI-safe updates
- Distinct streams skip duplicate values to reduce UI churn

---

## 2. Getting Started

### Installation

Add StorageKit to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/yourusername/StorageKit.git", from: "2.0.0")
]
```

Then add to your target:

```swift
.target(
    name: "YourApp",
    dependencies: ["StorageKit"]
)
```

### Minimal Working Example

```swift
import StorageKit
import Foundation

// 1. Define your entity with @StorageEntity macro
@StorageEntity
struct User {
    var id: String
    var name: String
    var email: String
}

// 2. Initialize StorageKit
let context = try StorageKit.start { schema in
    schema.addKVCache()
    schema.autoSchema(UserRecord.self)  // Auto-sync schema
}

let storage = context.facade

// 3. Perform CRUD operations
let user = User(id: UUID().uuidString, name: "Alice", email: "alice@example.com")
try await storage.save(user)

// 4. Retrieve data
if let retrieved = try await storage.get(User.self, id: user.id) {
    print("Found user: \(retrieved.name)")
}

// 5. Observe changes (MainActor delivery for SwiftUI)
for await users in storage.observeAll(User.self, orderBy: "name") {
    print("Users updated: \(users.count)")
}
```

### SwiftUI Integration

```swift
import SwiftUI
import StorageKit
import Observation

@Observable
@MainActor
final class UserStore {
    private(set) var users: [User] = []
    private var observationTask: Task<Void, Never>?

    init() {
        observationTask = Task {
            let stream = await AppStorage.storage.observeAll(User.self, orderBy: "name")
            for await updatedUsers in stream {
                self.users = updatedUsers
            }
        }
    }
}

struct UserListView: View {
    @State private var store = UserStore()

    var body: some View {
        List(store.users) { user in
            Text(user.name)
        }
    }
}
```

---

## 3. Macros Reference

StorageKit provides five macros for code generation. All macros are automatically available when you `import StorageKit`.

### 3.1. @StorageEntity

**Declaration:**
```swift
@attached(extension, conformances: RegisteredEntity, names: named(Record))
@attached(peer, names: suffixed(Record))
public macro StorageEntity(table: String? = nil)
```

**Description:**
Transforms a struct into a StorageKit entity by generating a companion Record type that conforms to GRDB's `FetchableRecord` and `PersistableRecord`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `table` | `String?` | `nil` | Custom table name. If `nil`, uses lowercased struct name with 's' appended (e.g., `User` → `"users"`) |

**Requirements:**
- Must be applied to a `struct`
- Struct must have an `id` property of any `Hashable & Sendable` type
- All properties must be `Codable` and `Sendable`
- Struct should conform to `Codable`, `Sendable`, `Equatable`

**Generated Code:**

The macro generates:

1. **RegisteredEntity conformance:**
```swift
extension User: RegisteredEntity {
    public typealias Record = UserRecord
}
```

2. **Companion Record struct:**
```swift
public struct UserRecord: StorageKitEntityRecord, FetchableRecord, PersistableRecord, Sendable {
    public typealias E = User

    public var id: String
    public var name: String
    public var email: String
    public var updatedAt: Date

    public static let databaseTableName = "users"

    public func asEntity() -> User {
        User(id: id, name: name, email: email)
    }

    public static func from(_ entity: User, now: Date) -> UserRecord {
        UserRecord(
            id: entity.id,
            name: entity.name,
            email: entity.email,
            updatedAt: now
        )
    }

    public static var schemaColumns: [ColumnSchema] {
        [
            ColumnSchema(name: "id", type: "TEXT", notNull: true, primaryKey: true),
            ColumnSchema(name: "name", type: "TEXT", notNull: true),
            ColumnSchema(name: "email", type: "TEXT", notNull: true),
            ColumnSchema(name: "updatedAt", type: "DATETIME", notNull: true)
        ]
    }

    public static func createTable(in db: Database) throws {
        try db.create(table: databaseTableName) { t in
            t.column("id", .text).primaryKey()
            t.column("name", .text).notNull()
            t.column("email", .text).notNull()
            t.column("updatedAt", .datetime).notNull()
        }
    }
}
```

**Type Mappings:**

| Swift Type | SQL Type | GRDB Column |
|------------|----------|-------------|
| `String`, `UUID`, `URL` | `TEXT` | `.text` |
| `Int`, `Int32`, `Int64` | `INTEGER` | `.integer` |
| `Double`, `Float` | `REAL` | `.real` |
| `Bool` | `BOOLEAN` | `.boolean` |
| `Date` | `DATETIME` | `.datetime` |
| `Data` | `BLOB` | `.blob` |

**Usage Examples:**

```swift
// Basic entity
@StorageEntity
struct Product {
    var id: String
    var name: String
    var price: Double
}

// Custom table name
@StorageEntity(table: "app_users")
struct User {
    var id: String
    var email: String
}

// UUID as ID
@StorageEntity
struct Post {
    var id: UUID  // Works with any Hashable & Sendable type
    var title: String
    var content: String
    var publishedAt: Date?
}
```

**Notes:**
- The `updatedAt` column is automatically added to track modification time
- Records are immutable (all properties are `var` but the struct is value-typed)
- The macro preserves all original properties and only adds the Record companion

---

### 3.2. @StorageEmbedded

**Declaration:**
```swift
@attached(peer)
public macro StorageEmbedded(prefix: String? = nil)
```

**Description:**
Marks a property to be embedded (flattened) into the parent entity's database table. The embedded type's properties become columns in the parent table with an optional prefix.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `prefix` | `String?` | `nil` | Column name prefix for embedded fields. If `nil`, uses property name + `"_"` |

**Requirements:**
- Property type must conform to `Embeddable` protocol
- Embedded type must have only `Codable` primitive properties
- Nested embeddables are not supported (only one level of flattening)

**Usage Examples:**

```swift
// 1. Define embeddable value object
struct Address: Embeddable {
    var street: String
    var city: String
    var zipCode: String
}

// 2. Use in entity with prefix
@StorageEntity
struct User {
    var id: String
    var name: String

    @StorageEmbedded(prefix: "home_")
    var homeAddress: Address
    // Generates columns: home_street, home_city, home_zipCode

    @StorageEmbedded(prefix: "work_")
    var workAddress: Address
    // Generates columns: work_street, work_city, work_zipCode
}

// 3. Default prefix (property name + "_")
@StorageEntity
struct Company {
    var id: String
    var name: String

    @StorageEmbedded  // Uses "headquarters_" as prefix
    var headquarters: Address
    // Generates columns: headquarters_street, headquarters_city, headquarters_zipCode
}
```

**Generated Schema:**

For the `User` example above, the generated table schema includes:

```sql
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    home_street TEXT NOT NULL,
    home_city TEXT NOT NULL,
    home_zipCode TEXT NOT NULL,
    work_street TEXT NOT NULL,
    work_city TEXT NOT NULL,
    work_zipCode TEXT NOT NULL,
    updatedAt DATETIME NOT NULL
)
```

**Querying Embedded Fields:**

```swift
// You can query on embedded fields
let kyivUsers = try await storage.query(User.self)
    .where { Column<String>("home_city") == "Kyiv" }
    .fetch()

// Or use string-based queries
let local = try await storage.all(User.self, orderBy: "work_city")
```

**When to Use:**
- ✅ Value objects without identity (Address, Money, DateRange)
- ✅ Data always loaded with parent
- ✅ Properties that need to be queryable/sortable
- ❌ Entities with their own ID (use `@StorageHasMany` instead)
- ❌ Data shared between multiple parents (use separate table)

---

### 3.3. @StorageHasMany

**Declaration:**
```swift
@attached(peer)
public macro StorageHasMany(foreignKey: String)
```

**Description:**
Marks a property as a one-to-many relationship. The related entities are stored in a separate table with a foreign key column pointing back to the parent entity.

**Parameters:**

| Name | Type | Required | Description |
|------|------|----------|-------------|
| `foreignKey` | `String` | Yes | Column name in the child table that references the parent's `id` |

**Requirements:**
- Property must be an array type `[ChildEntity]`
- Child entity must be a `@StorageEntity` type
- The `foreignKey` column must exist in the child table

**Important:**
Properties marked with `@StorageHasMany` are **NOT stored** in the parent table. They represent a virtual relationship that must be loaded separately.

**Usage Example:**

```swift
@StorageEntity
struct User {
    var id: String
    var name: String

    @StorageHasMany(foreignKey: "authorId")
    var posts: [Post]  // Virtual relationship, not stored
}

@StorageEntity
struct Post {
    var id: String
    var title: String
    var content: String
    var authorId: String  // Foreign key column

    @StorageBelongsTo
    var author: User?  // Inverse relationship
}
```

**Loading Children:**

```swift
// Get parent
let user = try await storage.get(User.self, id: "user-1")!

// Load children using foreignKey
let posts = try await storage.loadChildren(
    Post.self,
    where: "authorId",
    equals: user.id,
    orderBy: "createdAt",
    ascending: false
)

print("User has \(posts.count) posts")
```

**Generated Schema:**

The parent table (`users`) does NOT include the relationship:
```sql
CREATE TABLE users (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    updatedAt DATETIME NOT NULL
)
```

The child table (`posts`) includes the foreign key:
```sql
CREATE TABLE posts (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT NOT NULL,
    authorId TEXT NOT NULL,  -- Foreign key
    updatedAt DATETIME NOT NULL
)
```

**Best Practices:**

```swift
// Create index on foreign key for performance
schema.migration("2026-01-15_add_post_author_index") { db in
    try db.create(index: "idx_posts_authorId", on: "posts", columns: ["authorId"])
}
```

---

### 3.4. @StorageBelongsTo

**Declaration:**
```swift
@attached(peer)
public macro StorageBelongsTo(foreignKey: String? = nil)
```

**Description:**
Marks a property as a belongs-to relationship with a parent entity. The foreign key column is stored in the current entity's table.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `foreignKey` | `String?` | `nil` | Column name storing the parent's ID. If `nil`, uses property name + `"Id"` (e.g., `author` → `"authorId"`) |

**Requirements:**
- Property must be an optional type `ParentEntity?`
- Parent entity must be a `@StorageEntity` type
- The foreign key column must exist in the current entity

**Important:**
Properties marked with `@StorageBelongsTo` are **NOT stored** in the table. Only the foreign key column is stored.

**Usage Examples:**

```swift
// 1. Automatic foreign key name
@StorageEntity
struct Post {
    var id: String
    var title: String
    var authorId: String  // Foreign key column (stored)

    @StorageBelongsTo  // Uses "authorId" as foreign key
    var author: User?  // Not stored, lazy loaded
}

// 2. Explicit foreign key name
@StorageEntity
struct Comment {
    var id: String
    var text: String
    var createdBy: String  // Custom foreign key column name

    @StorageBelongsTo(foreignKey: "createdBy")
    var user: User?  // Not stored
}
```

**Loading Parent:**

```swift
// Get child entity
let post = try await storage.get(Post.self, id: "post-1")!

// Load parent using the foreign key
let author = try await storage.loadParent(User.self, id: post.authorId)

if let author {
    print("Post by \(author.name)")
}
```

**Generated Schema:**

```sql
CREATE TABLE posts (
    id TEXT PRIMARY KEY,
    title TEXT NOT NULL,
    authorId TEXT NOT NULL,  -- Foreign key stored
    updatedAt DATETIME NOT NULL
)
-- Note: 'author' property is NOT a column
```

**Bidirectional Relationships:**

```swift
@StorageEntity
struct User {
    var id: String
    var name: String

    @StorageHasMany(foreignKey: "authorId")
    var posts: [Post]
}

@StorageEntity
struct Post {
    var id: String
    var title: String
    var authorId: String

    @StorageBelongsTo
    var author: User?
}

// Load both directions
let user = try await storage.get(User.self, id: "user-1")!
let userPosts = try await storage.loadChildren(Post.self, where: "authorId", equals: user.id)

let post = try await storage.get(Post.self, id: "post-1")!
let postAuthor = try await storage.loadParent(User.self, id: post.authorId)
```

---

### 3.5. @StorageJSON

**Declaration:**
```swift
@attached(peer)
public macro StorageJSON()
```

**Description:**
Marks a property to be stored as JSON-encoded TEXT in the database. This is an **escape hatch** for truly dynamic or unstructured data.

**Parameters:** None

**Requirements:**
- Property type must conform to `Codable`

**Limitations:**
- ❌ Cannot filter/search on JSON fields
- ❌ Cannot create indexes on JSON fields
- ❌ Cannot JOIN on JSON fields
- ❌ No query optimization

**When to Use:**
- Truly dynamic data with unknown structure
- Metadata dictionaries
- Configuration objects
- **Rare cases** where structure can't be defined upfront

**When NOT to Use:**
- ✅ **Prefer `@StorageEmbedded`** for structured value objects
- ✅ **Prefer separate tables** for entities with identity
- ✅ **Prefer explicit columns** for queryable data

**Usage Examples:**

```swift
@StorageEntity
struct Product {
    var id: String
    var name: String
    var price: Double

    @StorageJSON
    var attributes: [String: String]  // Dynamic product attributes

    @StorageJSON
    var metadata: ProductMetadata  // Complex nested structure
}

struct ProductMetadata: Codable {
    var tags: [String]
    var ratings: [Int]
    var customFields: [String: AnyCodable]
}

// Usage
let product = Product(
    id: UUID().uuidString,
    name: "Laptop",
    price: 999.99,
    attributes: ["color": "silver", "storage": "512GB"],
    metadata: ProductMetadata(tags: ["electronics", "computers"], ratings: [5, 4, 5], customFields: [:])
)

try await storage.save(product)
```

**Generated Schema:**

```sql
CREATE TABLE products (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    price REAL NOT NULL,
    attributes TEXT NOT NULL,  -- JSON-encoded
    metadata TEXT NOT NULL,    -- JSON-encoded
    updatedAt DATETIME NOT NULL
)
```

**JSON Encoding:**

StorageKit uses `JSONEncoder` with `.iso8601` date encoding strategy:

```swift
// The attributes field is stored as:
// {"color":"silver","storage":"512GB"}

// The metadata field is stored as:
// {"tags":["electronics","computers"],"ratings":[5,4,5],"customFields":{}}
```

**Performance Considerations:**

```swift
// ❌ SLOW: Can't filter on JSON fields efficiently
// This requires a full table scan
let products = try await storage.all(Product.self)
let filtered = products.filter { $0.attributes["color"] == "silver" }

// ✅ FAST: Use explicit columns for filterable data
@StorageEntity
struct BetterProduct {
    var id: String
    var name: String
    var color: String  // Explicit column for filtering
    var storage: String

    @StorageJSON
    var extraMetadata: [String: String]?  // Only for truly dynamic data
}

let silverProducts = try await storage.query(BetterProduct.self)
    .where { $0.color == "silver" }
    .fetch()
```

---

## 4. Storage Facade API

The `Storage` class provides a simplified, high-level API for common CRUD operations. It's the recommended entry point for most use cases.

**Initialization:**

```swift
let context = try StorageKit.start { schema in
    schema.addKVCache()
    schema.autoSchema(UserRecord.self)
}

let storage = context.facade
```

---

### 4.1. Save Operations

#### `save(_:)`

**Declaration:**
```swift
public func save<E: RegisteredEntity>(_ entity: E) async throws
```

**Description:**
Saves a single entity to the database. Performs an upsert (insert or update).

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `entity` | `E: RegisteredEntity` | The entity to save |

**Throws:** `StorageError` on database failure

**Usage:**

```swift
let user = User(id: "1", name: "Alice", email: "alice@example.com")
try await storage.save(user)

// Update existing
var updated = user
updated.name = "Alice Smith"
try await storage.save(updated)  // Updates in place
```

---

#### `save(_:)` (Batch)

**Declaration:**
```swift
public func save<E: RegisteredEntity>(_ entities: [E]) async throws
```

**Description:**
Saves multiple entities in a single transaction. **Much faster** than individual saves.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `entities` | `[E]` | Array of entities to save |

**Throws:** `StorageError` on database failure

**Performance:**

```swift
// ❌ SLOW: 1000 individual transactions
for user in users {
    try await storage.save(user)
}

// ✅ FAST: Single transaction for all 1000 records
try await storage.save(users)  // ~100x faster
```

**Usage:**

```swift
let users = [
    User(id: "1", name: "Alice", email: "alice@example.com"),
    User(id: "2", name: "Bob", email: "bob@example.com"),
    User(id: "3", name: "Charlie", email: "charlie@example.com")
]

try await storage.save(users)  // Single transaction
```

---

### 4.2. Get Operations

#### `get(_:id:)`

**Declaration:**
```swift
public func get<E: RegisteredEntity>(_ type: E.Type, id: String) async throws -> E?
```

**Description:**
Retrieves a single entity by ID. Returns `nil` if not found.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type to retrieve |
| `id` | `String` | Entity ID |

**Returns:** Optional entity if found

**Throws:** `StorageError` on database failure

**Usage:**

```swift
if let user = try await storage.get(User.self, id: "1") {
    print("Found: \(user.name)")
} else {
    print("User not found")
}
```

---

#### `all(_:orderBy:ascending:)`

**Declaration:**
```swift
public func all<E: RegisteredEntity>(
    _ type: E.Type,
    orderBy: String? = nil,
    ascending: Bool = true
) async throws -> [E]
```

**Description:**
Retrieves all entities of a type with optional ordering.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `E.Type` | - | Entity type to retrieve |
| `orderBy` | `String?` | `nil` | Column name to sort by. If `nil`, sorts by `"id"` |
| `ascending` | `Bool` | `true` | Sort direction |

**Returns:** Array of entities (empty if none found)

**Throws:** `StorageError` on database failure

**Usage:**

```swift
// All users, sorted by ID
let users = try await storage.all(User.self)

// Sorted by name (ascending)
let byName = try await storage.all(User.self, orderBy: "name")

// Sorted by created date (descending)
let newest = try await storage.all(Post.self, orderBy: "createdAt", ascending: false)
```

---

#### `page(_:orderBy:ascending:limit:offset:)`

**Declaration:**
```swift
public func page<E: RegisteredEntity>(
    _ type: E.Type,
    orderBy: String? = nil,
    ascending: Bool = true,
    limit: Int,
    offset: Int = 0
) async throws -> RepoPage<E>
```

**Description:**
Retrieves a page of entities for cursor-based pagination.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `E.Type` | - | Entity type to retrieve |
| `orderBy` | `String?` | `nil` | Column to sort by |
| `ascending` | `Bool` | `true` | Sort direction |
| `limit` | `Int` | - | Maximum items per page |
| `offset` | `Int` | `0` | Number of items to skip |

**Returns:** `RepoPage<E>` containing items, nextOffset, and hasMore flag

**Throws:** `StorageError` on database failure

**Usage:**

```swift
// First page (20 items)
let page1 = try await storage.page(User.self, orderBy: "name", limit: 20)
print("Items: \(page1.items.count), Has more: \(page1.hasMore)")

// Next page
if page1.hasMore {
    let page2 = try await storage.page(User.self, orderBy: "name", limit: 20, offset: page1.nextOffset)
}

// Pagination loop
var offset = 0
let limit = 50
while true {
    let page = try await storage.page(Post.self, orderBy: "createdAt", ascending: false, limit: limit, offset: offset)

    for post in page.items {
        print(post.title)
    }

    guard page.hasMore else { break }
    offset = page.nextOffset
}
```

---

#### `count(_:)`

**Declaration:**
```swift
public func count<E: RegisteredEntity>(_ type: E.Type) async throws -> Int
```

**Description:**
Counts all entities of a type.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type to count |

**Returns:** Total number of entities

**Throws:** `StorageError` on database failure

**Usage:**

```swift
let totalUsers = try await storage.count(User.self)
print("Total users: \(totalUsers)")

// Check if empty
if try await storage.count(Post.self) == 0 {
    print("No posts yet")
}
```

---

### 4.3. Delete Operations

#### `delete(_:id:)`

**Declaration:**
```swift
public func delete<E: RegisteredEntity>(_ type: E.Type, id: String) async throws
```

**Description:**
Deletes a single entity by ID. Silently succeeds if entity doesn't exist.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type |
| `id` | `String` | Entity ID to delete |

**Throws:** `StorageError` on database failure

**Usage:**

```swift
try await storage.delete(User.self, id: "1")
```

---

#### `delete(_:)` (Entity)

**Declaration:**
```swift
public func delete<E: RegisteredEntity>(_ entity: E) async throws
```

**Description:**
Deletes an entity using its ID property.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `entity` | `E` | Entity to delete |

**Throws:** `StorageError` on database failure

**Usage:**

```swift
let user = try await storage.get(User.self, id: "1")!
try await storage.delete(user)
```

---

#### `deleteAll(_:)`

**Declaration:**
```swift
@discardableResult
public func deleteAll<E: RegisteredEntity>(_ type: E.Type) async throws -> Int
```

**Description:**
Deletes all entities of a type.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type |

**Returns:** Number of entities deleted

**Throws:** `StorageError` on database failure

**Usage:**

```swift
let deleted = try await storage.deleteAll(User.self)
print("Deleted \(deleted) users")
```

---

#### `deleteAll(_:where:equals:)`

**Declaration:**
```swift
@discardableResult
public func deleteAll<E: RegisteredEntity>(
    _ type: E.Type,
    where column: String,
    equals value: String
) async throws -> Int
```

**Description:**
Deletes all entities matching a column condition.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type |
| `column` | `String` | Column name to filter by |
| `value` | `String` | Value to match |

**Returns:** Number of entities deleted

**Throws:** `StorageError` on database failure

**Usage:**

```swift
// Delete all posts by author
let deleted = try await storage.deleteAll(Post.self, where: "authorId", equals: "user-1")
print("Deleted \(deleted) posts")

// Delete all inactive users
let removed = try await storage.deleteAll(User.self, where: "status", equals: "inactive")
```

---

### 4.4. Observe Operations

#### `observe(_:id:)`

**Declaration:**
```swift
public func observe<E: RegisteredEntity>(_ type: E.Type, id: String) -> AsyncStream<E?>
```

**Description:**
Creates a reactive stream that emits the entity whenever it changes. Values are delivered on **MainActor** (safe for SwiftUI).

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type |
| `id` | `String` | Entity ID to observe |

**Returns:** `AsyncStream<E?>` that emits `nil` when deleted

**MainActor Delivery:** Yes (safe for SwiftUI updates)

**Usage:**

```swift
// In SwiftUI view or @MainActor context
for await user in storage.observe(User.self, id: "1") {
    if let user {
        print("User updated: \(user.name)")
    } else {
        print("User deleted")
    }
}

// With Task
@MainActor
func observeUser(id: String) {
    Task {
        for await user in storage.observe(User.self, id: id) {
            self.currentUser = user
        }
    }
}
```

---

#### `observeAll(_:orderBy:ascending:)`

**Declaration:**
```swift
public func observeAll<E: RegisteredEntity>(
    _ type: E.Type,
    orderBy: String? = nil,
    ascending: Bool = true
) -> AsyncStream<[E]>
```

**Description:**
Creates a reactive stream that emits all entities whenever the table changes. Values are delivered on **MainActor**.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `E.Type` | - | Entity type |
| `orderBy` | `String?` | `nil` | Column to sort by |
| `ascending` | `Bool` | `true` | Sort direction |

**Returns:** `AsyncStream<[E]>` that emits on every table change

**MainActor Delivery:** Yes

**Usage:**

```swift
// SwiftUI with @Observable
@Observable
@MainActor
final class UserStore {
    private(set) var users: [User] = []
    private var observationTask: Task<Void, Never>?

    init() {
        observationTask = Task {
            for await updatedUsers in storage.observeAll(User.self, orderBy: "name") {
                self.users = updatedUsers
            }
        }
    }
}

struct UserListView: View {
    @State private var store = UserStore()

    var body: some View {
        List(store.users) { user in
            Text(user.name)
        }
    }
}
```

---

#### `observeAllDistinct(_:orderBy:ascending:)`

**Declaration:**
```swift
public func observeAllDistinct<E: RegisteredEntity & Equatable>(
    _ type: E.Type,
    orderBy: String? = nil,
    ascending: Bool = true
) -> AsyncStream<[E]>
```

**Description:**
Like `observeAll`, but only emits when values **actually change** (requires `Equatable`). Reduces unnecessary UI updates.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `E & Equatable` | - | Entity type (must be Equatable) |
| `orderBy` | `String?` | `nil` | Column to sort by |
| `ascending` | `Bool` | `true` | Sort direction |

**Returns:** `AsyncStream<[E]>` that skips duplicate values

**MainActor Delivery:** Yes

**Usage:**

```swift
// Only emits when user list actually changes
@Observable
@MainActor
final class EfficientUserStore {
    private(set) var users: [User] = []

    init() {
        Task {
            // Skips duplicate emissions, reducing SwiftUI re-renders
            for await updatedUsers in storage.observeAllDistinct(User.self, orderBy: "name") {
                self.users = updatedUsers
            }
        }
    }
}
```

**Performance Benefit:**

```swift
// observeAll: Emits on EVERY database change (even if result is same)
// Trigger: INSERT user → Emit [Alice, Bob]
// Trigger: UPDATE user (same result) → Emit [Alice, Bob]  ← Unnecessary
// Trigger: DELETE user → Emit [Alice]

// observeAllDistinct: Only emits when result changes
// Trigger: INSERT user → Emit [Alice, Bob]
// Trigger: UPDATE user (same result) → Skip emission  ← Saved UI update!
// Trigger: DELETE user → Emit [Alice]
```

---

### 4.5. Query Builder

#### `query(_:)`

**Declaration:**
```swift
public func query<E: RegisteredEntity>(_ type: E.Type) -> Query<E>
```

**Description:**
Creates a type-safe query builder for advanced filtering and pagination.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type to query |

**Returns:** `Query<E>` builder instance

**Usage:**

See [Section 5: QueryBuilder API](#5-querybuilder-api) for full details.

```swift
let adults = try await storage.query(User.self)
    .where { $0.age >= 18 }
    .orderBy("name")
    .limit(20)
    .fetch()
```

---

### 4.6. Relationship Loading

#### `loadParent(_:id:)`

**Declaration:**
```swift
public func loadParent<Parent: RegisteredEntity>(
    _ type: Parent.Type,
    id: String
) async throws -> Parent?
```

**Description:**
Loads a parent entity by ID. Use with `@StorageBelongsTo` relationships.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `Parent.Type` | Parent entity type |
| `id` | `String` | Parent ID |

**Returns:** Optional parent entity

**Throws:** `StorageError` on database failure

**Usage:**

```swift
@StorageEntity
struct Post {
    var id: String
    var title: String
    var authorId: String

    @StorageBelongsTo
    var author: User?
}

// Load post
let post = try await storage.get(Post.self, id: "post-1")!

// Load its author
let author = try await storage.loadParent(User.self, id: post.authorId)
print("Post by \(author?.name ?? "Unknown")")
```

---

#### `loadChildren(_:where:equals:orderBy:ascending:)`

**Declaration:**
```swift
public func loadChildren<Child: RegisteredEntity>(
    _ type: Child.Type,
    where foreignKey: String,
    equals parentId: String,
    orderBy: String? = nil,
    ascending: Bool = true
) async throws -> [Child]
```

**Description:**
Loads child entities by foreign key. Use with `@StorageHasMany` relationships.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `Child.Type` | - | Child entity type |
| `foreignKey` | `String` | - | Foreign key column name |
| `parentId` | `String` | - | Parent ID value |
| `orderBy` | `String?` | `nil` | Column to sort by |
| `ascending` | `Bool` | `true` | Sort direction |

**Returns:** Array of child entities

**Throws:** `StorageError` on database failure

**Usage:**

```swift
@StorageEntity
struct User {
    var id: String
    var name: String

    @StorageHasMany(foreignKey: "authorId")
    var posts: [Post]
}

// Load user
let user = try await storage.get(User.self, id: "user-1")!

// Load their posts
let posts = try await storage.loadChildren(
    Post.self,
    where: "authorId",
    equals: user.id,
    orderBy: "createdAt",
    ascending: false
)

print("\(user.name) has \(posts.count) posts")
```

---

### 4.7. Full-Text Search

#### `search(_:query:limit:)`

**Declaration:**
```swift
public func search<E: RegisteredEntity>(
    _ type: E.Type,
    query: String,
    limit: Int = 50
) async throws -> [SearchResult<E>]
```

**Description:**
Performs full-text search using FTS5. Requires FTS5 virtual table created with `schema.addFullTextSearch()`.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `E.Type` | - | Entity type |
| `query` | `String` | - | FTS5 query string (supports AND, OR, NOT, phrases) |
| `limit` | `Int` | `50` | Maximum results |

**Returns:** Array of `SearchResult<E>` sorted by relevance (best matches first)

**Throws:** `StorageError` if FTS5 table not configured

**FTS5 Query Syntax:**

| Syntax | Description | Example |
|--------|-------------|---------|
| `word` | Single term | `"swift"` |
| `"phrase"` | Exact phrase | `"swift concurrency"` |
| `AND` | Both terms | `"swift AND performance"` |
| `OR` | Either term | `"swift OR kotlin"` |
| `NOT` | Exclude term | `"swift NOT objc"` |
| `*` | Prefix match | `"swif*"` (matches swift, swiftly) |

**Setup:**

```swift
// 1. Create FTS5 virtual table during migration
let context = try StorageKit.start { schema in
    schema.autoSchema(ArticleRecord.self)
    schema.addFullTextSearch(table: "articles", columns: ["title", "content"])
}

// 2. Perform search
let results = try await storage.search(Article.self, query: "swift performance")

for result in results {
    print("\(result.entity.title) - rank: \(result.rank)")
}
```

**Usage Examples:**

```swift
// Simple search
let swift = try await storage.search(Article.self, query: "swift")

// Phrase search
let exact = try await storage.search(Article.self, query: "\"structured concurrency\"")

// Boolean search
let advanced = try await storage.search(Article.self, query: "swift AND (async OR await)")

// Exclude terms
let filtered = try await storage.search(Article.self, query: "swift NOT objc")

// Prefix matching
let starts = try await storage.search(Article.self, query: "concur*")
```

**Ranking:**

Results are sorted by BM25 rank (lower = better match):

```swift
for result in results {
    print("Rank: \(result.rank), Title: \(result.entity.title)")
}
// Output:
// Rank: -2.5, Title: "Swift Concurrency Deep Dive"
// Rank: -1.8, Title: "Async/Await in Swift"
// Rank: -0.9, Title: "Introduction to Swift"
```

---

#### `searchWithSnippets(_:query:snippetColumn:limit:)`

**Declaration:**
```swift
public func searchWithSnippets<E: RegisteredEntity>(
    _ type: E.Type,
    query: String,
    snippetColumn: Int = 0,
    limit: Int = 50
) async throws -> [SearchResult<E>]
```

**Description:**
Like `search()`, but includes highlighted snippets showing match context.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `E.Type` | - | Entity type |
| `query` | `String` | - | FTS5 query string |
| `snippetColumn` | `Int` | `0` | Column index (0-based) for snippet extraction |
| `limit` | `Int` | `50` | Maximum results |

**Returns:** Array of `SearchResult<E>` with `.snippet` populated

**Throws:** `StorageError` if FTS5 table not configured

**Snippet Format:**
- Matched terms wrapped in `<b>` tags
- Surrounding context with `...` ellipsis
- Max 32 tokens

**Usage:**

```swift
// Setup FTS with multiple columns
schema.addFullTextSearch(table: "articles", columns: ["title", "content"])
//                                                     ↑ col 0  ↑ col 1

// Search with snippets from "title" (column 0)
let results = try await storage.searchWithSnippets(
    Article.self,
    query: "swift concurrency",
    snippetColumn: 0,  // Extract from title
    limit: 10
)

for result in results {
    if let snippet = result.snippet {
        print("Match: \(snippet)")
        // Output: "...Deep Dive into <b>Swift</b> <b>Concurrency</b>..."
    }
}

// Search with snippets from "content" (column 1)
let contentResults = try await storage.searchWithSnippets(
    Article.self,
    query: "async await",
    snippetColumn: 1,  // Extract from content
    limit: 10
)
```

**Display in SwiftUI:**

```swift
struct SearchResultRow: View {
    let result: SearchResult<Article>

    var body: some View {
        VStack(alignment: .leading) {
            Text(result.entity.title)
                .font(.headline)

            if let snippet = result.snippet {
                Text(snippet)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

---

### 4.8. Repository Access

#### `repository(_:)`

**Declaration:**
```swift
public func repository<E: RegisteredEntity>(_ type: E.Type) -> GenericRepository<E, E.Record>
```

**Description:**
Returns a typed repository for advanced operations beyond the facade API.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type |

**Returns:** `GenericRepository<E, E.Record>` with full API

**Usage:**

```swift
let userRepo = storage.repository(User.self)

// Use repository methods
let users = try await userRepo.getAll(orderBy: "name")
let page = try await userRepo.getPage(limit: 20)
```

---

#### `anyRepository(_:)`

**Declaration:**
```swift
public func anyRepository<E: RegisteredEntity>(_ type: E.Type) -> AnyRepository<E>
```

**Description:**
Returns a type-erased repository for dependency injection scenarios.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `type` | `E.Type` | Entity type |

**Returns:** `AnyRepository<E>` with type-erased interface

**Usage:**

```swift
// Dependency injection
protocol UserService {
    var repository: AnyRepository<User> { get }
}

class UserServiceImpl: UserService {
    let repository: AnyRepository<User>

    init(storage: Storage) {
        self.repository = storage.anyRepository(User.self)
    }

    func findByEmail(_ email: String) async throws -> User? {
        let all = try await repository.getAll()
        return all.first { $0.email == email }
    }
}
```

---

## 5. QueryBuilder API

The `Query<E>` type provides a type-safe, chainable API for building complex queries with compile-time safety.

**Initialization:**

```swift
let query = storage.query(User.self)
```

---

### 5.1. Column References

**Declaration:**
```swift
public struct Column<T>: Sendable {
    public let name: String
    public init(_ name: String)
}
```

**Description:**
Type-safe column reference for building predicates.

**Usage:**

```swift
// Manual column creation
let ageColumn = Column<Int>("age")
let nameColumn = Column<String>("name")

// Used in predicates
let predicate = ageColumn >= 18
```

**Dynamic Member Lookup:**

```swift
// Access columns via keypaths (preferred)
storage.query(User.self)
    .where { $0.age >= 18 }  // $0.age returns Column<Int>
    .where { $0.name.contains("John") }  // $0.name returns Column<String>
```

---

### 5.2. Comparison Operators

#### Equality

```swift
// String
public func == (lhs: Column<String>, rhs: String) -> Predicate
public func != (lhs: Column<String>, rhs: String) -> Predicate

// Optional String
public func == (lhs: Column<String?>, rhs: String?) -> Predicate
public func != (lhs: Column<String?>, rhs: String?) -> Predicate

// Int
public func == (lhs: Column<Int>, rhs: Int) -> Predicate
public func != (lhs: Column<Int>, rhs: Int) -> Predicate

// Double
public func == (lhs: Column<Double>, rhs: Double) -> Predicate

// Bool
public func == (lhs: Column<Bool>, rhs: Bool) -> Predicate

// Date
public func == (lhs: Column<Date>, rhs: Date) -> Predicate
```

**Usage:**

```swift
storage.query(User.self)
    .where { $0.name == "Alice" }
    .where { $0.isActive == true }
    .fetch()
```

---

#### Comparison (<, >, <=, >=)

```swift
// Int
public func < (lhs: Column<Int>, rhs: Int) -> Predicate
public func > (lhs: Column<Int>, rhs: Int) -> Predicate
public func <= (lhs: Column<Int>, rhs: Int) -> Predicate
public func >= (lhs: Column<Int>, rhs: Int) -> Predicate

// Double
public func < (lhs: Column<Double>, rhs: Double) -> Predicate
public func > (lhs: Column<Double>, rhs: Double) -> Predicate
public func <= (lhs: Column<Double>, rhs: Double) -> Predicate
public func >= (lhs: Column<Double>, rhs: Double) -> Predicate

// Date
public func < (lhs: Column<Date>, rhs: Date) -> Predicate
public func > (lhs: Column<Date>, rhs: Date) -> Predicate
public func <= (lhs: Column<Date>, rhs: Date) -> Predicate
public func >= (lhs: Column<Date>, rhs: Date) -> Predicate
```

**Usage:**

```swift
// Age filter
storage.query(User.self)
    .where { $0.age >= 18 }
    .where { $0.age < 65 }
    .fetch()

// Date range
let yesterday = Date().addingTimeInterval(-86400)
storage.query(Post.self)
    .where { $0.createdAt > yesterday }
    .fetch()

// Price range
storage.query(Product.self)
    .where { $0.price >= 10.0 }
    .where { $0.price <= 100.0 }
    .fetch()
```

---

### 5.3. String Operations

#### `contains(_:)`

**Declaration:**
```swift
extension Column where T == String {
    public func contains(_ value: String) -> Predicate
}

extension Column where T == String? {
    public func contains(_ value: String) -> Predicate
}
```

**Description:**
Matches strings containing the given substring (case-sensitive).

**SQL Generated:** `column LIKE '%value%'`

**Usage:**

```swift
storage.query(User.self)
    .where { $0.name.contains("John") }
    .fetch()
// Matches: "John", "Johnny", "John Doe", "St. John"
```

---

#### `hasPrefix(_:)`

**Declaration:**
```swift
extension Column where T == String {
    public func hasPrefix(_ value: String) -> Predicate
}
```

**Description:**
Matches strings starting with the given prefix.

**SQL Generated:** `column LIKE 'value%'`

**Usage:**

```swift
storage.query(User.self)
    .where { $0.email.hasPrefix("admin@") }
    .fetch()
// Matches: "admin@example.com", "admin@company.org"
```

---

#### `hasSuffix(_:)`

**Declaration:**
```swift
extension Column where T == String {
    public func hasSuffix(_ value: String) -> Predicate
}
```

**Description:**
Matches strings ending with the given suffix.

**SQL Generated:** `column LIKE '%value'`

**Usage:**

```swift
storage.query(User.self)
    .where { $0.email.hasSuffix("@example.com") }
    .fetch()
// Matches: "alice@example.com", "bob@example.com"
```

---

#### `isNull` / `isNotNull`

**Declaration:**
```swift
extension Column where T == String? {
    public var isNull: Predicate
    public var isNotNull: Predicate
}
```

**Description:**
Checks for NULL values in optional columns.

**SQL Generated:** `column IS NULL` / `column IS NOT NULL`

**Usage:**

```swift
// Find users without phone numbers
storage.query(User.self)
    .where { $0.phone.isNull }
    .fetch()

// Find users with phone numbers
storage.query(User.self)
    .where { $0.phone.isNotNull }
    .fetch()
```

---

### 5.4. Compound Predicates

#### AND (`&&`)

**Declaration:**
```swift
public func && (lhs: Predicate, rhs: Predicate) -> Predicate
```

**Description:**
Combines predicates with AND logic (both must be true).

**SQL Generated:** `(predicate1) AND (predicate2)`

**Usage:**

```swift
storage.query(User.self)
    .where { $0.age >= 18 && $0.isActive == true }
    .fetch()
// SQL: WHERE (age >= 18) AND (isActive = 1)

// Multiple AND conditions
storage.query(Product.self)
    .where { $0.price >= 10.0 && $0.price <= 100.0 && $0.inStock == true }
    .fetch()
```

---

#### OR (`||`)

**Declaration:**
```swift
public func || (lhs: Predicate, rhs: Predicate) -> Predicate
```

**Description:**
Combines predicates with OR logic (either can be true).

**SQL Generated:** `(predicate1) OR (predicate2)`

**Usage:**

```swift
storage.query(User.self)
    .where { $0.role == "admin" || $0.role == "moderator" }
    .fetch()
// SQL: WHERE (role = 'admin') OR (role = 'moderator')
```

---

#### NOT (`!`)

**Declaration:**
```swift
public prefix func ! (predicate: Predicate) -> Predicate
```

**Description:**
Negates a predicate.

**SQL Generated:** `NOT (predicate)`

**Usage:**

```swift
storage.query(User.self)
    .where { !($0.email.hasSuffix("@spam.com")) }
    .fetch()
// SQL: WHERE NOT (email LIKE '%@spam.com')

// Complex negation
storage.query(Product.self)
    .where { !($0.price < 10.0 || $0.inStock == false) }
    .fetch()
// SQL: WHERE NOT ((price < 10.0) OR (inStock = 0))
```

---

### 5.5. Query Building

#### `where(_:)`

**Declaration:**
```swift
public func `where`(_ predicate: (ColumnRef<E>) -> Predicate) -> Query<E>
```

**Description:**
Adds a WHERE clause using type-safe column references.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `predicate` | `(ColumnRef<E>) -> Predicate` | Closure building the predicate |

**Returns:** New `Query<E>` with predicate added

**Chaining:** Multiple `where()` calls are combined with AND

**Usage:**

```swift
// Single condition
storage.query(User.self)
    .where { $0.age >= 18 }
    .fetch()

// Multiple where calls (AND combined)
storage.query(User.self)
    .where { $0.age >= 18 }
    .where { $0.isActive == true }
    .where { $0.email.hasSuffix("@example.com") }
    .fetch()
// SQL: WHERE (age >= 18) AND (isActive = 1) AND (email LIKE '%@example.com')

// Complex conditions
storage.query(Product.self)
    .where { ($0.category == "electronics" || $0.category == "computers") && $0.price <= 1000.0 }
    .fetch()
```

---

#### `orderBy(_:_:)`

**Declaration:**
```swift
public func orderBy(_ column: String, _ order: SortOrder = .ascending) -> Query<E>

public enum SortOrder: Sendable {
    case ascending
    case descending
}
```

**Description:**
Specifies result ordering.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `column` | `String` | - | Column name to sort by |
| `order` | `SortOrder` | `.ascending` | Sort direction |

**Returns:** New `Query<E>` with ordering

**Chaining:** Multiple `orderBy()` calls create multi-level sorting

**Usage:**

```swift
// Single sort
storage.query(User.self)
    .orderBy("name", .ascending)
    .fetch()

// Descending
storage.query(Post.self)
    .orderBy("createdAt", .descending)
    .fetch()

// Multi-level sort
storage.query(User.self)
    .orderBy("lastName", .ascending)
    .orderBy("firstName", .ascending)
    .fetch()
// SQL: ORDER BY lastName ASC, firstName ASC
```

---

#### `limit(_:)`

**Declaration:**
```swift
public func limit(_ n: Int) -> Query<E>
```

**Description:**
Limits the number of results returned.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `n` | `Int` | Maximum number of results |

**Returns:** New `Query<E>` with limit

**Usage:**

```swift
// Top 10
storage.query(Post.self)
    .orderBy("createdAt", .descending)
    .limit(10)
    .fetch()

// Single result (fetchOne is more efficient)
storage.query(User.self)
    .where { $0.email == "alice@example.com" }
    .limit(1)
    .fetchOne()
```

---

#### `offset(_:)`

**Declaration:**
```swift
public func offset(_ n: Int) -> Query<E>
```

**Description:**
Skips the first N results.

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `n` | `Int` | Number of results to skip |

**Returns:** New `Query<E>` with offset

**Usage:**

```swift
// Pagination
storage.query(User.self)
    .orderBy("name")
    .limit(20)
    .offset(40)  // Page 3 (skip first 40)
    .fetch()

// Load more pattern
var offset = 0
let limit = 50
while true {
    let items = try await storage.query(Post.self)
        .orderBy("createdAt", .descending)
        .limit(limit)
        .offset(offset)
        .fetch()

    guard !items.isEmpty else { break }
    offset += items.count
}
```

---

### 5.6. Query Execution

#### `fetch()`

**Declaration:**
```swift
public func fetch() async throws -> [E]
```

**Description:**
Executes the query and returns all matching entities.

**Returns:** Array of entities (empty if none found)

**Throws:** `StorageError` on database failure

**Usage:**

```swift
let adults = try await storage.query(User.self)
    .where { $0.age >= 18 }
    .orderBy("name")
    .fetch()

print("Found \(adults.count) adults")
```

---

#### `fetchOne()`

**Declaration:**
```swift
public func fetchOne() async throws -> E?
```

**Description:**
Executes the query and returns the first matching entity.

**Returns:** Optional entity (nil if not found)

**Throws:** `StorageError` on database failure

**Performance:** More efficient than `.limit(1).fetch()[0]`

**Usage:**

```swift
let admin = try await storage.query(User.self)
    .where { $0.role == "admin" }
    .fetchOne()

if let admin {
    print("Admin: \(admin.name)")
}
```

---

#### `count()`

**Declaration:**
```swift
public func count() async throws -> Int
```

**Description:**
Counts matching entities without fetching them.

**Returns:** Number of matching entities

**Throws:** `StorageError` on database failure

**Performance:** More efficient than `.fetch().count`

**Usage:**

```swift
let adultCount = try await storage.query(User.self)
    .where { $0.age >= 18 }
    .count()

print("\(adultCount) adults in database")

// Check existence
let hasAdmin = try await storage.query(User.self)
    .where { $0.role == "admin" }
    .count() > 0
```

---

#### `deleteAll()`

**Declaration:**
```swift
@discardableResult
public func deleteAll() async throws -> Int
```

**Description:**
Deletes all matching entities.

**Returns:** Number of entities deleted

**Throws:** `StorageError` on database failure

**Usage:**

```swift
// Delete inactive users
let deleted = try await storage.query(User.self)
    .where { $0.isActive == false }
    .deleteAll()

print("Deleted \(deleted) inactive users")

// Delete old posts
let oneYearAgo = Date().addingTimeInterval(-365 * 86400)
let removed = try await storage.query(Post.self)
    .where { $0.createdAt < oneYearAgo }
    .deleteAll()
```

---

### 5.7. Complete Query Examples

**Complex Filtering:**

```swift
// Users aged 18-65, active, with verified email
let users = try await storage.query(User.self)
    .where { $0.age >= 18 && $0.age <= 65 }
    .where { $0.isActive == true }
    .where { $0.emailVerified == true }
    .orderBy("lastName")
    .orderBy("firstName")
    .fetch()
```

**Pagination with Total Count:**

```swift
let limit = 20
let offset = 40

// Get page
let page = try await storage.query(Post.self)
    .where { $0.published == true }
    .orderBy("createdAt", .descending)
    .limit(limit)
    .offset(offset)
    .fetch()

// Get total count (separate query)
let total = try await storage.query(Post.self)
    .where { $0.published == true }
    .count()

print("Showing \(offset + 1)-\(offset + page.count) of \(total)")
```

**Search with Multiple Criteria:**

```swift
// Products in price range, in stock, specific category
let products = try await storage.query(Product.self)
    .where { $0.price >= 50.0 && $0.price <= 200.0 }
    .where { $0.inStock == true }
    .where { $0.category == "electronics" || $0.category == "computers" }
    .where { $0.name.contains("wireless") }
    .orderBy("price", .ascending)
    .limit(50)
    .fetch()
```

**Conditional Query Building:**

```swift
func searchUsers(role: String?, minAge: Int?, isActive: Bool?) async throws -> [User] {
    var query = storage.query(User.self)

    if let role {
        query = query.where { $0.role == role }
    }

    if let minAge {
        query = query.where { $0.age >= minAge }
    }

    if let isActive {
        query = query.where { $0.isActive == isActive }
    }

    return try await query
        .orderBy("name")
        .fetch()
}

// Usage
let admins = try await searchUsers(role: "admin", minAge: nil, isActive: true)
let adults = try await searchUsers(role: nil, minAge: 18, isActive: nil)
```

---

## 6. Migrations API

The `AppMigrations` type provides a declarative DSL for managing database schema migrations with automatic tracking.

**Initialization:**

```swift
let context = try StorageKit.start { schema in
    // Configure migrations here
}
```

---

### 6.1. Auto-Schema Migration

#### `autoSchema(_:)`

**Declaration:**
```swift
@discardableResult
public mutating func autoSchema<each R: StorageKitEntityRecord>(
    _ records: repeat (each R).Type
) -> Self
```

**Description:**
Automatically synchronizes entity schemas with the database. Handles CREATE TABLE and ADD COLUMN operations. Does NOT delete columns (for safety).

**Parameters:**

| Name | Type | Description |
|------|------|-------------|
| `records` | `repeat R.Type` | Record types to synchronize (variadic) |

**Returns:** `Self` for chaining

**How It Works:**
1. Generates schema fingerprint from Record types
2. Compares with current database schema
3. Creates missing tables
4. Adds missing columns
5. Skips if schema unchanged

**Migration Tracking:**
Tracked by schema fingerprint (e.g., `auto_schema_a3f4c2d1`). Only runs when schema changes.

**Usage:**

```swift
let context = try StorageKit.start { schema in
    schema.addKVCache()

    // Auto-sync multiple entities
    schema.autoSchema(
        UserRecord.self,
        PostRecord.self,
        CommentRecord.self
    )
}
```

**What Gets Migrated:**

```swift
// Initial state: Empty database
schema.autoSchema(UserRecord.self)
// Creates: users table with (id, name, email, updatedAt)

// Add field to User struct
@StorageEntity
struct User {
    var id: String
    var name: String
    var email: String
    var phone: String  // NEW FIELD
}

// Next app launch
schema.autoSchema(UserRecord.self)
// Adds: phone column to users table

// Schema unchanged
schema.autoSchema(UserRecord.self)
// Skips: No changes detected
```

**Column Additions:**

```swift
// Safe default values for NOT NULL columns
// TEXT → ''
// INTEGER → 0
// REAL → 0.0
// BOOLEAN → 0
// DATETIME → CURRENT_TIMESTAMP

ALTER TABLE users ADD COLUMN phone TEXT NOT NULL DEFAULT ''
```

**Fingerprint Calculation:**

```swift
// Deterministic hash based on:
// - Table names
// - Column names + types
// - Sorted alphabetically for consistency

// Example fingerprint: "auto_schema_a3f4c2d1"
```

---

### 6.2. KV Cache Table

#### `addKVCache(tableName:)`

**Declaration:**
```swift
@discardableResult
public mutating func addKVCache(tableName: String = "kv_cache") -> Self
```

**Description:**
Creates the key-value cache table required by `DiskCache`. Should be called in every migration setup.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `tableName` | `String` | `"kv_cache"` | Custom table name |

**Returns:** `Self` for chaining

**Generated Schema:**

```sql
CREATE TABLE IF NOT EXISTS kv_cache (
    key TEXT PRIMARY KEY,
    blob BLOB NOT NULL,
    updatedAt DATETIME NOT NULL,
    expiresAt DATETIME,
    size INTEGER NOT NULL DEFAULT 0
);

CREATE INDEX idx_kv_cache_expiresAt ON kv_cache(expiresAt);
CREATE INDEX idx_kv_cache_updatedAt ON kv_cache(updatedAt);
```

**Usage:**

```swift
let context = try StorageKit.start { schema in
    schema.addKVCache()  // Always include this
    schema.autoSchema(UserRecord.self)
}

// Custom table name (rare)
schema.addKVCache(tableName: "app_cache")
```

---

### 6.3. Full-Text Search

#### `addFullTextSearch(table:columns:tokenizer:)`

**Declaration:**
```swift
@discardableResult
public mutating func addFullTextSearch(
    table: String,
    columns: [String],
    tokenizer: String = "porter"
) -> Self
```

**Description:**
Creates an FTS5 virtual table with auto-sync triggers. Uses external content mode (no data duplication).

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `table` | `String` | - | Source table name (must exist) |
| `columns` | `[String]` | - | Columns to index for search |
| `tokenizer` | `String` | `"porter"` | FTS5 tokenizer (porter, unicode61, ascii) |

**Returns:** `Self` for chaining

**Requirements:**
- Source table must exist before calling this
- Columns must exist in source table

**Generated Components:**

1. **FTS5 Virtual Table:**
```sql
CREATE VIRTUAL TABLE articles_fts USING fts5(
    title, content,
    content='articles',
    content_rowid='rowid',
    tokenize='porter'
)
```

2. **Sync Triggers:** INSERT, UPDATE, DELETE triggers keep FTS in sync

**Usage:**

```swift
let context = try StorageKit.start { schema in
    // 1. Create table first
    schema.autoSchema(ArticleRecord.self)

    // 2. Add FTS5 index
    schema.addFullTextSearch(
        table: "articles",
        columns: ["title", "content"]
    )
}

// Search usage
let results = try await storage.search(Article.self, query: "swift concurrency")
```

**Tokenizers:**

| Tokenizer | Description | Use Case |
|-----------|-------------|----------|
| `porter` | English stemming | English text (default) |
| `unicode61` | Unicode-aware | Multilingual text |
| `ascii` | ASCII-only | ASCII text (faster) |

**Example with Unicode:**

```swift
schema.addFullTextSearch(
    table: "articles",
    columns: ["title", "content"],
    tokenizer: "unicode61"  // Supports Ukrainian, Chinese, etc.
)
```

---

### 6.4. Manual Migrations

#### `migration(_:skipIfTableExists:body:)`

**Declaration:**
```swift
@discardableResult
public mutating func migration(
    _ id: String,
    skipIfTableExists: String? = nil,
    body: @escaping @Sendable (Database) throws -> Void
) -> Self
```

**Description:**
Adds a custom migration for complex operations not covered by auto-schema.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `id` | `String` | - | Unique migration identifier (use date prefix: `"2026-01-15_description"`) |
| `skipIfTableExists` | `String?` | `nil` | Skip migration if table exists (for CREATE migrations) |
| `body` | `(Database) throws -> Void` | - | Migration code with GRDB Database access |

**Returns:** `Self` for chaining

**Migration ID Format:**
`"YYYY-MM-DD_short_description"`

**Tracking:**
Each migration runs once and is recorded in `grdb_migrations` table.

**Usage:**

```swift
let context = try StorageKit.start { schema in
    schema.autoSchema(UserRecord.self)

    // Create index
    schema.migration("2026-01-15_add_email_index") { db in
        try db.create(index: "idx_users_email", on: "users", columns: ["email"])
    }

    // Data transformation
    schema.migration("2026-01-20_normalize_emails") { db in
        try db.execute(sql: "UPDATE users SET email = LOWER(email)")
    }

    // Add column with default
    schema.migration("2026-01-25_add_status_column") { db in
        try db.execute(sql: "ALTER TABLE users ADD COLUMN status TEXT NOT NULL DEFAULT 'active'")
    }
}
```

**Skip If Table Exists:**

```swift
// Only create table if it doesn't exist
schema.migration("2026-01-15_create_settings", skipIfTableExists: "settings") { db in
    try db.create(table: "settings") { t in
        t.column("key", .text).primaryKey()
        t.column("value", .text).notNull()
    }
}

// Migration skipped if table already exists
// Useful for optional tables or backward compatibility
```

**Complex Migrations:**

```swift
// Foreign key constraint
schema.migration("2026-01-15_add_post_fk") { db in
    // SQLite doesn't support ADD CONSTRAINT, so we recreate table
    try db.execute(sql: """
        CREATE TABLE posts_new (
            id TEXT PRIMARY KEY,
            title TEXT NOT NULL,
            authorId TEXT NOT NULL,
            updatedAt DATETIME NOT NULL,
            FOREIGN KEY (authorId) REFERENCES users(id) ON DELETE CASCADE
        )
    """)
    try db.execute(sql: "INSERT INTO posts_new SELECT * FROM posts")
    try db.execute(sql: "DROP TABLE posts")
    try db.execute(sql: "ALTER TABLE posts_new RENAME TO posts")
}

// Composite index
schema.migration("2026-01-20_add_composite_index") { db in
    try db.create(index: "idx_posts_author_created", on: "posts", columns: ["authorId", "createdAt"])
}

// Unique constraint
schema.migration("2026-01-25_unique_email") { db in
    try db.create(index: "idx_users_email_unique", on: "users", columns: ["email"], unique: true)
}
```

---

### 6.5. Migration Options

#### `setOptions(_:)`

**Declaration:**
```swift
@discardableResult
public mutating func setOptions(_ options: Options) -> Self

public struct Options: Sendable {
    public var eraseDatabaseOnSchemaChange: Bool
    public var logger: (@Sendable (String) -> Void)?

    public init(
        eraseDatabaseOnSchemaChange: Bool = false,
        logger: (@Sendable (String) -> Void)? = nil
    )
}
```

**Description:**
Configures migration behavior.

**Parameters:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `eraseDatabaseOnSchemaChange` | `Bool` | `false` | **DANGER:** Erase database on schema change (development only!) |
| `logger` | `((String) -> Void)?` | `nil` | Migration event logger |

**Returns:** `Self` for chaining

**Usage:**

```swift
// Development: Reset database on schema change
let context = try StorageKit.start { schema in
    schema.setOptions(Options(
        eraseDatabaseOnSchemaChange: true,  // WARNING: Deletes all data!
        logger: { print("[Migration] \($0)") }
    ))

    schema.autoSchema(UserRecord.self)
}

// Production: Conservative options
let context = try StorageKit.start { schema in
    schema.setOptions(Options(
        eraseDatabaseOnSchemaChange: false,  // Safe for production
        logger: nil  // No logging overhead
    ))

    schema.autoSchema(UserRecord.self)
}
```

**Logger Output:**

```
[Migration] Applied storage_kv_cache_v1:kv_cache
[Migration] Created table 'users'
[Migration] Applied auto_schema_a3f4c2d1
[Migration] Added column 'phone' to 'users'
[Migration] Applied 2026-01-15_add_email_index
```

---

### 6.6. Complete Migration Examples

**Minimal Setup:**

```swift
let context = try StorageKit.start { schema in
    schema.addKVCache()
    schema.autoSchema(UserRecord.self)
}
```

**Full-Featured App:**

```swift
let context = try StorageKit.start { schema in
    // Options
    schema.setOptions(Options(
        eraseDatabaseOnSchemaChange: false,
        logger: { print($0) }
    ))

    // KV Cache
    schema.addKVCache()

    // Auto-sync entities
    schema.autoSchema(
        UserRecord.self,
        PostRecord.self,
        CommentRecord.self,
        TagRecord.self
    )

    // Full-text search
    schema.addFullTextSearch(table: "posts", columns: ["title", "content"])

    // Indexes for performance
    schema.migration("2026-01-15_indexes") { db in
        try db.create(index: "idx_posts_author", on: "posts", columns: ["authorId"])
        try db.create(index: "idx_comments_post", on: "comments", columns: ["postId"])
        try db.create(index: "idx_users_email", on: "users", columns: ["email"], unique: true)
    }

    // Data migrations
    schema.migration("2026-01-20_normalize_data") { db in
        try db.execute(sql: "UPDATE users SET email = LOWER(TRIM(email))")
    }
}
```

**Migration Order:**

```swift
// ✅ CORRECT: Table first, then FTS
schema.autoSchema(ArticleRecord.self)
schema.addFullTextSearch(table: "articles", columns: ["title"])

// ❌ WRONG: FTS before table exists
schema.addFullTextSearch(table: "articles", columns: ["title"])
schema.autoSchema(ArticleRecord.self)  // Error: articles_fts already exists
```

---

## 7. Repository Layer

The repository layer provides advanced CRUD operations with caching support. Most apps should use the `Storage` facade, but repositories are useful for:

- Dependency injection
- Advanced caching strategies
- Type-erased access

---

### 7.1. GenericRepository

**Declaration:**
```swift
public struct GenericRepository<E: StorageKitEntity, R: StorageKitEntityRecord>: Sendable
where R.E == E
```

**Description:**
Generic repository providing CRUD operations for an entity type.

**Initialization:**

```swift
let repo = context.makeRepository(User.self, record: UserRecord.self)

// Or via Storage facade
let repo = storage.repository(User.self)
```

---

#### CRUD Operations

**get(id:)**

```swift
public func get(id: String) async throws -> E?
```

Fetch entity by ID from database.

**Usage:**
```swift
let user = try await repo.get(id: "1")
```

---

**put(_:)**

```swift
public func put(_ entity: E) async throws
```

Save entity to database (upsert).

**Usage:**
```swift
try await repo.put(user)
```

---

**delete(id:)**

```swift
public func delete(id: String) async throws
```

Delete entity by ID.

**Usage:**
```swift
try await repo.delete(id: "1")
```

---

**getAll(orderBy:ascending:)**

```swift
public func getAll(
    orderBy: String? = nil,
    ascending: Bool = true
) async throws -> [E]
```

Fetch all entities with optional ordering.

**Usage:**
```swift
let users = try await repo.getAll(orderBy: "name")
```

---

**getAll(where:equals:orderBy:ascending:)**

```swift
public func getAll(
    where column: String,
    equals value: String,
    orderBy: String? = nil,
    ascending: Bool = true
) async throws -> [E]
```

Fetch entities filtered by column value.

**Usage:**
```swift
let posts = try await repo.getAll(where: "authorId", equals: "user-1", orderBy: "createdAt", ascending: false)
```

---

**countAll()**

```swift
public func countAll() async throws -> Int
```

Count all entities.

**Usage:**
```swift
let total = try await repo.countAll()
```

---

#### Batch Operations

**putAll(_:)**

```swift
public func putAll(_ entities: [E]) async throws
```

Save multiple entities in single transaction (much faster).

**Usage:**
```swift
try await repo.putAll(users)
```

---

**deleteAll()**

```swift
@discardableResult
public func deleteAll() async throws -> Int
```

Delete all entities.

**Returns:** Number deleted

**Usage:**
```swift
let deleted = try await repo.deleteAll()
```

---

**deleteAll(where:equals:)**

```swift
@discardableResult
public func deleteAll(where column: String, equals value: String) async throws -> Int
```

Delete entities matching condition.

**Returns:** Number deleted

**Usage:**
```swift
let deleted = try await repo.deleteAll(where: "status", equals: "inactive")
```

---

#### Observation

**observe(id:)**

```swift
public func observe(id: String) -> AsyncStream<E?>
```

Stream entity changes (MainActor delivery).

**Usage:**
```swift
for await user in repo.observe(id: "1") {
    if let user {
        print("User: \(user.name)")
    }
}
```

---

**observeAll(orderBy:ascending:)**

```swift
public func observeAll(
    orderBy: String? = nil,
    ascending: Bool = true
) -> AsyncStream<[E]>
```

Stream all entities (MainActor delivery).

**Usage:**
```swift
for await users in repo.observeAll(orderBy: "name") {
    print("Users: \(users.count)")
}
```

---

**observeAllDistinct(orderBy:ascending:)**

```swift
public func observeAllDistinct(
    orderBy: String? = nil,
    ascending: Bool = true
) -> AsyncStream<[E]> where E: Equatable
```

Stream distinct values only (skips duplicates).

**Usage:**
```swift
for await users in repo.observeAllDistinct(orderBy: "name") {
    self.users = users  // Only updates when actually changed
}
```

---

#### Pagination

**getPage(orderBy:ascending:limit:offset:)**

```swift
public func getPage(
    orderBy: String? = nil,
    ascending: Bool = true,
    limit: Int,
    offset: Int = 0
) async throws -> RepoPage<E>
```

Fetch a page of entities.

**Usage:**
```swift
let page = try await repo.getPage(orderBy: "name", limit: 20, offset: 0)
print("Items: \(page.items.count), Has more: \(page.hasMore)")
```

---

### 7.2. AnyRepository

**Declaration:**
```swift
public struct AnyRepository<E: StorageKitEntity>: Sendable
```

**Description:**
Type-erased repository for dependency injection.

**Initialization:**

```swift
let anyRepo = context.repository(User.self, record: UserRecord.self)

// Or via Storage facade
let anyRepo = storage.anyRepository(User.self)
```

**API:**
Same methods as `GenericRepository` but type-erased.

**Usage:**

```swift
protocol UserService {
    var userRepo: AnyRepository<User> { get }
}

class UserServiceImpl: UserService {
    let userRepo: AnyRepository<User>

    init(storage: Storage) {
        self.userRepo = storage.anyRepository(User.self)
    }

    func findByEmail(_ email: String) async throws -> User? {
        let all = try await userRepo.getAll()
        return all.first { $0.email == email }
    }
}
```

---

### 7.3. RepoPage

**Declaration:**
```swift
public struct RepoPage<T: Sendable>: Sendable {
    public let items: [T]
    public let nextOffset: Int
    public let hasMore: Bool
}
```

**Description:**
Pagination result container.

**Properties:**

| Name | Type | Description |
|------|------|-------------|
| `items` | `[T]` | Current page items |
| `nextOffset` | `Int` | Offset for next page |
| `hasMore` | `Bool` | Whether more items exist |

**Usage:**

```swift
var offset = 0
let limit = 20

while true {
    let page = try await repo.getPage(limit: limit, offset: offset)

    process(page.items)

    guard page.hasMore else { break }
    offset = page.nextOffset
}
```

---

## 8. Core Types

### 8.1. Entity Protocols

#### StorageKitEntity

**Declaration:**
```swift
public protocol StorageKitEntity: Codable, Sendable, Equatable {
    associatedtype Id: Hashable & Sendable
    var id: Id { get }
}
```

**Description:**
Base protocol for domain entities.

**Requirements:**
- `Codable`: JSON serialization support
- `Sendable`: Swift 6 concurrency safety
- `Equatable`: Value comparison
- `id` property of any `Hashable & Sendable` type

**Usage:**

```swift
struct User: StorageKitEntity {
    var id: String  // or UUID, Int, etc.
    var name: String
    var email: String
}
```

---

#### StorageKitEntityRecord

**Declaration:**
```swift
public protocol StorageKitEntityRecord: FetchableRecord, PersistableRecord, Sendable {
    associatedtype E: StorageKitEntity
    static var databaseTableName: String { get }
    func asEntity() -> E
    static func from(_ e: E, now: Date) -> Self
    static var schemaColumns: [ColumnSchema] { get }
}
```

**Description:**
Database representation of an entity (usually generated by `@StorageEntity`).

**Requirements:**
- `FetchableRecord`, `PersistableRecord`: GRDB protocols
- `databaseTableName`: Table name
- `asEntity()`: Convert to domain entity
- `from(_:now:)`: Create from domain entity
- `schemaColumns`: Schema for auto-migration

**Generated by `@StorageEntity`:**

```swift
// You write:
@StorageEntity
struct User {
    var id: String
    var name: String
}

// Macro generates:
struct UserRecord: StorageKitEntityRecord {
    typealias E = User
    static let databaseTableName = "users"

    var id: String
    var name: String
    var updatedAt: Date

    func asEntity() -> User { ... }
    static func from(_ e: User, now: Date) -> UserRecord { ... }
    static var schemaColumns: [ColumnSchema] { ... }
}
```

---

#### RegisteredEntity

**Declaration:**
```swift
public protocol RegisteredEntity: StorageKitEntity {
    associatedtype Record: StorageKitEntityRecord where Record.E == Self
}
```

**Description:**
Entity with known Record type for simplified API.

**Generated by `@StorageEntity`:**

```swift
extension User: RegisteredEntity {
    public typealias Record = UserRecord
}
```

**Benefit:**

```swift
// Without RegisteredEntity
let repo = context.makeRepository(User.self, record: UserRecord.self)

// With RegisteredEntity (Record type inferred)
try await storage.save(user)  // UserRecord inferred automatically
```

---

#### Embeddable

**Declaration:**
```swift
public protocol Embeddable: Codable, Sendable, Equatable {}
```

**Description:**
Marker protocol for value objects that can be embedded (flattened) into parent tables.

**Requirements:**
- All properties must be `Codable` primitives
- No nested `Embeddable` types (only one level)

**Usage:**

```swift
struct Address: Embeddable {
    var street: String
    var city: String
    var zip: String
}

@StorageEntity
struct User {
    var id: String

    @StorageEmbedded(prefix: "home_")
    var homeAddress: Address
}
```

---

### 8.2. Configuration Types

#### StorageConfig

**Declaration:**
```swift
public struct StorageConfig: Sendable {
    public var defaultTTL: TimeInterval
    public var diskQuotaBytes: Int
    public var makeEncoder: @Sendable () -> JSONEncoder
    public var makeDecoder: @Sendable () -> JSONDecoder
    public var clock: Clock
    public var namespace: String

    public init(
        defaultTTL: TimeInterval = 300,
        diskQuotaBytes: Int = 20 * 1024 * 1024,
        clock: Clock = SystemClock(),
        namespace: String = "storage",
        configureEncoder: (@Sendable (inout JSONEncoder) -> Void)? = nil,
        configureDecoder: (@Sendable (inout JSONDecoder) -> Void)? = nil
    )
}
```

**Description:**
Configuration for caching, encoding, and time management.

**Properties:**

| Name | Type | Default | Description |
|------|------|---------|-------------|
| `defaultTTL` | `TimeInterval` | `300` | Default cache TTL (5 minutes) |
| `diskQuotaBytes` | `Int` | `20_971_520` | Disk cache quota (20 MB) |
| `makeEncoder` | `() -> JSONEncoder` | ISO8601 | Factory for JSON encoders |
| `makeDecoder` | `() -> JSONDecoder` | ISO8601 | Factory for JSON decoders |
| `clock` | `Clock` | `SystemClock()` | Time abstraction |
| `namespace` | `String` | `"storage"` | Cache key namespace |

**Usage:**

```swift
let config = StorageConfig(
    defaultTTL: 600,  // 10 minutes
    diskQuotaBytes: 50 * 1024 * 1024,  // 50 MB
    namespace: "myapp",
    configureEncoder: { encoder in
        encoder.outputFormatting = .prettyPrinted
    }
)
```

**Why Factories?**
Swift 6 requires encoder/decoder to be `Sendable`. Factories create new instances per use instead of sharing.

---

#### Clock

**Declaration:**
```swift
public protocol Clock: Sendable {
    var now: Date { get }
}

public struct SystemClock: Clock {
    public init() {}
    public var now: Date { Date() }
}
```

**Description:**
Time abstraction for testability.

**Usage:**

```swift
// Production
let config = StorageConfig(clock: SystemClock())

// Testing
struct MockClock: Clock {
    var now: Date
}

let testConfig = StorageConfig(clock: MockClock(now: Date(timeIntervalSince1970: 0)))
```

---

#### KeyBuilder

**Declaration:**
```swift
public struct KeyBuilder: Sendable {
    public let namespace: String

    public func entityKey<T>(_ type: T.Type, id: String) -> String
    public func queryKey(_ name: String, params: [String: String] = [:]) -> String
}
```

**Description:**
Generates namespaced cache keys.

**Usage:**

```swift
let keys = KeyBuilder(namespace: "myapp")

let key1 = keys.entityKey(User.self, id: "1")
// "myapp.User:1"

let key2 = keys.queryKey("recent_posts", params: ["limit": "10"])
// "myapp.query:recent_posts?limit=10"
```

---

### 8.3. Cache Types

#### MemoryCache

**Declaration:**
```swift
public actor MemoryCache<Key: Hashable & Sendable, Value: Sendable> {
    public let capacity: Int
    public let defaultTTL: TimeInterval
    public let clock: Clock

    public init(capacity: Int, defaultTTL: TimeInterval, clock: Clock)

    public func get(_ key: Key) -> Value?
    public func set(_ value: Value, for key: Key, ttl: TimeInterval?)
    public func remove(_ key: Key)
    public func removeAll()
}
```

**Description:**
Actor-based in-memory LRU cache with TTL support.

**Eviction:**
1. TTL expiration check
2. LRU eviction when over capacity

**Usage:**

```swift
let cache = MemoryCache<String, User>(
    capacity: 100,
    defaultTTL: 300,
    clock: SystemClock()
)

await cache.set(user, for: "user-1", ttl: nil)
let cached = await cache.get("user-1")
await cache.remove("user-1")
```

---

#### DiskCache

**Declaration:**
```swift
public actor DiskCache<Value: Codable & Sendable> {
    public init(db: DatabaseActor, config: StorageConfig, onError: ErrorHandler? = nil)

    public func get(_ key: String) async -> Value?
    public func set(_ value: Value, for key: String, ttl: TimeInterval?) async
    public func remove(_ key: String) async
    public func removeAll() async
    public func pruneExpired() async
}
```

**Description:**
Actor-based disk cache using SQLite `kv_cache` table.

**Features:**
- TTL-based expiration
- Quota-based pruning (LRU eviction)
- Atomic operations

**Usage:**

```swift
let diskCache = DiskCache<User>(
    db: context.storage.dbActor,
    config: context.config
)

await diskCache.set(user, for: "user-1", ttl: 600)
let cached = await diskCache.get("user-1")
```

---

### 8.4. Error Types

#### StorageError

**Declaration:**
```swift
public enum StorageError: Error, Sendable {
    // Database
    case databaseNotFound(path: String)
    case migrationFailed(id: String, underlying: Error)
    case transactionFailed(underlying: Error)

    // Cache
    case cacheReadFailed(key: String, underlying: Error)
    case cacheWriteFailed(key: String, underlying: Error)
    case cacheDecodingFailed(key: String, type: String, underlying: Error)
    case cacheEncodingFailed(key: String, type: String, underlying: Error)

    // Entity
    case entityNotFound(type: String, id: String)
    case entityEncodingFailed(type: String, underlying: Error)
    case entityDecodingFailed(type: String, underlying: Error)

    // Configuration
    case invalidTableName(String)
    case invalidConfiguration(message: String)

    // Query
    case queryFailed(sql: String?, underlying: Error)
}
```

**Description:**
Errors thrown by StorageKit operations.

**Conforms to:** `LocalizedError` for user-friendly messages

**Usage:**

```swift
do {
    try await storage.save(user)
} catch let error as StorageError {
    switch error {
    case .entityNotFound(let type, let id):
        print("Not found: \(type) with id \(id)")
    case .migrationFailed(let id, let underlying):
        print("Migration \(id) failed: \(underlying)")
    default:
        print("Storage error: \(error.localizedDescription)")
    }
}
```

---

### 8.5. Schema Types

#### ColumnSchema

**Declaration:**
```swift
public struct ColumnSchema: Sendable, Equatable {
    public let name: String
    public let type: String
    public let notNull: Bool
    public let primaryKey: Bool
    public let defaultValue: String?

    public init(
        name: String,
        type: String,
        notNull: Bool = false,
        primaryKey: Bool = false,
        defaultValue: String? = nil
    )
}
```

**Description:**
Represents a database column for auto-migration.

**Usage:**

```swift
let column = ColumnSchema(
    name: "email",
    type: "TEXT",
    notNull: true,
    primaryKey: false
)
```

---

#### TableSchema

**Declaration:**
```swift
public struct TableSchema: Sendable, Equatable {
    public let name: String
    public let columns: [ColumnSchema]

    public init(name: String, columns: [ColumnSchema])

    public func column(named: String) -> ColumnSchema?
}
```

**Description:**
Represents a database table schema.

**Usage:**

```swift
let schema = TableSchema(
    name: "users",
    columns: [
        ColumnSchema(name: "id", type: "TEXT", primaryKey: true),
        ColumnSchema(name: "name", type: "TEXT", notNull: true)
    ]
)

let idColumn = schema.column(named: "id")
```

---

## 9. Observation & Reactivity

StorageKit provides reactive observation using Swift's `AsyncStream`, with MainActor delivery for UI safety.

### 9.1. Observation Architecture

**Flow:**

```
Database Change (INSERT/UPDATE/DELETE)
    ↓
GRDB ValueObservation (background thread)
    ↓
ObservationBridge (converts to AsyncStream)
    ↓
MainActor delivery (optional)
    ↓
SwiftUI View / @Observable class
```

**Key Components:**

1. **ObservationBridge:** Converts GRDB `ValueObservation` to `AsyncStream`
2. **DatabaseActor:** Provides `stream()` and `streamOnMainActor()` methods
3. **Repository:** High-level `observe()` and `observeAll()` methods
4. **Storage Facade:** Simplified `observe()` API

---

### 9.2. MainActor Delivery

**Why MainActor?**

SwiftUI views must update on MainActor. StorageKit delivers observation values on MainActor by default.

**Stream Types:**

| Method | MainActor | Distinct | Use Case |
|--------|-----------|----------|----------|
| `stream()` | ❌ | ❌ | Background processing |
| `streamOnMainActor()` | ✅ | ❌ | UI updates (all changes) |
| `streamDistinctOnMainActor()` | ✅ | ✅ | UI updates (skip duplicates) |

**Usage:**

```swift
// Background stream
for await users in db.stream(tracking: { db in try User.fetchAll(db) }) {
    // Not on MainActor
    processUsers(users)
}

// UI-safe stream
for await users in db.streamOnMainActor(tracking: { db in try User.fetchAll(db) }) {
    // On MainActor - safe for SwiftUI
    self.users = users
}
```

---

### 9.3. Distinct Observation

**Problem:**

```swift
// Emits on EVERY database write, even if result unchanged
for await users in storage.observeAll(User.self) {
    self.users = users  // Triggers SwiftUI update every time
}

// Timeline:
// INSERT user → Emit [Alice, Bob]        ← Needed
// UPDATE user → Emit [Alice, Bob]        ← Unnecessary (same result)
// UPDATE user → Emit [Alice, Bob]        ← Unnecessary
// DELETE user → Emit [Alice]             ← Needed
```

**Solution:**

```swift
// Only emits when value changes (requires Equatable)
for await users in storage.observeAllDistinct(User.self) {
    self.users = users  // Only triggers when users actually change
}

// Timeline:
// INSERT user → Emit [Alice, Bob]        ← Emitted
// UPDATE user → Skip (same as [Alice, Bob])
// UPDATE user → Skip (same as [Alice, Bob])
// DELETE user → Emit [Alice]             ← Emitted
```

**Performance Impact:**

```swift
// Without distinct: 1000 database writes = 1000 UI updates
// With distinct: 1000 database writes = 50 UI updates (95% reduction)
```

---

### 9.4. SwiftUI Integration Patterns

#### @Observable Pattern

```swift
import SwiftUI
import Observation
import StorageKit

@Observable
@MainActor
final class UserStore {
    private(set) var users: [User] = []
    private var observationTask: Task<Void, Never>?

    init() {
        observationTask = Task {
            // Stream is already on MainActor
            for await updatedUsers in AppStorage.storage.observeAllDistinct(User.self, orderBy: "name") {
                self.users = updatedUsers
            }
        }
    }

    // Task cancels automatically when UserStore is deallocated
}

struct UserListView: View {
    @State private var store = UserStore()

    var body: some View {
        List(store.users) { user in
            Text(user.name)
        }
    }
}
```

---

#### Task-based Observation

```swift
struct UserDetailView: View {
    let userId: String
    @State private var user: User?

    var body: some View {
        VStack {
            if let user {
                Text(user.name)
                Text(user.email)
            } else {
                ProgressView()
            }
        }
        .task {
            // Observation tied to view lifecycle
            for await updatedUser in AppStorage.storage.observe(User.self, id: userId) {
                self.user = updatedUser
            }
        }
    }
}
```

---

#### Manual Task Management

```swift
@MainActor
final class PostListViewModel {
    private(set) var posts: [Post] = []
    private var observationTask: Task<Void, Never>?

    func startObserving(authorId: String) {
        stopObserving()

        observationTask = Task {
            let stream = await AppStorage.storage.observeAll(Post.self, orderBy: "createdAt", ascending: false)
                .filter { $0.authorId == authorId }

            for await updatedPosts in stream {
                self.posts = updatedPosts
            }
        }
    }

    func stopObserving() {
        observationTask?.cancel()
        observationTask = nil
    }

    deinit {
        stopObserving()
    }
}
```

---

### 9.5. AsyncStream Patterns

#### Buffering Policy

```swift
// bufferingNewest(1): Keep only latest value (default)
db.streamOnMainActor(bufferingPolicy: .bufferingNewest(1)) { db in
    try User.fetchAll(db)
}

// bufferingOldest(10): Keep up to 10 oldest values
db.streamOnMainActor(bufferingPolicy: .bufferingOldest(10)) { db in
    try User.fetchAll(db)
}

// unbounded: No buffering (can cause memory issues)
db.streamOnMainActor(bufferingPolicy: .unbounded) { db in
    try User.fetchAll(db)
}
```

---

#### Error Handling

```swift
// Repository/Storage observations don't expose errors (silent failure)
for await users in storage.observeAll(User.self) {
    // Will continue even if errors occur
    print("Users: \(users.count)")
}

// Low-level DatabaseActor with error handler
db.streamOnMainActor(onError: { error in
    print("Observation error: \(error)")
}) { db in
    try User.fetchAll(db)
}
```

---

#### Cancellation

```swift
// Automatic cancellation via task
let task = Task {
    for await users in storage.observeAll(User.self) {
        print(users.count)
    }
}

// Cancel observation
task.cancel()

// AsyncStream handles cleanup automatically
```

---

### 9.6. Advanced Observation

#### Filtering Streams

```swift
// Filter in-stream
let stream = storage.observeAll(User.self)

for await users in stream {
    let admins = users.filter { $0.role == "admin" }
    self.adminUsers = admins
}
```

---

#### Combining Streams

```swift
@MainActor
func observeUsersAndPosts() async {
    async let usersTask = observeUsers()
    async let postsTask = observePosts()

    await (usersTask, postsTask)
}

func observeUsers() async {
    for await users in storage.observeAll(User.self) {
        self.users = users
    }
}

func observePosts() async {
    for await posts in storage.observeAll(Post.self) {
        self.posts = posts
    }
}
```

---

#### Debouncing (Manual)

```swift
@MainActor
func observeWithDebounce() {
    Task {
        var lastUpdate = Date()
        let debounceInterval: TimeInterval = 0.5

        for await users in storage.observeAll(User.self) {
            let now = Date()
            guard now.timeIntervalSince(lastUpdate) >= debounceInterval else {
                continue  // Skip rapid updates
            }

            lastUpdate = now
            self.users = users
        }
    }
}
```

---

## 10. Configuration & Advanced

### 10.1. StorageKit.start() Variants

#### Zero Configuration

```swift
let context = try StorageKit.start()
// File: ~/Library/Application Support/app.sqlite
// TTL: 5 minutes
// Quota: 30 MB
// Tables: kv_cache only
```

---

#### File Name Only

```swift
let context = try StorageKit.start(fileName: "myapp.sqlite")
// File: ~/Library/Application Support/myapp.sqlite
// TTL: 5 minutes
// Quota: 30 MB
// Tables: kv_cache only
```

---

#### Minimal Configuration

```swift
let context = try StorageKit.start(
    fileName: "myapp.sqlite",
    cacheTTL: .minutes(10),
    diskQuota: .megabytes(50)
) { schema in
    schema.addKVCache()
    schema.autoSchema(UserRecord.self)
}
```

---

#### Full URL

```swift
let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
let dbURL = documentsURL.appendingPathComponent("mydb.sqlite")

let context = try StorageKit.start(
    at: dbURL,
    cacheTTL: .hours(1),
    diskQuota: .gigabytes(1)
) { schema in
    schema.autoSchema(UserRecord.self)
}
```

---

### 10.2. Cache Configuration

#### TTL Settings

```swift
// Short-lived cache (1 minute)
StorageKit.start(cacheTTL: .minutes(1)) { ... }

// Long-lived cache (1 hour)
StorageKit.start(cacheTTL: .hours(1)) { ... }

// No expiration
StorageKit.start(cacheTTL: .init(seconds: 0)) { ... }
```

---

#### Disk Quota

```swift
// Small quota (10 MB)
StorageKit.start(diskQuota: .megabytes(10)) { ... }

// Large quota (1 GB)
StorageKit.start(diskQuota: .gigabytes(1)) { ... }

// Custom bytes
StorageKit.start(diskQuota: .init(bytes: 50_000_000)) { ... }
```

---

### 10.3. Custom Configuration

#### Custom Encoders/Decoders

```swift
let config = StorageConfig(
    configureEncoder: { encoder in
        encoder.outputFormatting = .prettyPrinted
        encoder.keyEncodingStrategy = .convertToSnakeCase
    },
    configureDecoder: { decoder in
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .secondsSince1970
    }
)
```

---

#### Custom Clock (Testing)

```swift
struct MockClock: Clock {
    var now: Date
}

let testConfig = StorageConfig(
    clock: MockClock(now: Date(timeIntervalSince1970: 1_000_000))
)

// Use in tests
let testContext = try StorageKit.start(at: testURL) { schema in
    schema.addKVCache()
}
// (Note: Can't pass config to start(), need custom initialization)
```

---

### 10.4. Database Access

#### Direct Pool Access

```swift
let pool = context.storage.pool

// Use GRDB directly
try await pool.write { db in
    try db.execute(sql: "VACUUM")
}
```

---

#### DatabaseActor Access

```swift
let db = context.storage.dbActor

// Custom read
let count = try await db.read { db in
    try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM users") ?? 0
}

// Custom write
try await db.write { db in
    try db.execute(sql: "DELETE FROM users WHERE createdAt < ?", arguments: [oldDate])
}
```

---

### 10.5. Testing Patterns

#### Isolated Database

```swift
func makeTestStorage() throws -> StorageKit.Context {
    let tempDir = FileManager.default.temporaryDirectory
    let testDB = tempDir.appendingPathComponent("test_\(UUID().uuidString).sqlite")

    return try StorageKit.start(at: testDB) { schema in
        schema.addKVCache()
        schema.autoSchema(UserRecord.self)
    }
}

// In test
let context = try makeTestStorage()
let storage = context.facade

try await storage.save(testUser)
XCTAssertEqual(try await storage.count(User.self), 1)
```

---

#### In-Memory Database

```swift
// GRDB supports in-memory databases
var config = Configuration()
config.prepareDatabase { db in
    try db.execute(sql: "PRAGMA foreign_keys = ON")
}

let pool = try DatabaseQueue(configuration: config)  // In-memory
let dbActor = DatabaseActor(pool: pool)
let storage = StorageContext(pool: pool, dbActor: dbActor)

// Run migrations
var schema = AppMigrations()
schema.addKVCache()
schema.autoSchema(UserRecord.self)
try schema.run(on: pool)
```

---

### 10.6. Performance Tuning

#### Batch Inserts

```swift
// ❌ SLOW: 1000 individual writes
for user in users {
    try await storage.save(user)
}

// ✅ FAST: Single transaction
try await storage.save(users)  // ~100x faster
```

---

#### Indexes for Queries

```swift
schema.migration("2026-01-15_indexes") { db in
    // Add indexes for frequently queried columns
    try db.create(index: "idx_users_email", on: "users", columns: ["email"])
    try db.create(index: "idx_posts_author_created", on: "posts", columns: ["authorId", "createdAt"])
}

// Now these queries are fast
let user = try await storage.query(User.self)
    .where { $0.email == "alice@example.com" }
    .fetchOne()  // Uses index

let posts = try await storage.query(Post.self)
    .where { $0.authorId == "user-1" }
    .orderBy("createdAt", .descending)
    .fetch()  // Uses composite index
```

---

#### Query vs. Repository

```swift
// ❌ Inefficient: Fetch all then filter
let all = try await storage.all(User.self)
let adults = all.filter { $0.age >= 18 }

// ✅ Efficient: Filter in database
let adults = try await storage.query(User.self)
    .where { $0.age >= 18 }
    .fetch()
```

---

#### Observation Efficiency

```swift
// ❌ Multiple separate observations
for await users in storage.observeAll(User.self) { ... }
for await posts in storage.observeAll(Post.self) { ... }
for await comments in storage.observeAll(Comment.self) { ... }

// ✅ Single observation with computed properties
@Observable
@MainActor
final class AppState {
    private(set) var users: [User] = []
    private(set) var posts: [Post] = []

    var recentPosts: [Post] {
        posts.filter { $0.createdAt > Date().addingTimeInterval(-86400) }
    }
}
```

---

### 10.7. WAL Mode

StorageKit enables Write-Ahead Logging (WAL) mode by default for better concurrency.

**Benefits:**
- Readers don't block writers
- Writers don't block readers
- Better performance for concurrent access

**Configuration:**

```swift
// Enabled by default in StorageKit.start()
var cfg = Configuration()
cfg.prepareDatabase { db in
    try db.execute(sql: "PRAGMA journal_mode = WAL")
    try db.execute(sql: "PRAGMA foreign_keys = ON")
}
```

---

## Appendix A: Complete Example

```swift
import StorageKit
import SwiftUI
import Observation

// MARK: - Models

@StorageEntity
struct User {
    var id: String
    var name: String
    var email: String
}

@StorageEntity
struct Post {
    var id: String
    var title: String
    var content: String
    var authorId: String
    var createdAt: Date

    @StorageBelongsTo
    var author: User?
}

// MARK: - Storage Setup

enum AppStorage {
    static let context: StorageKit.Context = {
        do {
            return try StorageKit.start(
                fileName: "myapp.sqlite",
                cacheTTL: .minutes(10),
                diskQuota: .megabytes(50)
            ) { schema in
                schema.setOptions(Options(logger: { print($0) }))
                schema.addKVCache()

                schema.autoSchema(
                    UserRecord.self,
                    PostRecord.self
                )

                schema.addFullTextSearch(table: "posts", columns: ["title", "content"])

                schema.migration("2026-01-15_indexes") { db in
                    try db.create(index: "idx_posts_author", on: "posts", columns: ["authorId"])
                    try db.create(index: "idx_posts_created", on: "posts", columns: ["createdAt"])
                }
            }
        } catch {
            fatalError("Storage init failed: \(error)")
        }
    }()

    static var storage: Storage { context.facade }
}

// MARK: - View Models

@Observable
@MainActor
final class PostListViewModel {
    private(set) var posts: [Post] = []

    init() {
        Task {
            for await updatedPosts in AppStorage.storage.observeAllDistinct(
                Post.self,
                orderBy: "createdAt",
                ascending: false
            ) {
                self.posts = updatedPosts
            }
        }
    }

    func createPost(title: String, content: String, authorId: String) async {
        let post = Post(
            id: UUID().uuidString,
            title: title,
            content: content,
            authorId: authorId,
            createdAt: Date()
        )
        try? await AppStorage.storage.save(post)
    }

    func deletePost(id: String) async {
        try? await AppStorage.storage.delete(Post.self, id: id)
    }

    func search(query: String) async -> [Post] {
        guard !query.isEmpty else { return [] }
        let results = try? await AppStorage.storage.search(Post.self, query: query, limit: 20)
        return results?.map { $0.entity } ?? []
    }
}

// MARK: - Views

struct PostListView: View {
    @State private var viewModel = PostListViewModel()

    var body: some View {
        List(viewModel.posts) { post in
            VStack(alignment: .leading) {
                Text(post.title)
                    .font(.headline)
                Text(post.content)
                    .font(.caption)
                    .lineLimit(2)
            }
        }
    }
}
```

---

## Appendix B: Migration Guide

### From Direct GRDB to StorageKit

**Before:**
```swift
let pool = try DatabasePool(path: dbPath)

try pool.write { db in
    try db.create(table: "users") { t in
        t.column("id", .text).primaryKey()
        t.column("name", .text).notNull()
    }
}

struct User: Codable, FetchableRecord, PersistableRecord {
    var id: String
    var name: String
}

let users = try pool.read { db in
    try User.fetchAll(db)
}
```

**After:**
```swift
@StorageEntity
struct User {
    var id: String
    var name: String
}

let context = try StorageKit.start { schema in
    schema.addKVCache()
    schema.autoSchema(UserRecord.self)
}

let storage = context.facade
let users = try await storage.all(User.self)
```

---

## Appendix C: Troubleshooting

### Migration Errors

**Problem:** `Migration '2026-01-15_xxx' failed`

**Solutions:**
1. Check SQL syntax in migration body
2. Ensure tables exist before adding indexes/FTS
3. Use `skipIfTableExists` for CREATE migrations
4. Check GRDB logs for detailed error

---

### Observation Not Updating

**Problem:** SwiftUI view not updating on database changes

**Solutions:**
1. Ensure using `observeAll()` not `all()` (one-time fetch)
2. Verify Task is running (not cancelled)
3. Check MainActor delivery for @Observable classes
4. Use `observeAllDistinct()` if updates seem missed

---

### Performance Issues

**Problem:** Slow queries

**Solutions:**
1. Add indexes on frequently queried columns
2. Use batch inserts (`save([entities])`)
3. Use QueryBuilder instead of filtering in Swift
4. Check EXPLAIN QUERY PLAN for query optimization

---

## Appendix D: Best Practices

1. **Always use `@StorageEntity`** instead of manual Record creation
2. **Prefer `autoSchema()`** over manual migrations for table creation
3. **Use batch operations** for multiple inserts/updates
4. **Add indexes** for frequently queried columns
5. **Use `observeAllDistinct()`** to reduce UI churn
6. **Prefer `@StorageEmbedded`** over JSON for structured data
7. **Use FTS5** for search instead of LIKE queries
8. **Test with isolated databases** in unit tests
9. **Enable WAL mode** for better concurrency (default)
10. **Use namespaced cache keys** to avoid collisions

---

**End of Documentation**
