// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexProcessManager",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CodexProcessManagerCore",
            targets: ["CodexProcessManagerCore"]
        ),
        .executable(
            name: "CodexProcessManager",
            targets: ["CodexProcessManager"]
        ),
        .executable(
            name: "CodexProcessManagerCoreTestRunner",
            targets: ["CodexProcessManagerCoreTestRunner"]
        )
    ],
    targets: [
        .target(
            name: "CodexProcessManagerCore"
        ),
        .executableTarget(
            name: "CodexProcessManager",
            dependencies: ["CodexProcessManagerCore"]
        ),
        .executableTarget(
            name: "CodexProcessManagerCoreTestRunner",
            dependencies: ["CodexProcessManagerCore"],
            path: "Tests/CodexProcessManagerCoreTestRunner"
        )
    ],
    swiftLanguageModes: [.v5]
)
