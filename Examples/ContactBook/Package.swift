// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ContactBook",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ContactBook", targets: ["ContactBook"]),
    ],
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
)
