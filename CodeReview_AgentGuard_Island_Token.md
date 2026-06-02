# 三大核心功能代码审查报告

| 项目 | MacCleaner (AIMacCleaner) |
|------|---------------------------|
| 审查日期 | 2026-06-02 |
| 审查范围 | Agent 中心审批 / 灵动岛审批弹窗 / Token 统计 |
| 审查人 | Mavis (代码审查) |
| 项目语言/框架 | Swift / SwiftUI / macOS |

---

## 0. 审查范围

| 文件 | 行数 | 涉及模块 |
|------|------|---------|
| `AIMacCleaner/AgentGuardFeature.swift` | 1399 | Agent 中心审批 |
| `AIMacCleaner/AgentGuardTab.swift` | 1430 | Agent 中心审批 |
| `AIMacCleaner/Views/AgentCenter/AgentCenterView.swift` | 1041 | Agent 中心审批 |
| `AIMacCleaner/ViewModels/IslandViewModel.swift` | 575 | 灵动岛审批弹窗 |
| `AIMacCleaner/Views/Island/IslandView.swift` | 614 | 灵动岛审批弹窗 |
| `AIMacCleaner/Views/Island/IslandWindow.swift` | 179 | 灵动岛审批弹窗 |
| `AIMacCleaner/Views/Island/PlanApprovalSheet.swift` | 152 | 灵动岛审批弹窗 |
| `AIMacCleaner/Views/Island/PermissionSheet.swift` | 348 | 灵动岛审批弹窗 |
| `AIMacCleaner/Views/Island/QuestionSheet.swift` | 265 | 灵动岛审批弹窗 |
| `AIMacCleaner/TokenScopeLabView.swift` | 3238 | Token 统计 |
| **合计** | **9241** | |

**问题分级**

| 级别 | 含义 |
|------|------|
| P0 | 数据丢失 / 线程安全 / 状态机错乱，必须立即修复 |
| P1 | 功能正确性 / 性能 / UX 缺陷，本周修复 |
| P2 | 设计 / 可维护性 / 一致性问题，迭代修复 |

---

## 1. P0 严重问题（数据丢失 / 线程安全 / 状态机错乱）

### 1.1 TokenScopeStore 8 秒硬超时提前标记 `scanCompleted = true`

**文件**：`TokenScopeLabView.swift:1119-1125`

```swift
if showProgress {
    isScanning = true
    DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
        guard self.generation == currentGeneration, self.isScanning else { return }
        self.scanCompleted = true   // ❌ 扫描未完成就翻成"完成"
    }
}
```

**后果**：用户点"同步数据"，UI 在 8 秒后立刻显示"扫描完成"并切到"未发现数据"状态，但后台其实还在扫。Mac 慢一点、文件多，就出现"显示空但数据慢慢冒出来"的鬼影。

**修复**：
- 删掉这个 `asyncAfter`。
- 只在 `scanQueue` 回调结束（`DispatchQueue.main.async` 内）才设置 `scanCompleted = true`。

```swift
scanQueue.async {
    let result = self.scanner.scan(roots: roots)
    DispatchQueue.main.async {
        guard currentGeneration == self.generation else { return }
        self.records = result.records
        self.summaries = TokenScopeRange.cachedSummaries(for: result.records)
        self.sources = result.sources
        self.scanCompleted = true     // 只在这里置
        self.isScanning = false
    }
}
```

---

### 1.2 AgentGuardFeature 文件写盘没有 atomic

**文件**：`AgentGuardFeature.swift:1299-1302, 1310-1312, 1321-1323, 1336-1338, 1347-1349, 1358-1360`

```swift
func saveAlerts() {
    guard let data = try? JSONEncoder().encode(alerts) else { return }
    try? data.write(to: URL(fileURLWithPath: alertsPath))   // ❌ 非 atomic
}
```

**后果**：`saveAlerts()` 在 `fireAlert` 主线程、auto-save 定时器（line 1670）、用户点 `clearAlerts` 等多个入口同时调用。即使都在主线程，写盘中途 app crash / OS kill 会导致 alerts.json 损坏为空，丢失所有告警历史。

**修复**：

```swift
try? data.write(to: url, options: .atomic)   // 加 options: .atomic
```

同时考虑把写盘合并到串行调度队列：

```swift
private let writeQueue = DispatchQueue(label: "agentguard.write", qos: .utility)
```

---

### 1.3 AgentGuardTab 高频 Slider/Toggle 写盘

**文件**：`AgentGuardTab.swift:278-326, 330-360`

```swift
Slider(value: Binding(
    get: { Double(service.guardFeature.alertRule.batchDeleteThreshold) },
    set: { service.guardFeature.alertRule.batchDeleteThreshold = Int($0); service.guardFeature.saveAlertRule() }
), ...)
```

