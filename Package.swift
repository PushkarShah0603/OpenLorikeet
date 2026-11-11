// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OpenLorikeet",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "ConversionCore", targets: ["ConversionCore"]),
        .executable(name: "OpenLorikeet", targets: ["OpenLorikeetApp"]),
    ],
    targets: [
        .target(name: "ConversionCore"),
        .executableTarget(name: "OpenLorikeetApp", dependencies: ["ConversionCore"], resources: [.copy("Assets")]),
        .executableTarget(name: "CoreChecks", dependencies: ["ConversionCore"], path: "Tests/CoreChecks"),
    ]
)
