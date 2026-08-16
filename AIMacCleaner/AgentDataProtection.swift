import Foundation

/// Shared protection rules used by both the native disk advisor and the Disk Cleanup plugin.
/// Agent state is analysis-only: it can contribute aggregate storage and duplicate-media
/// statistics, but file inventory and generic cleanup discovery must not expose it as user-file
/// deletion candidates.
enum AgentDataProtection {
    static let hiddenRootNames: Set<String> = [
        ".agentgpt", ".agentscope", ".aider", ".amazon-q", ".amp", ".augment",
        ".autogenstudio", ".browser-use", ".camel", ".claude", ".cline",
        ".codebuddy", ".codebuddy-agent", ".codeium", ".codex", ".continue",
        ".crewai", ".cursor", ".cursor-agent", ".deepseek", ".deer-flow",
        ".deerflow", ".dify", ".doubao", ".gemini", ".glm", ".grok",
        ".hermes", ".huginn", ".kimi", ".langgraph", ".lingma", ".lobehub",
        ".metagpt", ".minimax", ".openclaw", ".opencode", ".openhands",
        ".pi-agent", ".qoder", ".qwen", ".roo", ".swarm", ".tabnine", ".ui-tars",
        ".windsurf-agent"
    ]

    private static let applicationSupportRoots = [
        "Library/Application Support/Cursor/User/workspaceStorage",
        "Library/Application Support/Trae/User/workspaceStorage",
        "Library/Application Support/CodeBuddy CN/User/workspaceStorage"
    ]

    static func containsProtectedData(path rawPath: String, homeDirectory rawHome: String) -> Bool {
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let home = URL(fileURLWithPath: rawHome, isDirectory: true).standardizedFileURL.path
        guard path != home, path.hasPrefix(home + "/") else { return false }
        let relative = String(path.dropFirst(home.count + 1))
        let components = relative.split(separator: "/").map { $0.lowercased() }
        if components.contains(where: hiddenRootNames.contains) { return true }
        return applicationSupportRoots.contains { root in
            relative == root || relative.hasPrefix(root + "/")
        }
    }
}