**后果**：用户拖动 Slider 1 秒可能产生 60+ 次 `saveAlertRule()`，每次 JSON 编码 + 写盘。CPU 飙升、磁盘 I/O 抖动。

**修复**：

```swift
// 用 Combine debounce
.service.guardFeature.$alertRule
    .dropFirst()
    .debounce(for: 0.3, scheduler: DispatchQueue.main)
    .sink { _ in service.guardFeature.saveAlertRule() }
```

或 `.onChange(of: threshold) { _ in scheduleSave() }` + 300ms 防抖。

---

### 1.4 AgentGuardFeature `incrementRuleCount` 日期/区域敏感

**文件**：`AgentGuardFeature.swift:1048-1065`

```swift
let todayStr = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .none)
let lastDateStr = commandRules[index].lastCalledBy.isEmpty ? "" : String(commandRules[index].lastCalledBy.split(separator: "|").first ?? "")
if isToday {
    if todayStr == lastDateStr {
        commandRules[index].todayCallCount += 1
    } else {
        commandRules[index].todayCallCount = 1
    }
}
```

**问题**：
1. `Date()`（now）和 `timestamp` 可能不是同一天 — 应用了 timestamp 但 todayStr 用 `Date()`。
2. `localizedString` 输出受用户地区影响，"5/15/25" vs "15/5/25" 不一致。
3. `lastCalledBy` 用 "|" 拼接，agentName 也可能含 "|"（虽然概率低，但没人验证）。

**修复**：

```swift
private static let dayKey: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"   // 用绝对格式，不用 localized
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = .current
    return f
}()

// 直接用 Date 比较，不要用字符串
if Calendar.current.isDate(timestamp, inSameDayAs: previousCallDate) {
    commandRules[index].todayCallCount += 1
} else {
    commandRules[index].todayCallCount = 1
}
```

把 `lastCalledBy` 拆成两个字段：`lastCallDate: Date?` 和 `lastCallAgent: String`。

---

### 1.5 IslandViewModel 重复的 sheet 状态管理 — 双轨制不一致

**文件**：`IslandViewModel.swift:96-102, 365-369`

```swift
@Published var showPermissionSheet: Bool = false
@Published var showQuestionSheet: Bool = false
@Published var showPlanApprovalSheet: Bool = false
@Published var approvalQueue: [IslandApprovalOverlay] = []
@Published var activeApprovalOverlay: IslandApprovalOverlay?

private func updateLegacySheetFlags(for overlay: IslandApprovalOverlay?) {
    showPermissionSheet = overlay?.kind == .permission
    showQuestionSheet = overlay?.kind == .question
    showPlanApprovalSheet = overlay?.kind == .plan
}
```

**后果**：
- `activeApprovalOverlay` 已经是 sheet 显示的 source of truth，但还有 3 个 legacy `show*Sheet` 标志。
- 命名 `Legacy` 表明是历史包袱但实际还在用，没看到消费方 — 全岛代码都没人读这三个 bool。
- `dismissSheets()` 也只动这三个 bool，**完全不会清掉 `activeApprovalOverlay`**，导致下个事件来时 advance 失败。

**修复**：
- 全岛代码都通过 `activeApprovalOverlay` 渲染（`IslandView.expandedView` 已经这样做了）。
- 删除 `showPermissionSheet/showQuestionSheet/showPlanApprovalSheet` 和 `updateLegacySheetFlags`。
- 删除 `dismissSheets()`（或者改为清空 `approvalQueue` 和 `activeApprovalOverlay`）。

---

### 1.6 PermissionSheetView 切 session 后 `isDenyInputVisible` 不重置

**文件**：`PermissionSheetView.swift:11, 92-103`

```swift
@State private var isDenyInputVisible: Bool = false
...
} else if isDenyInputVisible {
    HStack {
        decisionButton(title: "Cancel", ...) { isDenyInputVisible = false }
        decisionButton(title: "No with reason", ...) { onDecision(.deny(...)) }
    }
}
```

**问题**：`@State` 在 View identity 变化时才会重置。`expandedView` 用 `if let perm = session.pendingPermission { PermissionSheetView(...) }`，SwiftUI 在 `perm` 引用变化时**不一定**重建 view。`customMessage` 同样有这个问题。

**修复**：

```swift
struct PermissionSheetView: View {
    let permission: PendingPermission
    @State private var reason = ""
    @State private var isDenyInputVisible = false

    var body: some View {
        content
            .onChange(of: permission.toolUseId) { _ in
                isDenyInputVisible = false
                reason = ""
            }
            .onAppear {
                isDenyInputVisible = false
                reason = ""
            }
    }
}
```

