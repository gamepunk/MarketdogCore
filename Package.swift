// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "MarketdogCore",
    platforms: [
        .macOS(.v14),
        .iOS(.v16)
    ],
    products: [
        .library(name: "MarketdogCore", targets: ["MarketdogCore"])
    ],
    targets: [
        .target(name: "MarketdogCore", resources: [
            .copy("Resources/CoinIcons"),
            .copy("Resources/WEB3ICONS-LICENSE.txt")
        ]),
        .executableTarget(name: "CoinIconHealth", dependencies: ["MarketdogCore"]),
        .testTarget(name: "MarketdogCoreTests", dependencies: ["MarketdogCore"])
    ]
)
