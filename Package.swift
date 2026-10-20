// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LaunchDock",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "LaunchDock", targets: ["LaunchDock"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .target(name: "ProcessSupport"),
        .target(name: "LaunchDockCore", dependencies: ["ProcessSupport"]),
        .executableTarget(name: "LaunchDock", dependencies: ["LaunchDockCore", .product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "LaunchDockChecks", dependencies: ["LaunchDockCore"], path: "Tests/LaunchDockChecks")
    ]
)
