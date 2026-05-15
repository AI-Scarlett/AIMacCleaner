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
        let home = NSHomeDirectory()

        var systemTotal: Int64 = 0
        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        if let values = try? url.resourceValues(forKeys: keys),
           let totalCap = values.volumeTotalCapacity,
           let available = values.volumeAvailableCapacityForImportantUsage {
            systemTotal = Int64(totalCap) - Int64(available)
        }

        await MainActor.run { scanProgress = "扫描应用程序..." }
        let appResult = await scanCategoryWithDu(
            id: "apps", name: "应用程序", icon: "app.fill", color: .cyan,
            paths: ["/Applications", "\(home)/Applications"]
        )

        await MainActor.run { scanProgress = "扫描文稿..." }
        let docsResult = await scanCategoryWithDu(
            id: "documents", name: "文稿", icon: "doc.fill", color: .blue,
            paths: [
                "\(home)/Desktop", "\(home)/Documents", "\(home)/Downloads",
                "\(home)/Movies", "\(home)/Music", "\(home)/Pictures",
            ]
        )

        await MainActor.run { scanProgress = "计算系统数据..." }
        let systemSize = systemTotal - appResult.size - docsResult.size
        let systemDataCat = StorageCategory(
            id: "system", name: "系统数据", icon: "gearshape.2", color: .gray,
            size: max(systemSize, 0),
            path: "\(home)/Library",
            files: []
        )

        await MainActor.run { scanProgress = "扫描其它..." }
        var otherPaths: [String] = []
        for item in (try? fm.contentsOfDirectory(atPath: home)) ?? [] {
            if item.hasPrefix(".") { continue }
            let fullPath = "\(home)/\(item)"
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: fullPath, isDirectory: &isDir), isDir.boolValue else { continue }
            let known = Set(["Desktop", "Documents", "Downloads", "Movies", "Music", "Pictures", "Library", "Applications", "Public"])
            if !known.contains(item) {
                otherPaths.append(fullPath)
            }
        }
        let otherResult = otherPaths.isEmpty
            ? StorageCategory(id: "other", name: "其它", icon: "folder.fill", color: .indigo, size: 0, path: home, files: [])
            : await scanCategoryWithDu(id: "other", name: "其它", icon: "folder.fill", color: .indigo, paths: otherPaths)

        let results = [appResult, docsResult, systemDataCat, otherResult].filter { $0.size > 0 || $0.id == "other" }

        await MainActor.run {
            categories = results
            totalUsed = systemTotal
            isScanning = false
            scanProgress = ""
        }
    }

    private func scanCategoryWithDu(id: String, name: String, icon: String, color: Color, paths: [String]) async -> StorageCategory {
        return await Task.detached(priority: .userInitiated) {
            var totalSize: Int64 = 0
            var files: [StorageFile] = []
            let fm = FileManager.default
            let home = NSHomeDirectory()
            let maxFiles = 2000

            for path in paths {
                let expanded = NSString(string: path).expandingTildeInPath
                guard fm.fileExists(atPath: expanded) else { continue }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                process.arguments = ["-sk", expanded]
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()

                if let data = try? pipe.fileHandleForReading.readToEnd(),
                   let output = String(data: data, encoding: .utf8) {
                    let lines = output.trimmingCharacters(in: .whitespacesAndNewlines).components(separatedBy: .newlines)
                    for line in lines {
                        let parts = line.components(separatedBy: .whitespaces)
                        if parts.count >= 2 {
                            let sizeKB = Int64(parts[0]) ?? 0
                            let dirPath = parts.dropFirst().joined(separator: " ")
                            if sizeKB > 0 {
                                totalSize += sizeKB * 1024
                                if sizeKB > 1024 && files.count < maxFiles {
                                    let name = (dirPath as NSString).lastPathComponent
                                    let attrs = try? fm.attributesOfItem(atPath: dirPath)
                                    let created = attrs?[.creationDate] as? Date
                                    let modified = attrs?[.modificationDate] as? Date
                                    var isDir: ObjCBool = false
                                    let isDirectory = fm.fileExists(atPath: dirPath, isDirectory: &isDir) && isDir.boolValue
                                    files.append(StorageFile(
                                        id: dirPath, name: name, path: dirPath, size: sizeKB * 1024,
                                        createdDate: created, modifiedDate: modified, isDirectory: isDirectory
                                    ))
                                }
                            }
                        }
                    }
                }
            }

            files.sort { $0.size > $1.size }
            if files.count > maxFiles { files = Array(files.prefix(maxFiles)) }

            return StorageCategory(id: id, name: name, icon: icon, color: color, size: totalSize, path: paths.first ?? "", files: files)
        }.value
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
