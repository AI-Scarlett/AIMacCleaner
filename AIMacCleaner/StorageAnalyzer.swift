import SwiftUI
import Foundation
import Combine

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
            scanProgress = "正在扫描存储空间..."
            categories.removeAll()
        }

        let fm = FileManager.default
        var results: [StorageCategory] = []

        let systemSize = await scanCategory(
            id: "system", name: "系统文件", icon: "gear", color: .gray,
            paths: ["/System", "/Library", "/private/var", "/usr"],
            fm: fm
        )
        results.append(systemSize)

        await MainActor.run { scanProgress = "扫描应用文件..." }
        let appSize = await scanCategory(
            id: "apps", name: "APP 文件", icon: "app.fill", color: .cyan,
            paths: ["/Applications", "\(home)/Applications", "\(home)/Library/Application Support", "\(home)/Library/Caches"],
            fm: fm
        )
        results.append(appSize)

        await MainActor.run { scanProgress = "扫描文稿..." }
        let docsSize = await scanCategory(
            id: "documents", name: "文稿", icon: "doc.fill", color: .blue,
            paths: ["\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads", "\(home)/Movies", "\(home)/Music", "\(home)/Pictures"],
            fm: fm
        )
        results.append(docsSize)

        await MainActor.run { scanProgress = "扫描 Agent 文件..." }
        let agentDirs = getAgentDirs()
        let agentSize = await scanCategory(
            id: "agents", name: "Agent", icon: "cpu", color: .purple,
            paths: agentDirs,
            fm: fm
        )
        results.append(agentSize)

        await MainActor.run { scanProgress = "扫描依赖..." }
        let depDirs = getDependencyDirs()
        let depSize = await scanCategory(
            id: "dependencies", name: "依赖", icon: "cube.box", color: .orange,
            paths: depDirs,
            fm: fm
        )
        results.append(depSize)

        await MainActor.run { scanProgress = "扫描其它..." }
        let otherPaths = getOtherDirs(exclude: agentDirs + depDirs)
        let otherSize = await scanCategory(
            id: "other", name: "其它", icon: "folder.fill", color: .brown,
            paths: otherPaths,
            fm: fm
        )
        results.append(otherSize)

        let total = results.reduce(Int64(0)) { $0 + $1.size }

        await MainActor.run {
            categories = results
            totalUsed = total
            isScanning = false
            scanProgress = ""
        }
    }

    private func scanCategory(id: String, name: String, icon: String, color: Color, paths: [String], fm: FileManager) async -> StorageCategory {
        let result = await Task.detached(priority: .userInitiated) {
            var totalSize: Int64 = 0
            var files: [StorageFile] = []
            let maxFiles = 200

            for path in paths {
                var isDir: ObjCBool = false
                guard fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue else { continue }
                let (size, items) = self.scanDirectory(at: path, maxDepth: 3, maxFiles: maxFiles - files.count, fm: fm)
                totalSize += size
                files.append(contentsOf: items)
            }

            files.sort { $0.size > $1.size }
            if files.count > maxFiles {
                files = Array(files.prefix(maxFiles))
            }

            return StorageCategory(id: id, name: name, icon: icon, color: color, size: totalSize, path: paths.first ?? "", files: files)
        }.value

        return result
    }

    private func scanDirectory(at path: String, maxDepth: Int, maxFiles: Int, fm: FileManager) -> (Int64, [StorageFile]) {
        var totalSize: Int64 = 0
        var files: [StorageFile] = []

        guard maxDepth > 0, maxFiles > 0 else { return (0, []) }

        let contents: [String]
        do {
            contents = try fm.contentsOfDirectory(atPath: path)
        } catch {
            let attrs = try? fm.attributesOfItem(atPath: path)
            let size = (attrs?[.size] as? Int64) ?? 0
            return (size, [])
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
                if size > 1048576 {
                    files.append(StorageFile(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        size: subSize,
                        createdDate: created,
                        modifiedDate: modified,
                        isDirectory: true
                    ))
                }
            } else {
                totalSize += size
                if size > 1048576 {
                    files.append(StorageFile(
                        id: fullPath,
                        name: name,
                        path: fullPath,
                        size: size,
                        createdDate: created,
                        modifiedDate: modified,
                        isDirectory: false
                    ))
                }
            }
        }

        return (totalSize, files)
    }

    private func getAgentDirs() -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []
        let agentNames = [
            "Trae", "CodeBuddy", "Claude", "Codex", "Hermes", "yi-code", "Cline",
            "MiniMax", "Cherry Studio", "LM Studio", "OpenClaw", "QClaw",
            "CodeArts", "Kimi", "DeepSeek", "Augment", "Copilot", "Aider",
            "Cody", "Tabby", "Warp", "ChatGPT", "Cursor", "Whitzard",
            "豆包", "通义千问", "通义灵码", "智谱AI", "讯飞星火"
        ]
        for name in agentNames {
            let dotDir = "\(home)/.\(name.lowercased())"
            if fm.fileExists(atPath: dotDir) { dirs.append(dotDir) }
            let configDir = "\(home)/.config/\(name.lowercased())"
            if fm.fileExists(atPath: configDir) { dirs.append(configDir) }
        }
        return dirs
    }

    private func getDependencyDirs() -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []
        let depPaths = [
            "\(home)/.nvm", "\(home)/.pyenv", "\(home)/.conda", "\(home)/.cargo",
            "\(home)/.android", "\(home)/.ohos", "\(home)/.harmony",
            "\(home)/.gradle", "\(home)/.m2", "\(home)/.npm", "\(home)/.pnpm-store",
            "\(home)/.cocoapods", "\(home)/.local", "\(home)/.go",
            "\(home)/.julia", "\(home)/.rustup"
        ]
        for path in depPaths {
            if fm.fileExists(atPath: path) { dirs.append(path) }
        }

        if fm.fileExists(atPath: "/opt/homebrew") { dirs.append("/opt/homebrew") }
        if fm.fileExists(atPath: "/usr/local/Cellar") { dirs.append("/usr/local/Cellar") }

        return dirs
    }

    private func getOtherDirs(exclude excludedPaths: [String]) -> [String] {
        let fm = FileManager.default
        var dirs: [String] = []
        let excludeSet = Set(excludedPaths)

        guard let contents = try? fm.contentsOfDirectory(atPath: home) else { return dirs }

        for name in contents {
            guard name.hasPrefix(".") else { continue }
            let fullPath = "\(home)/\(name)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
            guard !excludeSet.contains(fullPath) else { continue }
            dirs.append(fullPath)
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

        let requestBody: [String: Any] = [
            "model": config.model ?? "deepseek-chat",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 300
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }

        var request = URLRequest(url: URL(string: apiBase + "/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            return content
        } catch {
            return nil
        }
    }

    func analyzeCategoryWithAI(category: StorageCategory, config: AIConfig) async -> String? {
        guard let apiKey = config.apiKey, !apiKey.isEmpty, let apiBase = config.apiBase else { return nil }

        let topFiles = category.files.prefix(20).map { "- \($0.name): \($0.sizeFormatted)" }.joined(separator: "\n")

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

        let requestBody: [String: Any] = [
            "model": config.model ?? "deepseek-chat",
            "messages": [["role": "user", "content": prompt]],
            "temperature": 0.3,
            "max_tokens": 500
        ]

        guard let bodyData = try? JSONSerialization.data(withJSONObject: requestBody) else { return nil }

        var request = URLRequest(url: URL(string: apiBase + "/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 30

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let content = message["content"] as? String else { return nil }
            return content
        } catch {
            return nil
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
