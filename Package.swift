// swift-tools-version: 6.0
import PackageDescription
import CompilerPluginSupport

let package = Package(
  name: "StorageKit",
  platforms: [
    .iOS(.v18),
    .macOS(.v15)
  ],
  products: [
    .library(name: "StorageCore", targets: ["StorageCore"]),
    .library(name: "StorageGRDB", targets: ["StorageGRDB"]),
    .library(name: "StorageRepo", targets: ["StorageRepo"]),
    .library(name: "StorageKit", targets: ["StorageKit"]),
    .library(name: "StorageKitMacros", targets: ["StorageKitMacros"])
  ],
  dependencies: [
    .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.6.1"),
    .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "600.0.0")
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
      "StorageKitMacros",
      .product(name: "GRDB", package: "GRDB.swift")
    ]),

    // MARK: - Macros
    .macro(
      name: "StorageKitMacrosPlugin",
      dependencies: [
        .product(name: "SwiftSyntax", package: "swift-syntax"),
        .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
        .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
      ]
    ),
    .target(
      name: "StorageKitMacros",
      dependencies: [
        "StorageCore",
        "StorageGRDB",
        "StorageKitMacrosPlugin",
        .product(name: "GRDB", package: "GRDB.swift")
      ]
    ),

    // MARK: - Tests
    .testTarget(
      name: "StorageKitMacrosTests",
      dependencies: [
        "StorageKitMacros",
        "StorageKitMacrosPlugin",
        .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
      ]
    ),
  ]
)
