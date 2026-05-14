import SwiftUI
import Foundation

enum FileRiskLevel: String, Codable {
    case safe = "可清理"
    case caution = "谨慎清理"
    case keep = "保留"
    case unknown = "未知"

    var color: Color {
        switch self {
        case .safe: .green
        case .caution: .orange
        case .keep: .red
        case .unknown: .gray
        }
    }

    var icon: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .keep: "xmark.circle.fill"
        case .unknown: "questionmark.circle.fill"
        }
    }
}

class StorageAnalyzer: ObservableObject {
    @Published var categories: [StorageCategory] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: String = ""
    @Published var totalUsed: Int64 = 0
    @Published var aiAnalysisResult: String?

    private let home = NSHomeDirectory()

    func scanStorage() async {
        await MainActor.run {
            isScanning = true
            scanProgress = "正在扫描磁盘..."
            categories.removeAll()
        }

        let fm = FileManager.default
        var results: [StorageCategory] = []

        await MainActor.run { scanProgress = "扫描系统文件..." }
        let systemPaths = ["/System", "/Library", "/usr", "/sbin", "/bin", "/etc", "/var", "/tmp"]
        let systemSize = await scanCategory(id: "system", name: "系统文件", icon: "gear", color: .gray, paths: systemPaths, fm: fm)
        results.append(systemSize)

        await MainActor.run { scanProgress = "扫描应用..." }
        let appPaths = ["/Applications", "\(home)/Applications", "/Applications/Utilities"]
        let appSize = await scanCategory(id: "apps", name: "应用程序", icon: "app.fill", color: .cyan, paths: appPaths, fm: fm)
        results.append(appSize)

        await MainActor.run { scanProgress = "扫描应用数据..." }
        let appDataPaths = [
            "\(home)/Library/Application Support", "\(home)/Library/Caches", "\(home)/Library/Containers",
            "\(home)/Library/Group Containers", "\(home)/Library/HTTPStorages", "\(home)/Library/WebKit",
            "\(home)/Library/Saved Application State", "\(home)/Library/Preferences",
        ]
        let appDataSize = await scanCategory(id: "appdata", name: "应用数据", icon: "archivebox", color: .teal, paths: appDataPaths, fm: fm)
        results.append(appDataSize)

        await MainActor.run { scanProgress = "扫描文稿..." }
        let docsPaths = [
            "\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads", "\(home)/Movies",
            "\(home)/Music", "\(home)/Pictures", "\(home)/Library/Mobile Documents",
        ]
        let docsSize = await scanCategory(id: "documents", name: "文稿", icon: "doc.fill", color: .blue, paths: docsPaths, fm: fm)
        results.append(docsSize)

        await MainActor.run { scanProgress = "扫描 Agent..." }
        let agentDirs = getAgentDirs()
        let agentSize = await scanCategory(id: "agents", name: "Agent", icon: "cpu", color: .purple, paths: agentDirs, fm: fm)
        results.append(agentSize)

        await MainActor.run { scanProgress = "扫描依赖..." }
        let depDirs = getDependencyDirs()
        let depSize = await scanCategory(id: "dependencies", name: "依赖", icon: "cube.box", color: .orange, paths: depDirs, fm: fm)
        results.append(depSize)

        await MainActor.run { scanProgress = "扫描日志与缓存..." }
        let logsPaths = ["\(home)/Library/Logs", "/Library/Logs", "/private/var/log"]
        let logsSize = await scanCategory(id: "logs", name: "日志与缓存", icon: "doc.text.fill", color: .brown, paths: logsPaths, fm: fm)
        results.append(logsSize)

        await MainActor.run { scanProgress = "扫描其它..." }
        let otherDirs = await findOtherDirs(exclude: systemPaths + appPaths + appDataPaths + docsPaths + agentDirs + depDirs + logsPaths, fm: fm)
        let otherSize = await scanCategory(id: "other", name: "其它", icon: "folder.fill", color: .indigo, paths: otherDirs, fm: fm)
        if otherSize.size > 0 { results.append(otherSize) }

        let total = results.reduce(Int64(0)) { $0 + $1.size }

        await MainActor.run {
            categories = results
            totalUsed = total
            isScanning = false
            scanProgress = ""
        }
    }