PlanApprovalSheet 同样有 `customMessage` 问题，一并修。

---

## 2. P1 高优问题（功能正确性 / 性能 / UX）

### 2.1 AgentGuardFeature `operationTypeForHookTool` 字符串匹配脆弱

**文件**：`AgentGuardFeature.swift:1025-1046`

```swift
if combined.contains("delete") || combined.contains("remove") || combined.contains("trash") || combined.contains("rm ") {
    return .delete
}
if combined.contains("read") || combined.contains("grep") || ... { return .read }
if combined.contains("write") || combined.contains("create") || ... { return .create }
if combined.contains("rename") { return .rename }
if combined.contains("move") || combined.contains(" mv ") {   // ❌ "mv" 前后必须空格
    return .move
}
```

**问题**：
1. 顺序问题：文件名包含 "read"（如 `readme.md`）会被判为 `.read`，但写 `readme.md` 应该是 `.create`。
2. `" mv "` 前后都要空格 — 实际命令可能是 `/usr/bin/mv` 或 `mv` 开头。
3. 完全没看到 `.rename` → `.move` 区分；`rename` 关键字在 read 之后被截走（`read` 包含在 `read` 里没问题，但 `cread` 这种就有歧义）。
4. `chmod` 应该归 `.modify` 但没匹配。

**修复**：
- 改用结构化数据：hook 上游应当传 `operation: String`（"create"/"modify"/"delete"/"read"），不是猜。
- 或者用正则词边界：`\bmv\b`。
- 优先级改成：精确 tool name → generic name → 关键字 fallback。

---

### 2.2 AgentGuardFeature `isAuditableAgentRecord` 硬编码黑名单

**文件**：`AgentGuardFeature.swift:633-639`

```swift
let nonAgentToolNames: Set<String> = [
    "Node.js", "Python", "npm", "npx", "Yarn", "pnpm", "Cargo", "Rust",
    "Deno", "Bun", "Go", "Swift", "Java", "Gradle", "Maven", "Make",
    "CMake", "Xcode", "Git", "Docker", "pip", "pip3", "Clang",
    "rsync", "cp", "mv", "rm", "zip", "tar", "mkdir"   // ❌ "cp"/"mv"/"rm" 是命令名
]
```

**问题**：如果用户给某个 agent 命名为 "rm" 或 "cp"（完全可能），这条记录会被静默跳过。审计记录缺失、CSV 导出漏数据。

**修复**：
- 用 agent name + 命令字段组合判断。
- 或者从白名单（已注册 agent）查；不要用进程名黑名单。
- 至少在 `localizer` 加一个可配置的黑名单，并加注释"以下名字在某些情况下会被误判"。

---

### 2.3 AgentGuardFeature `matchCommand` 每次重新构造 Regex

**文件**：`AgentGuardFeature.swift:1067-1073`

```swift
private func matchCommand(_ cmdLower: String, rule: CommandRule) -> Bool {
    if rule.isRegex {
        return (try? Regex(rule.pattern).firstMatch(in: cmdLower)) != nil   // ❌ 每次编译
    } else {
        return cmdLower.contains(rule.pattern.lowercased())
    }
}
```

**后果**：每条命令检查会扫所有规则 × 每次新构造 Regex。`checkCommand` 中规则数 30+，正则规则编译是昂贵的。

**修复**：

```swift
private var regexCache: [String: Regex<AnyRegexOutput>?] = [:]

private func matchCommand(_ cmdLower: String, rule: CommandRule) -> Bool {
    if rule.isRegex {
        let re = regexCache[rule.id] ?? {
            let r = try? Regex(rule.pattern)
            regexCache[rule.id] = r
            return r
        }()
        return re?.firstMatch(in: cmdLower) != nil
    } else {
        return cmdLower.contains(rule.pattern.lowercased())
    }
}
```

---

### 2.4 IslandViewModel `currentSession` 异步覆盖造成状态错乱

**文件**：`IslandViewModel.swift:159-220`（handleEvent 内）

```swift
private func handleEvent(_ event: AgentHookEvent) async {
    ...
    if let store = sessionStore {
        currentSession = await store.getSession(event.sessionId)   // ❌ 异步
    }
    switch event {
    case .tokenUsage(let id, let input, let output, _, _):
        if let session = await sessionStore?.getSession(id) {
            lastStatusText = "Tokens: \(input.formatted())↑ \(output.formatted())↓"
            currentSession = session   // ❌ 又设一次
        }
    ...
}
```

