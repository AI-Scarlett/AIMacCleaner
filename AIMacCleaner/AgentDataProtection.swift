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

    /// Permanent cleanup guard shared by scan and execution revalidation.
    ///
    /// The inventory intentionally hides whole Agent roots, but cleanup rules may still target a
    /// narrow, known-rebuildable child such as `~/.codex/versions`. This guard therefore protects
    /// irreplaceable subtrees and credentials rather than blanket-blocking every Agent directory.
    static func cleanupProtectionReason(
        path rawPath: String,
        homeDirectory rawHome: String
    ) -> String? {
        let path = URL(fileURLWithPath: rawPath).standardizedFileURL.path
        let home = URL(fileURLWithPath: rawHome, isDirectory: true).standardizedFileURL.path
        guard path != home, path.hasPrefix(home + "/") else { return nil }

        let relative = String(path.dropFirst(home.count + 1)).lowercased()
        let components = relative.split(separator: "/").map(String.init)

        if relative == ".ollama/models" || relative.hasPrefix(".ollama/models/")
            || relative == ".cache/huggingface" || relative.hasPrefix(".cache/huggingface/") {
            return "downloaded AI model data is protected"
        }

        if applicationSupportRoots.map({ $0.lowercased() }).contains(where: { root in
            relative == root || relative.hasPrefix(root + "/")
        }) {
            return "active Agent workspace state is protected"
        }

        guard let agentRoot = components.first, hiddenRootNames.contains(agentRoot) else {
            return nil
        }

        let protectedSubtreeNames: Set<String> = [
            "sessions", "archived_sessions", "projects", "memories", "plans", "skills",
            "media_objects", "worktrees", "file-history", "session-env"
        ]
        if components.dropFirst().contains(where: protectedSubtreeNames.contains) {
            return "Agent conversations, media, and workspace state are protected"
        }

        let protectedRootFiles: Set<String> = [
            "auth.json", "credentials.json", "history.jsonl", "config.toml", "settings.json"
        ]
        if components.count == 2, protectedRootFiles.contains(components[1]) {
            return "Agent credentials, history, and configuration are protected"
        }

        return nil
    }
}
