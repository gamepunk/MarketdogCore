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
        .target(name: "MarketdogCore"),
        .testTarget(name: "MarketdogCoreTests", dependencies: ["MarketdogCore"])
    ]
)