**问题**：
- `handleEvent` 在 streamTask 中执行，不是主线程。
- `currentSession` 是 `@Published` 跨线程读。
- `await store.getSession(...)` 是异步，期间其他事件会先处理完，`currentSession` 被覆盖多次。
- `sessionToDetail` 在 detail view 用，跟 `currentSession` 在 expanded view 用，但 `selectApprovalOverlay` 又会覆盖 `currentSession` — **三个 session 状态互相覆盖**。

**修复**：
- 把 `currentSession` 改为 `lastEventSessionId`，UI 自行从 `allSessions` 找。
- 详细页面用 `sessionToDetail`、expanded 用 `activeApprovalOverlay?.sessionId` 查 allSessions。
- `selectApprovalOverlay` 不要写 `currentSession` — 当前在 detail 页时这会破坏 detail。

---

### 2.5 IslandViewModel `respondTo*` 内多余 `await MainActor.run`

**文件**：`IslandViewModel.swift:413-430, 480-497, 502-519`

```swift
func respondToPermission(_ decision: PermissionDecision) {
    ...
    Task { [weak self] in
        await self?.hookServer?.respondToPermission(...)
        await MainActor.run {                  // ❌ class 是 @MainActor
            self?.activeApprovalOverlay = nil
            ...
        }
        await self?.sessionStore?.setPendingPermission(...)
    }
}
```

**问题**：`IslandViewModel` 是 `@MainActor class`，外层 `Task { ... }` 默认在主 actor 继承（具体行为 Swift 版本依赖），但 `await MainActor.run` 是显式 hop 一次，造成不必要的 suspension。

**后果**：每次响应多一次 actor hop，UI 反馈延迟。

**修复**：

```swift
@MainActor
func respondToPermission(_ decision: PermissionDecision) async {
    guard let session = activeApprovalSession ?? currentSession,
          let perm = session.pendingPermission else { return }
    if perm.requiresExternalHandling { ... }

    await hookServer?.respondToPermission(sessionId: session.id, toolName: perm.toolName, decision: decision)
    await sessionStore?.setPendingPermission(session.id, nil)
    advanceAfterResponse()
}
```

---

### 2.6 AgentGuardTab Toast 多次快速触发会重叠

**文件**：`AgentGuardTab.swift:1104-1110`

```swift
private func showCommandToast(_ action: String) {
    toastMessage = "\(action) ✓"
    withAnimation { showToast = true }
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
        withAnimation { showToast = false }
    }
}
```

**问题**：连续点 3 个命令的 move 按钮，第 1 个 toast 还没消失，第 2/3 个排队 closure，1.5 秒后一起把 `showToast = false`，最终用户只看到 1.5 秒一条 toast。

**修复**：

```swift
@State private var toastTask: Task<Void, Never>?

private func showCommandToast(_ action: String) {
    toastTask?.cancel()
    toastMessage = "\(action) ✓"
    withAnimation { showToast = true }
    toastTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        guard !Task.isCancelled else { return }
        withAnimation { showToast = false }
    }
}
```

---

### 2.7 TokenScopeScanner 同步顺序扫多个 root

**文件**：`TokenScopeLabView.swift:1890-1929`

```swift
func scan(roots: [URL]) -> TokenScopeScanResult {
    var records: [TokenScopeUsageRecord] = []
    var statuses: [TokenScopeSourceStatus] = []
    for root in roots {           // ❌ 顺序
        ...
        let files = candidateFiles(root: root, source: source)   // I/O 密集
        let sourceRecords = files.flatMap { parse(file: $0, ...) }   // CPU 密集
        ...
    }
    return TokenScopeScanResult(records: dedupe(records), sources: mergeStatuses(statuses))
}
```

**后果**：用户有 18 个 agent、3 个 root，串行扫可能 10+ 秒。`scanQueue` 是 utility QoS 串行 queue，多核浪费。

**修复**：

```swift
func scan(roots: [URL]) -> TokenScopeScanResult {
    let group = DispatchGroup()
    let lock = NSLock()
    var allRecords: [TokenScopeUsageRecord] = []
    var allStatuses: [TokenScopeSourceStatus] = []

    let workQueue = DispatchQueue(label: "tokenscope.scan", qos: .utility, attributes: .concurrent)
    for root in roots {
        group.enter()
        workQueue.async {
            defer { group.leave() }
            let result = self.scanSingleRoot(root)
            lock.lock()
            allRecords.append(contentsOf: result.records)
            allStatuses.append(contentsOf: result.statuses)
            lock.unlock()
        }
    }
    group.wait()
    return TokenScopeScanResult(records: dedupe(allRecords), sources: mergeStatuses(allStatuses))
}
```

同时把 `startAccessingSecurityScopedResource()` 的 `defer stop` 改用 `withExtendedLifetime` 或更稳的 guard 模式。

---

### 2.8 TokenScopeScanner 文件大小限制 silently 跳过大文件

