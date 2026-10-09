// swift-tools-version: 6.0
import PackageDescription

var products: [Product] = []
var dependencies: [Package.Dependency] = [
    .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
]
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
// Sparkle 2 (automatic updates) is the official binary package: a signed Sparkle.framework,
// plus the tools to make and sign updates in .build/artifacts/sparkle/Sparkle/bin.
// scripts/bundle.sh embeds the framework in Contents/Frameworks, where the rpath points.
#if os(macOS)
dependencies.append(.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.10.0"))
products.append(.executable(name: "Aomidori", targets: ["Aomidori"]))
targets.append(.executableTarget(
    name: "Aomidori",
    dependencies: ["EPUBKit", "AomidoriCore", .product(name: "Sparkle", package: "Sparkle")],
    linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
))
#endif

let package = Package(
    name: "Aomidori",
    platforms: [.macOS("27.0")],
    products: products,
    dependencies: dependencies,
    targets: targets
)
