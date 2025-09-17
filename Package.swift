// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "StorageKit",
  platforms: [
    .iOS(.v18)
  ],
  products: [
    .library(name: "StorageCore", targets: ["StorageCore"]),
    .library(name: "StorageGRDB", targets: ["StorageGRDB"]),
    .library(name: "StorageRepo", targets: ["StorageRepo"]),
    .library(name: "StorageKit", targets: ["StorageKit"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.6.1")
  ],
  targets: [
    .target(name: "StorageCore", dependencies: []),
    .target(name: "StorageGRDB", dependencies: [
      "StorageCore",
      .product(name: "GRDB", package: "GRDB.swift")
    ]),
    .target(name: "StorageRepo", dependencies: [
      "StorageCore",
      "StorageGRDB",
      .product(name: "GRDB", package: "GRDB.swift")
    ]),
    .target(name: "StorageKit", dependencies: [
      "StorageCore",
      "StorageGRDB",
      "StorageRepo",
      .product(name: "GRDB", package: "GRDB.swift")
    ]),
  ]
)