**文件**：`TokenScopeLabView.swift:1873-1874, 1955`

```swift
private let maxBytesPerFile = 4 * 1024 * 1024        // 4MB
private let maxCodexBytesPerFile = 256 * 1024 * 1024 // 256MB
...
if let size = values?.fileSize, size > maxBytes(for: source) { continue }  // 静默跳过
```

**后果**：Claude Code 一天的 jsonl 可能超过 4MB（verbose tool result 容易撑大），关键 token 数据丢失，统计偏差。

**修复**：
- 改为按行流式截断：读 4MB 但 parse 时丢弃完整行（已经做了，但截断后会丢 token 记录）。
- 或者用 gzip 压缩后判断（很多 jsonl 是 zstd 压缩）。
- UI 显示"X 个文件超过大小限制"提示。

---

### 2.9 TokenScopeCodexAdapter.scanJSONLLines `prefixText.contains` O(N) 性能

**文件**：`TokenScopeLabView.swift:2368-2390`

```swift
func flush(_ line: Data) {
    guard !line.isEmpty else { return }
    let prefix = line.prefix(4096)
    guard let prefixText = String(data: prefix, encoding: .utf8) else { return }

    if prefixText.contains("\"type\":\"event_msg\""),         // 每次扫前 4KB
       prefixText.contains("\"payload\":{\"type\":\"token_count\""),
       let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
        onObject(object)
        return
    }
    ...
}
```

**问题**：
- 4KB 字符串 `contains` 在百万行文件上是真开销。
- 第二次 `prefixText.contains` 在 `if` 短路后还要扫一遍 — 应该用单次 `range(of:)` 串联检查。

**修复**：

```swift
let eventMsgRange = prefixText.range(of: "\"type\":\"event_msg\"")
guard let eventMsgRange else { return }
if prefixText.range(of: "\"payload\":{\"type\":\"token_count\"", range: eventMsgRange.upperBound..<prefixText.endIndex) != nil,
   let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] {
    onObject(object)
    return
}
```

---

### 2.10 QuestionSheetView 状态机混乱 — `multiSelect` + `isTextReply` 混用

**文件**：`QuestionSheetView.swift:55-89, 117-161, 163-203`

```swift
if question.multiSelect {
    Divider()
    HStack {
        Button("Cancel") { onAnswer("cancel") }
        Button("Submit") { onAnswer(selectedOptions.sorted().joined(separator: ", ")) }
    }
}
...
private var customReplySection: some View {
    VStack {
        TextEditor(text: $textAnswer)
        Button("Send Reply") { onAnswer(textAnswer) }
    }
}
```

**问题**：
- `question.multiSelect == true` 时底部显示 Submit 按钮，但 **customReplySection 永远显示**（line 42 `customReplySection` 不在 if 里）— 用户会困惑。
- multiSelect + 自定义输入是冲突的：用户既可以勾选也可以打字，但响应逻辑只走一条。
- 单选模式直接 `onAnswer(option)`，不显示底部按钮，但 `textAnswer` 还在 — 用户打字后没法提交。
- `cancel` 字符串传给 hook server 是个 magic string。

**修复**：
- 抽出状态机 `enum ReplyMode { case option, multiSelect, textReply }`，由 `isTextReply || options.isEmpty` 推导出唯一模式。
- 三个 mode 互斥，UI 严格分支。
- 用 enum 而不是 string 传 `onAnswer`。

---

### 2.11 PlanApprovalSheet 缺"延后/稍后处理"路径

**文件**：`PlanApprovalSheet.swift:60-103`

```swift
VStack {
    HStack {
        Button("Reject") { onResponse("reject", ...) }
        Button("Approve") { onResponse("approve", ...) }
    }
    Button("Modify") { onResponse("modify", ...) }
    TextField("feedback", text: $customMessage)
}
```

**问题**：用户被 3 个按钮绑架 — 没有"Dismiss"/"Decide Later"。如果用户想先去查项目代码再决定，弹窗挡住所有操作。

**修复**：加一个 `Button("Decide Later") { onResponse("defer", nil) }`，hook server 端把 plan 状态保留为 pending，island 收起来稍后提醒。或者干脆复用 PermissionSheet 的 cancel 模式。

---

### 2.12 AgentCenterView `pendingApprovalSessions` 每次访问都重算

**文件**：`AgentCenterView.swift:314-318`

```swift
private var pendingApprovalSessions: [SessionState] {
    sessionsViewModel.sessions.filter {
        $0.pendingPermission != nil || $0.pendingQuestion != nil || $0.pendingPlan != nil || $0.phase.needsAttention
    }
}
```

**后果**：这个 computed property 在 4 个地方被读（line 100, 316, 370, 425-432），每次都遍历 + 4 个 OR 检查。sessions 多时（实际 100+）有可观开销。

