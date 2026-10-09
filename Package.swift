// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = []
var targets: [Target] = [
    // EPUB container and package parsing. No UI, no WebKit.
    .target(
        name: "EPUBKit",
        dependencies: [.product(name: "ZIPFoundation", package: "ZIPFoundation")]
    ),
    // Reader logic that does not need AppKit: styles, CSS analysis, settings models.
    .target(name: "AomidoriCore"),
    .testTarget(
        name: "EPUBKitTests",
        dependencies: ["EPUBKit", .product(name: "ZIPFoundation", package: "ZIPFoundation")]
    ),
    .testTarget(name: "AomidoriCoreTests", dependencies: ["AomidoriCore"]),
]

// The application needs AppKit and WebKit. The libraries and their tests also build elsewhere.
#if os(macOS)
products.append(.executable(name: "Aomidori", targets: ["Aomidori"]))
targets.append(.executableTarget(name: "Aomidori", dependencies: ["EPUBKit", "AomidoriCore"]))
#endif

let package = Package(
    name: "Aomidori",
    platforms: [.macOS("27.0")],
    products: products,
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: targets
)
