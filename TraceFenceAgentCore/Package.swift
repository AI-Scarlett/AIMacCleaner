// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TraceFenceAgentCore",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TraceFenceAgentCore", targets: ["TraceFenceAgentCore"]),
        .executable(name: "TraceFenceAgentCoreUpdater", targets: ["TraceFenceAgentCoreUpdater"]),
        .executable(name: "TraceFenceClaudeAdapter", targets: ["TraceFenceClaudeAdapter"]),
        .executable(name: "TraceFenceUniversalAdapter", targets: ["TraceFenceUniversalAdapter"])
    ],
    targets: [
        .executableTarget(name: "TraceFenceAgentCore"),
        .executableTarget(name: "TraceFenceAgentCoreUpdater"),
        .executableTarget(name: "TraceFenceClaudeAdapter"),
        .executableTarget(
            name: "TraceFenceUniversalAdapter",
            linkerSettings: [.linkedLibrary("sqlite3")]
        )
    ]
)
