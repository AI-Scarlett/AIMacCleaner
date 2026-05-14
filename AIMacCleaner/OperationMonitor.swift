import Foundation
import AppKit

class OperationMonitor: ObservableObject {
    @Published var records: [OperationRecord] = []
    @Published var isMonitoring: Bool = false

    private var streamRef: FSEventStreamRef?
    private var fileSnapshots: [String: FileSnapshot] = [:]
    private let maxRecords = 2000
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
            "\(home)/Library/Caches",
            "\(home)/Library/Application Support",
        ].filter { FileManager.default.fileExists(atPath: $0) }
    }()

    private let agentProcessNames = [
        "claude", "claude-code", "codebuddy", "cline", "codex", "hermes", "trae", "trae-agent",
        "cursor", "windsurf", "codearts", "kimi", "deepseek", "qwen", "doubao",
        "minimax", "copilot", "aider", "cody", "tabby", "warp",
        "chatgpt", "gemini", "augment", "node", "python", "python3",
        "bun", "deno",
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
        processPoller?.invalidate()
        isMonitoring = false
    }

    // MARK: - FSEvents

    private func startFSEventStream() {
        guard !watchPaths.isEmpty else { return }

        let weakRef = Unmanaged.passUnretained(self).toOpaque()
        let callback: FSEventStreamCallback = { _, info, numEvents, eventPaths, _, _ in
            guard let info = info else { return }
            let monitor = Unmanaged<OperationMonitor>.fromOpaque(info).takeUnretainedValue()
            let cPaths = eventPaths.bindMemory(to: UnsafePointer<Int8>.self, capacity: Int(numEvents))
            var pathList: [String] = []
            for i in 0..<Int(numEvents) {
                let cStr = cPaths[i]
                pathList.append(String(cString: cStr))
            }
            DispatchQueue.global(qos: .utility).async {
                monitor.processEvents(paths: pathList)
            }
        }

        var context = FSEventStreamContext(
            version: 0,
            info: weakRef,
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        streamRef = FSEventStreamCreate(
            nil,
            callback,
            &context,
            watchPaths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            3.0,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        )

        if let stream = streamRef {
            FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
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
            let fileName = (eventPath as NSString).lastPathComponent
            if fileName.hasPrefix(".") || fileName.hasPrefix("._") { continue }

            let expanded = NSString(string: eventPath).expandingTildeInPath

            if !fm.fileExists(atPath: expanded) {
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: activeAgents.first ?? "文件操作",
                    operationType: .delete,
                    targetPath: eventPath,
                    detail: formatDeleteDetail(eventPath),
                    fileSize: 0
                )
                DispatchQueue.main.async { self.addRecord(record) }
                fileSnapshots[eventPath] = nil
                continue
            }

            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: expanded, isDirectory: &isDir) else { continue }
            if isDir.boolValue { continue }

            let attrs = try? fm.attributesOfItem(atPath: expanded)
            let size = (attrs?[.size] as? Int64) ?? 0
            let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0

            if let existing = fileSnapshots[eventPath] {
                guard abs(modDate - existing.modDate) > 1.0 || size != existing.size else { continue }
                let agentName = activeAgents.first ?? existing.agentName ?? "文件操作"
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
            } else {
                let agentName = activeAgents.first ?? "文件操作"
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
        task.executableURL = URL(fileURLWithPath: "/usr/bin/ps")
        task.arguments = ["-eo", "comm="]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return []
        }

        guard let data = try? pipe.fileHandleForReading.readToEnd(),
              let output = String(data: data, encoding: .utf8) else { return [] }

        let lines = output.components(separatedBy: .newlines)
        var activeAgents: [String] = []

        for line in lines {
            let processName = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !processName.isEmpty else { continue }

            for agent in agentProcessNames {
                if processName == agent || processName.hasSuffix("/\(agent)") {
                    let displayName = agent.capitalized
                    if !activeAgents.contains(displayName) {
                        activeAgents.append(displayName)
                    }
                }
            }
        }

        return activeAgents
    }

    private var processPoller: Timer?
    private var lastPolledAgents: [String] = []
    private func startProcessPoller() {
        processPoller?.invalidate()
        processPoller = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            let agents = self.detectActiveAgents()
            let newAgents = agents.filter { !self.lastPolledAgents.contains($0) }
            if !newAgents.isEmpty {
                let agentList = newAgents.joined(separator: ", ")
                let record = OperationRecord(
                    id: UUID().uuidString,
                    timestamp: Date(),
                    agentName: newAgents.first ?? "文件操作",
                    operationType: .modify,
                    targetPath: "系统进程",
                    detail: "🤖 新启动的 AI Agent: \(agentList)",
                    fileSize: 0
                )
                DispatchQueue.main.async { self.addRecord(record) }
            }
            self.lastPolledAgents = agents
        }
    }

    // MARK: - Snapshot

    private func buildInitialSnapshot() {
        let fm = FileManager.default
        for dirPath in watchPaths {
            let enumerator = fm.enumerator(atPath: dirPath)
            var count = 0
            while let file = enumerator?.nextObject() as? String, count < 50000 {
                let fullPath = "\(dirPath)/\(file)"
                var isDir: ObjCBool = false
                if fm.fileExists(atPath: fullPath, isDirectory: &isDir) {
                    let attrs = try? fm.attributesOfItem(atPath: fullPath)
                    let size = (attrs?[.size] as? Int64) ?? 0
                    let modDate = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
                    fileSnapshots[fullPath] = FileSnapshot(
                        path: fullPath, modDate: modDate, size: size, isDir: isDir.boolValue, agentName: nil
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
            diffStr = "内容变更"
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
        if records.count % 20 == 0 {
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
