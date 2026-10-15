// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaunchDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LaunchDock", targets: ["LaunchDock"])],
    targets: [
        .target(name: "ProcessSupport"),
        .target(name: "LaunchDockCore", dependencies: ["ProcessSupport"]),
        .executableTarget(name: "LaunchDock", dependencies: ["LaunchDockCore"]),
        .executableTarget(name: "LaunchDockChecks", dependencies: ["LaunchDockCore"], path: "Tests/LaunchDockChecks")
    ]
)
