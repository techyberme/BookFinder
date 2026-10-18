// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ZahoriKit",
    defaultLocalization: "es",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ZahoriCore", targets: ["ZahoriCore"]),
        .library(name: "ZahoriKit", targets: ["ZahoriKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0"),
    ],
    targets: [
        // Pure value types, geo + proximity, text rules. Foundation only: no UI, no network.
        .target(
            name: "ZahoriCore",
            resources: [.process("Resources")]
        ),
        // Parsing (SwiftSoup / XMLParser), networking, batch checks, cache.
        .target(
            name: "ZahoriKit",
            dependencies: ["ZahoriCore", "SwiftSoup"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ZahoriKitTests",
            dependencies: ["ZahoriCore", "ZahoriKit"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
