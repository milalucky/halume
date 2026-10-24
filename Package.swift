// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaluMoney",
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11)],
    products: [.library(name: "HaluMoneyCore", targets: ["HaluMoneyCore"])],
    targets: [
        .target(name: "HaluMoneyCore"),
        .executableTarget(name: "HaluMoney", dependencies: ["HaluMoneyCore"]),
        // XCTest and Swift Testing need full Xcode; checks run as `swift run money-check`.
        .executableTarget(name: "money-check", dependencies: ["HaluMoneyCore"], path: "Checks"),
    ]
)
