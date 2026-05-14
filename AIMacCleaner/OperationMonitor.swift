import Foundation
import AppKit

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false

    private var streamRef: FSEventStreamRef?
    private var agentProcesses: [String] = []
    private var fileSnapshots: [String: FileSnapshot] = [:]
    private let maxRecords = 5000
    private let recordsPath = NSHomeDirectory() + "/.aimaccleaner_operations_v2.json"

    struct FileSnapshot: Codable {
        let path: String
        let modDate: TimeInterval
        let size: Int64
        let isDir: Bool
        let agentName: String?
    }

    private let watchPaths: [String] = {
        let home = NSHomeDirectory()
        return [
            "\(home)/Desktop",
            "\(home)/Documents",
            "\(home)/Downloads",
            "\(home)/Projects",
            "\(home)/Work",
            "\(home)/Code",
            "\(home)/workspace",
            "\(home)/Developer",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }()

    private let agentNames = [
        "Claude Code", "claude", "CodeBuddy", "codebuddy", "Cline", "cline",
        "Codex", "codex", "Hermes", "hermes", "Trae", "trae",
        "Cursor", "cursor", "Windsurf", "windsurf", "CodeArts", "codearts",
        "QClaw", "qclaw", "OpenClaw", "openclaw", "Kimi", "kimi",
        "DeepSeek", "deepseek", "通义千问", "qwen", "豆包", "doubao",
        "MiniMax", "minimax", "Copilot", "copilot", "Aider", "aider",
        "GitHub", "github", "npm", "pip", "brew", "xcodebuild",
        "node", "python3", "python", "swift", "git",
    ]

    func start() {
        guard !isMonitoring else { return }
        isMonitoring = true
        loadRecords()
        buildInitialSnapshot()
        startFSEventStream()
        startProcessPoller()
    }

    func stop() {
        stopFSEventStream()
        isMonitoring = false
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        guard !watchPaths.isEmpty else { return }

        var context = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        let callback: FSEventStreamCallback = { _, clientCallBackInfo, numEvents, eventPaths, eventFlags, eventIds in
            let monitor = Unmanaged<OperationMonitor>.fromOpaque(clientCallBackInfo!).takeUnretainedValue()
            let paths = unsafeBitCast(eventPaths, to: NSArray.self) as! [String]
            DispatchQueue.global(qos: .userInitiated).async {
                monitor.processEvents(paths: paths)
            }
            return
        }

        var streamContext = FSEventStreamContext(
            version: 0, info: context, retain: nil, release: nil, copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            nil,
            callback,
            &streamContext,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            2.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        if let stream = streamRef {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
            FSEventStreamStart(stream)
        }
    }

    private func stopFSEventStream() {
        if let stream = streamRef {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
            streamRef = nil
        }
    }

    private func processEvents(paths: [String]) {
        let fm = FileManager.default
        let activeAgents = detectActiveAgents()

        for eventPath in paths {
            let expanded = NSString(string: eventPath).expandingTildeInPath

            if !fm.fileExists(atPath: expanded) {
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: activeAgents.first ?? "系统",
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: formatDeleteDetail(eventPath),
                    fileSize: 0
                )
                DispatchQueue.main.async { self.addRecord(record) }
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else { continue }

            let attrs = try? fm.attributesOfItem(atPath: expanded)
            let size = (attrs?[.size] as? Int64) ?? 0
            let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            if isDir.boolValue { continue }

            if let existing = fileSnapshots[eventPath] {
                if modDate > existing.modDate || size != existing.size {
                    let agentName = activeAgents.first ?? existing.agentName ?? "系统"
                    let record = OperationRecord(
                        id: UUID().uuidString,
                        timestamp: Date(),
                        agentName: agentName,
                        operationType: .modify,
                        targetPath: eventPath,
                        detail: formatModifyDetail(eventPath, oldSize: existing.size, newSize: size),
                        fileSize: size
                    )
                    DispatchQueue.main.async { self.addRecord(record) }
                }
            } else {
                let agentName = activeAgents.first ?? "系统"
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agentName,
                    operationType: .create,
                    targetPath: eventPath,
                    detail: formatCreateDetail(eventPath, size: size),
                    fileSize: size
                )
                DispatchQueue.main.async { self.addRecord(record) }
            }

            fileSnapshots[eventPath] = FileSnapshot(
                path: eventPath,
                modDate: modDate,
                size: size,
                isDir: isDir.boolValue,
                agentName: activeAgents.first
            )
        }
    }

    // MARK: - Process Detection

    private func detectActiveAgents() -> [String] {
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["ps", "-eo", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = nil
        task.launch()
        task.waitUntilExit()

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return [] }

        let lines = output.components(separatedBy: .newlines)
        var activeAgents: [String] = []

        for line in lines {
            let processName = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if processName.isEmpty { continue }

            for agent in agentNames {
                let agentLower = agent.lowercased()
                if processName.contains(agentLower) || agentLower.contains(processName) {
                    if !activeAgents.contains(agent) {
                        activeAgents.append(agent)
                    }
                }
            }
        }

        return activeAgents
    }

    private var processPoller: Timer?
    private func startProcessPoller() {
        processPoller?.invalidate()
        processPoller = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let agents = self.detectActiveAgents()
            if !agents.isEmpty {
                let agentList = agents.joined(separator: ", ")
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: agents.first ?? "系统",
                    operationType: .modify,
                    targetPath: "系统进程",
                    detail: "🤖 活跃的 AI Agent: \(agentList)",
                    fileSize: 0
                )
                DispatchQueue.main.async { self.addRecord(record) }
            }
        }
    }

    // MARK: - Snapshot

    private func buildInitialSnapshot() {
        let fm = FileManager.default
        for dirPath in watchPaths {
            let enumerator = fm.enumerator(atPath: dirPath)
            var count = 0
            while let file = enumerator?.nextObject() as? String, count < 10000 {
                let fullPath = "\(dirPath)/\(file)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    let attrs = try? fm.attributesOfItem(atPath: fullPath)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    fileSnapshots[file] = FileSnapshot(
                        path: file, modDate: modDate, size: size, isDir: isDir.boolValue, agentName: nil
                    )
                    count += 1
                }
            }
        }
    }

    // MARK: - Detail Formatting

    private func formatCreateDetail(_ path: String, size: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let sizeStr = ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        return "📄 创建文件: \(fileName) (\(sizeStr))\n📁 位置: \(dirName)"
    }

    private func formatModifyDetail(_ path: String, oldSize: Int64, newSize: Int64) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        let diff = newSize - oldSize
        let diffStr: String
        if diff > 0 {
            diffStr = "+\(ByteCountFormatter.string(fromByteCount: diff, countStyle: .file))"
        } else if diff < 0 {
            diffStr = ByteCountFormatter.string(fromByteCount: abs(diff), countStyle: .file)
        } else {
            diffStr = "大小不变"
        }
        return "✏️ 修改文件: \(fileName)\n📊 大小变化: \(diffStr)\n📁 位置: \(dirName)"
    }

    private func formatDeleteDetail(_ path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        let dirName = dirName(from: path)
        return "🗑️ 删除文件: \(fileName)\n📁 原位置: \(dirName)"
    }

    private func dirName(from path: String) -> String {
        let dir = (path as NSString).deletingLastPathComponent
        if dir.hasPrefix(NSHomeDirectory()) {
            return "~" + String(dir.dropFirst(NSHomeDirectory().count))
        }
        return dir
    }

    // MARK: - Record Management

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

    deinit {
        stopFSEventStream()
        processPoller?.invalidate()
    }
}