**修复**：

```swift
@State private var cachedPendingApprovals: [SessionState] = []
.onChange(of: sessionsViewModel.sessions) { _ in
    cachedPendingApprovals = sessionsViewModel.sessions.filter { ... }
}
```

或者用 `@StateObject` ViewModel 持有缓存。

---

### 2.13 AgentGuardTab 重复 Binding 模板（11 处）

**文件**：`AgentGuardTab.swift:278-326, 330-360`

11 个 `Binding(get: { ... }, set: { ...; save() })` 几乎一样，slider/toggle/picker 都是。

**修复**：抽 helper：

```swift
private func ruleBinding<T>(
    get: @escaping () -> T,
    set: @escaping (T) -> Void
) -> Binding<T> {
    Binding(
        get: get,
        set: { newValue in
            set(newValue)
            service.guardFeature.saveAlertRule()
        }
    )
}
// 用法：
Slider(value: ruleBinding(
    get: { Double(service.guardFeature.alertRule.batchDeleteThreshold) },
    set: { service.guardFeature.alertRule.batchDeleteThreshold = Int($0) }
), ...)
```

---

### 2.14 IslandWindow 跟踪区域 setupMouseTracking 一次性不更新

**文件**：`IslandWindow.swift:53-62`

```swift
private func setupMouseTracking(for view: NSView) {
    let options: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
    let trackingArea = NSTrackingArea(rect: view.bounds, options: options, owner: view, userInfo: nil)
    view.addTrackingArea(trackingArea)
}
```

**问题**：
- `view.bounds` 在 createWindow 时可能是 0×0，tracking area 无效。
- 已经 `inVisibleRect` 不需要明确 rect，但 `view.bounds` 为 0 时也不会自动更新。
- `IslandHostingView` 自己也重写 `updateTrackingAreas` 重新 add — **重复 add** 导致 mouseEntered 触发两次。

**修复**：
- 删掉 `setupMouseTracking`（IslandHostingView 已经在做）。
- `IslandHostingView.updateTrackingAreas` 用 `bounds` 而不是 `inVisibleRect`，因为 panel resize 时 bounds 会变。

---

## 3. P2 中等问题（设计 / 可维护性 / 一致性）

### 3.1 三个核心模块之间没有共享数据，审计盲区

**位置**：`AgentCenterView.swift:128, 320, 487` + `IslandViewModel.swift:84-110` + `AgentGuardFeature.swift:213-230`

`AgentCenterView` 用 `service.operationRecords`（来自 `OperationMonitor`，按 PID/comm 抓的），`IslandViewModel` 用 `sessionsViewModel.sessions`（来自 `HookServer` HTTP 推送），`AgentGuardFeature` 监听前者生成告警。**同一 agent 同一操作有 3 个不同来源/口径的数据**：
- 操作记录（process/file system）
- Session 状态（HTTP hook）
- Token 用量（扫描 jsonl 文件）

**后果**：
- 用户在 Agent 中心看 session，看到 token 100K，但操作记录里没对应行 — 因为 token 不走 OperationMonitor。
- 审计报告基于 operationRecords，但 agent session 里的 tool call 不一定生成 OperationRecord（特别是新 tool）。
- 灵动岛的 status 显示 token，但 token 来自 jsonl 扫描（5-20 秒延迟），hook token 实时但只显示在 island。

**修复建议**：
- 引入统一的 `AgentEventBus`，三个模块订阅同一事件流。
- 或者至少在 `SessionState` 上挂一个 `latestTokenUsage: TokenUsageSnapshot` 字段，让 Agent 中心和 island 都能读。
- 短期：文档化"三套数据流"在 README，避免误用。

---

### 3.2 TokenScopeSource 18 个 agent，path 匹配用 contains 太脆弱

**文件**：`TokenScopeLabView.swift:2004-2024, 2026-2043`

```swift
private func source(for root: URL) -> TokenScopeSource {
    let path = root.path.lowercased()
    if path.contains("codebuddy") || path.contains("codybuddy") { return .codeBuddy }
    if path.contains("cursor") { return .cursor }
    if path.contains("qoder") { return .qoder }
    if path.contains("cline") || path.contains("claude-dev") { return .cline }
    ...
}
```

**问题**：
- 用户目录叫 `my-cursor-project` 会被识别为 cursor。
- `claude-dev` 子串也会撞 `claude`，被前面 line 截走 OK；但 `qoder` vs `qclaw` 容易撞。
- 同一文件夹内嵌套的子目录会被多次识别为不同 source。

**修复**：
- 用完整 path 段比较：`path.split(separator: "/").contains("codebuddy")`。
- 或对 defaultPaths 做反向 map：`{path: source}` lookup。

