// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HaluMe",
    platforms: [.macOS(.v15), .iOS(.v18), .watchOS(.v11)],
    products: [.library(name: "HaluMeCore", targets: ["HaluMeCore"])],
    targets: [
        .target(name: "HaluMeCore"),
        .executableTarget(name: "HaluMe", dependencies: ["HaluMeCore"]),
        // XCTest and Swift Testing need full Xcode; checks run as `swift run money-check`.
        .executableTarget(name: "money-check", dependencies: ["HaluMeCore"], path: "Checks"),
    ]
)
