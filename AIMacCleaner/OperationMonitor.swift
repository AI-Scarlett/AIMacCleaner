import Foundation
import AppKit

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false

    private var timers: [Timer] = []
    private var lastSnapshots: [String: Set<String>] = [:]
    private let maxRecords = 5000
    private let recordsPath = NSHomeDirectory() + "/.aimaccleaner_operations.json"

    private let agentWatchDirs: [(String, String)] = [
        (NSHomeDirectory() + "/.hermes", "Hermes"),
        (NSHomeDirectory() + "/.claude", "Claude Code"),
        (NSHomeDirectory() + "/.codebuddy", "CodeBuddy"),
        (NSHomeDirectory() + "/.codebuddycn", "CodeBuddy CN"),
        (NSHomeDirectory() + "/.codex", "Codex"),
        (NSHomeDirectory() + "/.cline", "Cline"),
        (NSHomeDirectory() + "/.qclaw", "QClaw"),
        (NSHomeDirectory() + "/.openclaw-node", "OpenClaw"),
        (NSHomeDirectory() + "/.kimi", "Kimi"),
        (NSHomeDirectory() + "/.minimax-agent-cn", "MiniMax Agent"),
        (NSHomeDirectory() + "/.cherrystudio", "Cherry Studio"),
        (NSHomeDirectory() + "/.lmstudio", "LM Studio"),
        (NSHomeDirectory() + "/.yi-code", "yi-code"),
        (NSHomeDirectory() + "/.codearts-doer-for-coding", "CodeArts Agent"),
        (NSHomeDirectory() + "/.codeartsdoer", "CodeArts Agent"),
        (NSHomeDirectory() + "/.deepseek", "DeepSeek"),
        (NSHomeDirectory() + "/.qwen", "通义千问"),
        (NSHomeDirectory() + "/.doubao", "豆包"),
        (NSHomeDirectory() + "/.agents", "AI Agents"),
        (NSHomeDirectory() + "/.ai_completion", "AI Completion"),
        (NSHomeDirectory() + "/.evomorph", "EvoMorph"),
        (NSHomeDirectory() + "/Library/Application Support/Trae CN", "Trae"),
        (NSHomeDirectory() + "/Library/Application Support/Cursor", "Cursor"),
        (NSHomeDirectory() + "/Library/Application Support/Windsurf", "Windsurf"),
        (NSHomeDirectory() + "/Library/Application Support/CodeBuddyCN", "CodeBuddy CN"),
        (NSHomeDirectory() + "/Library/Application Support/Claude-3p", "Claude Code"),
    ]

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        loadRecords()

        for (dirPath, agentName) in agentWatchDirs {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }
            lastSnapshots[dirPath] = snapshotFiles(at: dirPath)
        }

        let timer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.pollChanges()
            }
        }
        timers.append(timer)
        pollChanges()
    }

    func stop() {
        for timer in timers { timer.invalidate() }
        timers.removeAll()
        lastSnapshots.removeAll()
        isMonitoring = false
    }

    private func snapshotFiles(at path: String, maxDepth: Int = 3) -> Set<String> {
        var result = Set<String>()
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(atPath: path) else { return result }
        var depth = 0
        while let file = enumerator.nextObject() as? String {
            let fullPath = (path as NSString).appendingPathComponent(file)
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: fullPath, isDirectory: &isDir), !isDir.boolValue {
                if let attrs = try? fm.attributesOfItem(atPath: fullPath),
                   let modDate = attrs[.modificationDate] as? Date {
                    let key = "\(file)|\(Int(modDate.timeIntervalSince1970))"
                    result.insert(key)
                }
            }
            depth += 1
            if depth > 5000 { break }
        }
        return result
    }

    private func pollChanges() {
        let fm = FileManager.default
        for (dirPath, agentName) in agentWatchDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: dirPath, isDirectory: &isDir), isDir.boolValue else { continue }

            let current = snapshotFiles(at: dirPath)
            let previous = lastSnapshots[dirPath] ?? Set<String>()

            let added = current.subtracting(previous)
            let removed = previous.subtracting(current)

            for item in added {
                let fileName = item.components(separatedBy: "|").first ?? item
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .create,
                    targetPath: (dirPath as NSString).appendingPathComponent(fileName),
                    detail: "\(agentName) 创建 \(fileName)",
                    fileSize: 0
                )
                addRecord(record)
            }

            for item in removed {
                let fileName = item.components(separatedBy: "|").first ?? item
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .delete,
                    targetPath: (dirPath as NSString).appendingPathComponent(fileName),
                    detail: "\(agentName) 删除 \(fileName)",
                    fileSize: 0
                )
                addRecord(record)
            }

            lastSnapshots[dirPath] = current
        }
    }

    func addRecord(_ record: OperationRecord) {
        records.insert(record, at: 0)
        if records.count > maxRecords {
            records = Array(records.prefix(maxRecords))
        }
        if records.count % 50 == 0 {
            saveRecords()
        }
    }

    func clearRecords() {
        records.removeAll()
        saveRecords()
    }

    private func loadRecords() {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: recordsPath)),
              let decoded = try? JSONDecoder().decode([OperationRecord].self, from: data) else { return }
        records = decoded
    }

    func saveRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        try? data.write(to: URL(fileURLWithPath: recordsPath))
    }
}