    private func scanCategory(id: String, name: String, icon: String, color: Color, paths: [String], fm: FileManager) async -> StorageCategory {
        return await Task.detached(priority: .userInitiated) {
            var totalSize: Int64 = 0
            var files: [StorageFile] = []
            let maxFiles = 3000

            for path in paths {
                let expanded = NSString(string: path).expandingTildeInPath
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else { continue }
                let (size, items) = self.scanDirectory(at: expanded, maxDepth: 6, maxFiles: maxFiles - files.count, fm: fm)
                totalSize += size
                files.append(contentsOf: items)
            }

            files.sort { $0.size > $1.size }
            if files.count > maxFiles {
                files = Array(files.prefix(maxFiles))
            }

            for i in 0..<files.count {
                files[i] = self.assessRisk(for: files[i])
            }

            return StorageCategory(id: id, name: name, icon: icon, color: color, size: totalSize, path: paths.first ?? "", files: files)
        }.value
    }

    private func assessRisk(for file: StorageFile) -> StorageFile {
        let path = file.path.lowercased()
        let ext = (file.path as NSString).pathExtension.lowercased()

        let safePatterns = ["cache", "tmp", "temp", "log", "trash", "deprecated", "backup"]
        let cautionPatterns = ["library", "preferences", "support", "container", "plist", "config"]
        let keepPatterns = ["system", "kernel", "framework", "bin/", "sbin/", "usr/"]

        let safeExtensions = ["log", "tmp", "bak", "cache", "crash"]
        let keepExtensions = ["app", "kext", "framework", "dylib", "bundle"]

        for pattern in safePatterns where path.contains(pattern) {
            return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .safe)
        }
        if safeExtensions.contains(ext) {
            return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .safe)
        }
        for pattern in keepPatterns where path.contains(pattern) {
            return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .keep)
        }
        if keepExtensions.contains(ext) {
            return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .keep)
        }
        for pattern in cautionPatterns where path.contains(pattern) {
            return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .caution)
        }

        if file.size > 500 * 1024 * 1024 {
            return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .caution)
        }

        return StorageFile(id: file.id, name: file.name, path: file.path, size: file.size, createdDate: file.createdDate, modifiedDate: file.modifiedDate, isDirectory: file.isDirectory, aiAnalysis: file.aiAnalysis, riskLevel: .unknown)
    }

    private func scanDirectory(at path: String, maxDepth: Int, maxFiles: Int, fm: FileManager) -> (Int64, [StorageFile]) {
        var totalSize: Int64 = 0
        var files: [StorageFile] = []
        guard maxDepth > 0, maxFiles > 0 else { return (0, []) }
        guard let contents = try? fm.contentsOfDirectory(atPath: path) else {
            if let attrs = try? fm.attributesOfItem(atPath: path) {
                return ((attrs[.size] as? Int64) ?? 0, [])
            }
            return (0, [])
        }
        for name in contents {
            guard files.count < maxFiles else { break }
            let fullPath = (path as NSString).appendingPathComponent(name)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }
            let attrs = try? fm.attributesOfItem(atPath: fullPath)
            let size = (attrs?[.size] as? Int64) ?? 0
            let created = attrs?[.creationDate] as? Date
            let modified = attrs?[.modificationDate] as? Date
            if isDir.boolValue {
                let (subSize, subFiles) = scanDirectory(at: fullPath, maxDepth: maxDepth - 1, maxFiles: maxFiles - files.count, fm: fm)
                totalSize += subSize
                files.append(contentsOf: subFiles)
                if subSize > 104857600 {
                    files.append(StorageFile(id: fullPath, name: name, path: fullPath, size: subSize, createdDate: created, modifiedDate: modified, isDirectory: true))
                }
            } else {
                totalSize += size
                if size > 102400 {
                    files.append(StorageFile(id: fullPath, name: name, path: fullPath, size: size, createdDate: created, modifiedDate: modified, isDirectory: false))
                }
            }
        }
        return (totalSize, files)
    }

    private func findOtherDirs(exclude: [String], fm: FileManager) async -> [String] {
        let excludeSet = Set(exclude)
        return await Task.detached {
            var localDirs: [String] = []
            if let homeContents = try? fm.contentsOfDirectory(atPath: self.home) {
                for name in homeContents {
                    guard name.hasPrefix(".") else { continue }
                    let fullPath = "\(self.home)/\(name)"
                    var isDir: ObjCBool = false
                    guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
                    guard !excludeSet.contains(fullPath) else { continue }
                    localDirs.append(fullPath)
                }
            }
            let systemDirs = ["/private"].filter { !excludeSet.contains($0) }
            return localDirs + systemDirs
        }.value
    }

    private func getAgentDirs() -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []
        let agentNames = ["trae", "codebuddy", "claude", "codex", "hermes", "yi-code", "cline", "minimax", "cherrystudio", "lmstudio", "openclaw", "qclaw", "codearts", "kimi", "deepseek", "augment", "copilot", "aider", "cody", "tabby", "warp", "chatgpt", "cursor", "whitzard", "doubao", "qwen", "zhipu", "spark", "tongyi"]
        for name in agentNames {
            let dotDir = "\(home)/.\(name)"
            if fm.fileExists(atPath: dotDir) { dirs.append(dotDir) }
            let configDir = "\(home)/.config/\(name)"
            if fm.fileExists(atPath: configDir) { dirs.append(configDir) }
            let supportDir = "\(home)/Library/Application Support/\(name.capitalized)"
            if fm.fileExists(atPath: supportDir) { dirs.append(supportDir) }
        }
        return dirs
    }

    private func getDependencyDirs() -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []
        let depPaths = ["\(home)/.nvm", "\(home)/.pyenv", "\(home)/.conda", "\(home)/.cargo", "\(home)/.android", "\(home)/.ohos", "\(home)/.harmony", "\(home)/.gradle", "\(home)/.m2", "\(home)/.npm", "\(home)/.pnpm-store", "\(home)/.cocoapods", "\(home)/.local", "\(home)/.go", "\(home)/.julia", "\(home)/.rustup", "\(home)/.gem", "\(home)/Library/Developer", "/opt/homebrew", "/usr/local/Cellar"]
        for path in depPaths {
            let expanded = NSString(string: path).expandingTildeInPath
            if fm.fileExists(atPath: expanded) { dirs.append(expanded) }
        }
        return dirs
    }

    func analyzeFileWithAI(file: StorageFile, config: AIConfig) async -> String? {
        guard let apiKey = config.apiKey, !apiKey.isEmpty, let apiBase = config.apiBase else { return nil }
        let prompt = """
        分析以下文件/目录是否可以安全删除或清理：
        - 名称: \(file.name)
        - 路径: \(file.path)
        - 大小: \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))
        - 类型: \(file.isDirectory ? "目录" : "文件")
        \(file.modifiedDate != nil ? "- 最后修改: \(formatDate(file.modifiedDate!))" : "")
        请简洁回答：
        1. 这是什么文件/目录？
        2. 是否可以删除？(可以删除/谨慎删除/不要删除)
        3. 删除后有什么影响？
        """
        let requestBody: [String: Any] = ["model": config.model ?? "deepseek-chat", "messages": [["role": "user", "content": prompt]], "temperature": 0.3, "max_tokens": 300]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        let urlString = apiBase.hasSuffix("/v1") ? "\(apiBase)/chat/completions" : "\(apiBase)/v1/chat/completions"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            return content
        } catch { return nil }
    }

    func analyzeCategoryWithAI(category: StorageCategory, config: AIConfig) async -> String? {
        guard let apiKey = config.apiKey, !apiKey.isEmpty, let apiBase = config.apiBase else { return nil }
        let topFiles = category.files.prefix(20).map { "- \($0.name): \($0.sizeFormatted) (\($0.path))" }.joined(separator: "\n")
        let prompt = """
        分析以下「\(category.name)」类别的存储占用，判断哪些可以删除清理：
        - 总占用: \(category.sizeFormatted)
        - 路径: \(category.path)
        - 主要文件：
        \(topFiles)
        请简洁回答：
        1. 该类别的主要存储占用是什么？
        2. 哪些可以安全清理？
        3. 哪些需要谨慎处理？
        4. 预计可释放多少空间？
        """
        let requestBody: [String: Any] = ["model": config.model ?? "deepseek-chat", "messages": [["role": "user", "content": prompt]], "temperature": 0.3, "max_tokens": 500]
        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }
        let urlString = apiBase.hasSuffix("/v1") ? "\(apiBase)/chat/completions" : "\(apiBase)/v1/chat/completions"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            return content
        } catch { return nil }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