---

### 3.3 TokenScopePricing 价格表硬编码、可能过时

**文件**：`TokenScopeLabView.swift:3206-3224`

```swift
static func estimate(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
    let lower = model.lowercased()
    let rates: (input: Double, output: Double, cacheRead: Double, cacheWrite: Double)
    if lower.contains("opus") { rates = (15.0, 75.0, 1.5, 18.75) }
    else if lower.contains("sonnet") || lower.contains("claude") { rates = (3.0, 15.0, 0.3, 3.75) }
    else if lower.contains("gpt-5") || lower.contains("codex") { rates = (1.25, 10.0, 0.125, 1.25) }
    ...
}
```

**问题**：
- 价格 100% 硬编码，厂商一改就错。
- "claude" 匹配太宽：claude-3-haiku 不是 3/15 美元。
- 用户实际计费可能跟估算有 30%+ 偏差（特别是 batch API、prompt cache 命中）。

**修复**：
- 把价格表抽到 JSON 配置（`pricing.json`），启动时加载。
- 提供"使用实际 `costUSD`（如果来源有）优先"逻辑。
- 在 UI 上明确标注"估算"。

---

### 3.4 AgentGuardFeature 内存 cache 不持久化

**位置**：整个 `AgentGuardFeature` 类（对比 `TokenScopeScanner.fileCache`）

- `TokenScopeScanner.fileCache` 是按文件 fingerprint 缓存的（size + mtime），避免重新解析。
- `AgentGuardFeature` 解析 hook event 每次都重新做（`checkSensitiveContent` `String(contentsOf:)` 读全文）。
- 应用重启后所有 alerts/historical 都没持久化（除了 alerts.json 本身，但 content 检查是从零开始）。

**修复**：
- 给 `checkSensitiveContent` 加文件级 cache（path → lastCheck timestamp + matched patterns）。
- 或者把检测结果写到 `sensitive_scan_cache.json`。

---

### 3.5 AgentGuardFeature `matchCommand` 冷启动黑名单缺失

**文件**：`AgentGuardFeature.swift:1364-1398` `defaultRules`

14 个 blacklist + 20 个 whitelist 启动时硬写入。
`init()` 检查 `if commandRules.isEmpty { commandRules = .defaultRules; save() }`。

**问题**：
- 如果用户编辑了一条 blacklist，下次启动如果他清空了 rules，会被 defaultRules 覆盖 — 数据丢失。
- 反过来，如果 defaultRules 升级（比如新加 `sudo curl | sh`），用户本地不会被更新，因为已经 saved。

**修复**：
- 启动时合并而不是覆盖：把 defaultRules 中"用户没自定义过的"加进去。
- 给 defaultRules 加版本号，迁移时升级。

---

### 3.6 AgentCenterView AgentCenterStatusFilterButton 命名混淆

**文件**：`AgentCenterView.swift:586-621`

- `AgentCenterStatusFilterButton(title: "All", status: nil, ...)` 显示 "All"。
- 但 `connectableAdapterCount` 又是另一个独立 computed。
- 三个 segment 按钮 + filter button + 5 个 StatCard 顶部叠加，UI 状态层级深。
- 切换 `selectedSection` 时 filter 状态保留，可能让用户困惑（"为什么 integrations 段只看 unavailable 的"）。

**修复**：
- 切换 section 时 reset filter。
- 或者把 filter 状态纳入 `selectedSection` 的 enum 内。

---

### 3.7 PermissionSheetView `reason` 输入是 lineLimit 1 的多行 editor

**文件**：`PermissionSheetView.swift:200-228`

```swift
private var denyInput: some View {
    VStack {
        Text("Deny Reason or Instruction")
        ZStack {
            TextEditor(text: $reason)        // 允许多行
                .frame(minHeight: 38, maxHeight: 48)  // 限高 1.5 行
            if reason.isEmpty {
                Text("placeholder")
            }
        }
    }
}
```

**问题**：
- maxHeight 48 但 placeholder 在 .padding(.vertical, 8) + 字体 11 — 实际 placeholder 会被截断。
- `allowsHitTesting(false)` 在 placeholder 上，但 TextEditor 区域有 padding，可能挡住用户点下半部分。

**修复**：
- 用 `TextField`（单行）+ `submitLabel(.done)`，因为 reason 不需要多行。
- 或者用 NSTextView 包装提供更稳的 placeholder。

---

### 3.8 AgentGuardTab 列表用 `id: \.offset` 不可靠

**文件**：`AgentGuardTab.swift:730-733`（protectedDirsView）

```swift
ForEach(Array(service.guardFeature.protectedDirs.enumerated()), id: \.offset) { index, dir in
    protectedDirRow(dir)
}
```

