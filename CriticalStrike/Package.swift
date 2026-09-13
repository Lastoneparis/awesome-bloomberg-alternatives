// swift-tools-version:5.9
import PackageDescription

// CriticalStrikeCore is intentionally free of UIKit / SceneKit / StoreKit so the whole
// simulation (ballistics, movement, game modes, netcode, economy, progression) can be
// unit tested on any platform, and so the dedicated server can reuse it verbatim.
let package = Package(
    name: "CriticalStrike",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [
        .library(name: "CriticalStrikeCore", targets: ["CriticalStrikeCore"])
    ],
    targets: [
        .target(
            name: "CriticalStrikeCore",
            path: "Sources/CriticalStrikeCore"
        ),
        .testTarget(
            name: "CriticalStrikeCoreTests",
            dependencies: ["CriticalStrikeCore"],
            path: "Tests/CriticalStrikeCoreTests"
        )
    ]
)
