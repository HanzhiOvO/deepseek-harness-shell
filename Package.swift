// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "DeepSeekHarnessShell",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .target(
            name: "DeepSeekHarnessCore",
            path: "Sources/DeepSeekHarnessCore"
        ),
        .executableTarget(
            name: "DeepSeekHarnessShell",
            dependencies: ["DeepSeekHarnessCore"],
            path: "Sources/DeepSeekHarnessShell"
        ),
        .executableTarget(
            name: "DeepSeekHarnessCoreSelfTests",
            dependencies: ["DeepSeekHarnessCore"],
            path: "Tests/DeepSeekHarnessCoreSelfTests"
        ),
        .executableTarget(
            name: "DeepSeekHarnessSmoke",
            dependencies: ["DeepSeekHarnessCore"],
            path: "Tests/DeepSeekHarnessSmoke"
        ),
        .executableTarget(
            name: "DeepSeekHarnessPluginSmoke",
            dependencies: ["DeepSeekHarnessCore"],
            path: "Tests/DeepSeekHarnessPluginSmoke"
        )
    ]
)