- 用 `id: \.offset` 不可靠：如果 protectedDirs 顺序变化，SwiftUI 复用 row 时 dir 跟 index 不匹配。
- 改用 `id: \.self`（path 是 String，已去重 OK）。

**修复**：

```swift
ForEach(service.guardFeature.protectedDirs, id: \.self) { dir in
    protectedDirRow(dir)
}
```

---

## 4. 跨模块总结

| 模块 | P0 数 | P1 数 | P2 数 | 状态 | 主要矛盾 |
|------|-------|-------|-------|------|---------|
| AgentGuard | 3 | 4 | 2 | 高风险 | I/O 路径、状态机、字符串匹配 |
| 灵动岛 | 2 | 3 | 2 | 中风险 | 双轨 sheet 状态、异步 session 覆盖 |
| Token 统计 | 1 | 2 | 2 | 中风险 | 性能、准确性、价格硬编码 |
| 三模块联动 | 0 | 0 | 1 | 架构债 | 3 套数据源不同步 |

---

## 5. 建议实施顺序

### 第一阶段 — P0（本周修完）

| # | 问题 | 涉及文件 | 工作量 |
|---|------|---------|--------|
| 1.1 | TokenScopeStore 8 秒硬超时 | `TokenScopeLabView.swift` | 1h |
| 1.2 | 文件写盘加 atomic | `AgentGuardFeature.swift` | 30min |
| 1.3 | Slider/Toggle 防抖 | `AgentGuardTab.swift` | 2h（含 helper 抽取） |
| 1.4 | `incrementRuleCount` 日期/区域 | `AgentGuardFeature.swift` | 1h |
| 1.5 | 删 Legacy sheet 状态 | `IslandViewModel.swift` | 1h |
| 1.6 | PermissionSheet 切 session 重置 | `PermissionSheet.swift` + `PlanApprovalSheet.swift` | 1h |

### 第二阶段 — P1（下周修）

| # | 问题 | 工作量 |
|---|------|--------|
| 2.1 | `operationTypeForHookTool` 鲁棒性 | 2h |
| 2.2 | `isAuditableAgentRecord` 黑名单 | 1h |
| 2.3 | regex cache | 30min |
| 2.4 | `currentSession` 异步覆盖 | 2h |
| 2.5 | `await MainActor.run` 多余 hop | 30min |
| 2.6 | Toast 重叠 | 30min |
| 2.7 | TokenScopeScanner 并发 | 2h |
| 2.8 | 文件大小限制提示 | 1h |
| 2.9 | `prefixText.contains` 优化 | 30min |
| 2.10 | QuestionSheet 状态机 | 3h（含测试） |
| 2.11 | PlanApprovalSheet 延后路径 | 1h |
| 2.12 | `pendingApprovalSessions` 缓存 | 30min |
| 2.13 | 重复 Binding 抽取 | 2h |
| 2.14 | IslandWindow tracking area | 30min |

### 第三阶段 — P2（迭代修）

| # | 问题 | 备注 |
|---|------|------|
| 3.1 | 跨模块数据流统一 | **需先讨论架构**，不建议直接动 |
| 3.2 | TokenScopeSource path 匹配 | 1h |
| 3.3 | TokenScopePricing 抽配置 | 3h |
| 3.4 | AgentGuardFeature cache 持久化 | 2h |
| 3.5 | defaultRules 版本管理 | 2h |
| 3.6 | AgentCenter filter reset | 30min |
| 3.7 | PermissionSheet reason 单行化 | 30min |
| 3.8 | `id: \.self` 修复 | 10min |

---

## 6. 测试建议

P0 / P1 修复建议配套以下测试：

- **AgentGuardFeature** — `XCTest` 覆盖 `incrementRuleCount` 时区切换、`operationTypeForHookTool` 各种命令名。
- **IslandViewModel** — 模拟 session 切换、并发事件流、queue 推进。
- **TokenScopeStore** — 构造大文件、mock scanner、模拟扫描超时。
- **UI 集成测试** — 拖动 Slider 100ms 内 30 次，验证只写盘 1 次。

---

## 7. 风险与建议

1. **不要一次性全部重构**：P0 6 条修完后再开 P1；P1 涉及异步 + 状态机的修复建议 review 一遍再合。
2. **跨模块数据流（3.1）** 是架构级改动，建议先开 RFC 讨论，不要边做边改。
3. **价格表（3.3）** 可以做"读取内置默认 + 用户覆盖"，但要规划好更新路径。
4. **回归测试**：每次修 P0 / P1 都要跑 `xcodeproj` 全量 build，因为涉及 9 个文件 + CoreData 持久化。

---

*文档结束*
