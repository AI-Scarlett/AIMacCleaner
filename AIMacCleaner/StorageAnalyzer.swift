import SwiftUI
import Foundation

enum FileRiskLevel: String, Codable {
    case safe = "Cleanable"
    case caution = "Clean with Caution"
    case keep = "Keep"
    case unknown = "Unknown"

    init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        switch rawValue {
        case "Cleanable", "可清理": self = .safe
        case "Clean with Caution", "谨慎清理": self = .caution
        case "Keep", "保留": self = .keep
        case "Unknown", "未知": self = .unknown
        default: self = .unknown
        }
    }

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

    func localizedLabel(_ localizer: Localizer) -> String {
        switch self {
        case .safe: return localizer.cleanableRisk
        case .caution: return localizer.cautionRisk
        case .keep: return localizer.keepRisk
        case .unknown: return localizer.unknownRisk
        }
    }
}

class StorageAnalyzer: ObservableObject {
    @Published var categories: [StorageCategory] = []
    @Published var isScanning: Bool = false
    @Published var scanProgress: String = ""
    @Published var totalUsed: Int64 = 0
    @Published var aiAnalysisResult: String?

    weak var localizer: Localizer?
    func scanStorage() async {
        await MainActor.run {
            isScanning = true
            scanProgress = localizer?.scanningDisk ?? "Scanning disk..."
            categories.removeAll()
        }

        let fm = FileManager.default
        let home = SandboxPaths.realHomeDirectory

        let url = URL(fileURLWithPath: "/")
        let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        let systemTotal: Int64 = {
            guard let values = try? url.resourceValues(forKeys: keys),
                  let totalCap = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacityForImportantUsage else {
                return 0
            }
            return Int64(totalCap) - Int64(available)
        }()

        await MainActor.run { scanProgress = localizer?.scanningApps ?? "Scanning apps..." }
        let appResult = await scanCategoryWithDu(
            id: "apps", name: localizer?.appNameApps ?? "Applications", icon: "app.fill", color: .cyan,
            paths: ["/Applications", "\(home)/Applications"]
        )

        await MainActor.run { scanProgress = localizer?.scanningDocs ?? "Scanning documents..." }
        let docsResult = await scanCategoryWithDu(
            id: "documents", name: localizer?.appNameDocs ?? "Documents", icon: "doc.fill", color: .blue,
            paths: [
                "\(home)/Desktop", "\(home)/Documents", "\(home)/Downloads",
                "\(home)/Movies", "\(home)/Music", "\(home)/Pictures",
            ]
        )

        await MainActor.run { scanProgress = localizer?.calcSystemData ?? "Calculating system data..." }
        let systemSize = systemTotal - appResult.size - docsResult.size
        let systemDataCat = StorageCategory(
            id: "system", name: localizer?.appNameSystem ?? "System Data", icon: "gearshape.2", color: .gray,
            size: max(systemSize, 0),
            path: "\(home)/Library",
            files: []
        )

        await MainActor.run { scanProgress = localizer?.scanningOther ?? "Scanning other..." }
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
            ? StorageCategory(id: "other", name: localizer?.appNameOther ?? "Other", icon: "folder.fill", color: .indigo, size: 0, path: home, files: [])
            : await scanCategoryWithDu(id: "other", name: localizer?.appNameOther ?? "Other", icon: "folder.fill", color: .indigo, paths: otherPaths)

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
            let maxFiles = 2000

            for path in paths {
                let expanded = NSString(string: path).expandingTildeInPath
                guard fm.fileExists(atPath: expanded) else { continue }

                let sizeKB = Self.calculateDirectorySize(expanded) / 1024
                if sizeKB > 0 {
                    totalSize += sizeKB * 1024
                    if sizeKB > 1024 && files.count < maxFiles {
                        let name = (expanded as NSString).lastPathComponent
                        let attrs = try? fm.attributesOfItem(atPath: expanded)
                        let created = attrs?[.creationDate] as? Date
                        let modified = attrs?[.modificationDate] as? Date
                        var isDir: ObjCBool = false
                        let isDirectory = fm.fileExists(atPath: expanded, isDirectory: &isDir) && isDir.boolValue
                        files.append(StorageFile(
                            id: expanded, name: name, path: expanded, size: sizeKB * 1024,
                            createdDate: created, modifiedDate: modified, isDirectory: isDirectory
                        ))
                    }
                }
            }

            files.sort { $0.size > $1.size }
            if files.count > maxFiles { files = Array(files.prefix(maxFiles)) }

            return StorageCategory(id: id, name: name, icon: icon, color: color, size: totalSize, path: paths.first ?? "", files: files)
        }.value
    }

    private static func calculateDirectorySize(_ path: String) -> Int64 {
        let fm = FileManager.default
        var totalSize: Int64 = 0
        if let enumerator = fm.enumerator(atPath: path) {
            for case let file as String in enumerator {
                let fullPath = (path as NSString).appendingPathComponent(file)
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                    if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                       let size = attrs[.size] as? Int64 {
                        totalSize += size
                    }
                }
            }
        }
        return totalSize
    }

    func analyzeFileWithAI(file: StorageFile, config: AIConfig) async -> String? {
        let type = file.isDirectory ? "directory" : "file"
        return "Local analysis: \(file.name) is a \(type) using \(file.sizeFormatted). Review the path before cleanup; TraceFence only moves selected items to Trash."
    }

    func analyzeCategoryWithAI(category: StorageCategory, config: AIConfig) async -> String? {
        let topFiles = category.files.prefix(3).map(\.name).joined(separator: ", ")
        return "Local analysis: \(category.name) uses \(category.sizeFormatted). Largest visible items: \(topFiles.isEmpty ? "none" : topFiles). Clean only reviewed items; changes are recoverable from Trash."
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        formatter.locale = localizer?.language == .english ? Locale(identifier: "en_US") : Locale(identifier: "zh_CN")
        return formatter.string(from: date)
    }
}
