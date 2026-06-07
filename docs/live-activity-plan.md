# AIMacCleaner：把「概览 - 当前活跃会话」实时显示在 macOS 顶栏/灵动岛风格区域

> 本文档是技术方案与示例代码，**不修改任何项目代码**，仅作为落地参考。
> 项目根目录：`/Users/zhouxiaoming/Downloads/MacCleaner`

---

## 0. 重要前置事实：macOS 没有「灵动岛」

先讲清楚这件事，否则后面会被「为什么不能直接像 iOS 一样」反复打断：

| 维度 | iOS 灵动岛 | macOS 对应能力 |
|---|---|---|
| 硬件 | iPhone 14 Pro+ 的挖孔屏 + 原深感模组 | **Mac 没有灵动岛硬件**，菜单栏是固定长条 |
| 框架 | `ActivityKit`（iOS 16.1+）+ `WidgetKit` | `ActivityKit`（macOS 14+）+ `WidgetKit`，**但 Live Activity 内容显示在「菜单栏右侧实时活动」与「控制中心 / 通知中心」，没有可展开/收起的药丸 UI** |
| 后台刷新 | Push / `Activity.update` (BG App Refresh) | macOS 14+ 支持 Live Activity 后台更新，**依然没有独立「灵动岛」区域** |
| 通用替代 | — | `NSStatusItem`（菜单栏图标 + 自定义 `NSView`/文本）+ `NSDockTile`（Dock 角标） |

如果用户实际想要的是「**顶栏（菜单栏）实时小卡片 + 数字角标**」这个体验，下面方案能直接满足；
如果坚持「**和 iPhone 灵动岛一样的药丸**」，macOS 原生做不到，**只能等 Apple 在 macOS 后续版本开放（目前到 macOS 15 Sequoia 没有）**。

> 下面按「最接近灵动岛的体验」给三个候选方案，**推荐方案 A**（成本低、效果稳），**进阶方案 B**（更原生、要做 Widget Extension 子项目）。

---

## 1. 现状梳理

### 1.1 数据源

| 项 | 值 |
|---|---|
| 类型 | `AgentMonitorSessionSnapshot`（`ContentView.swift:705`） |
| 持有者 | `AgentMonitorOverviewStore`（`@MainActor`），`@Published sessions`（`ContentView.swift:744`） |
| 扫描器 | `AgentMonitorOverviewScanner` |
| 活跃判定 | `isActiveSession`（`ContentView.swift:3611`）：`status ∈ {Thinking, Executing, Waiting, Paused}` **或** `currentTask 非空且 status ∉ {History, Done}` |
| 刷新策略 | `Timer.publish(every: 5, on: .main)` 触发 `overviewStore.refresh()` → `refreshRealtime()` 节流 3 秒（`ContentView.swift:785-826`） |
| 概览页 UI | `AppOverviewTab`（`ContentView.swift:2425`）→ `AgentCommandDashboardView`（`ContentView.swift:3457`） |
| 卡片展示字段 | `currentSessionUsageCard`（`ContentView.swift:3914`）：`agentCode` + `projectName` + `shortSessionId` + `displayLocation` + `status` + `model` + `contextPercent/window` + `tokens` + `memoryMB` + `turnCount` + `pid` + `runningToolCount` + `currentTask`（限 2 行） |

### 1.2 Session 关键字段（灵动岛需要展示的）

```swift
struct AgentMonitorSessionSnapshot: Identifiable {
    let id: String                         // "agentName|sessionId|sourcePath"
    let agentName: String                  // "Claude Code" / "Codex" / ...
    let pid: Int?
    let sessionId: String
    let status: String                     // "Thinking" | "Executing" | "Waiting" | "Paused" | "History" | "Done" | "Unknown"
    let projectName: String
    let projectPath: String
    let model: String                      // "gpt-4o-mini" / "claude-3.5" ...
    let tokens: AgentMonitorTokenBreakdown // input / output / cacheRead
    let contextPercent: Double             // 0.0~1.0
    let contextWindow: Int                 // 200_000 等
    let turnCount: Int
    let currentTask: String                // 任务描述
    let toolCount: Int
    let runningToolCount: Int
    let childCount: Int
    let ports: [Int]
    let memoryMB: Int?
    let latestActivity: Date?
    let sourcePath: String
}
```

### 1.3 当前限制

- `LSMinimumSystemVersion = 13.0`（要跑真正的 Live Activity 必须升到 14+）
- 单 `com.apple.product-type.application` target，**没有 Widget Extension**（要做 Live Activity 必须加）
- `AIMacCleaner.entitlements` 启用了 `com.apple.security.app-sandbox`，对 Live Activity / NSStatusItem 都不冲突
- Bundle ID：`com.aimaccleaner.app`
- 项目里**没有**任何 `ActivityKit` / `WidgetKit` / `NSStatusBar` / `NSDockTile` 代码（已全局搜过）

---

## 2. 三个候选方案

### 方案 A：菜单栏（NSStatusItem）实时卡片 —— **推荐**

**用户感知**：Mac 顶栏（菜单栏）右侧多一个 AIMacCleaner 图标 + 旁边一个 24×24 的小卡片，会随活跃会话状态自动刷新；点开是完整的 popover 概览。
**本质**：把 macOS 菜单栏右侧当「灵动岛」用 —— 这是 macOS 上最接近灵动岛体验、零额外 target、零 App Extension 的做法。
**最低系统**：macOS 11+（项目现状 13.0 已满足）

#### 2.1.A 架构图

```
┌─────────────────────── 菜单栏 (screen top) ───────────────────────┐
│  App menu   Edit   ...   battery   wifi   [AIMacCleaner▸status]  │
└───────────────────────────────────────────────────────────────────┘
                                                       ▲
                                NSStatusItem 左侧 icon + 自定义 NSView
                                                       │
                                       ┌───────────────┴──────────────┐
                                       │  AgentLiveActivityStatusItem  │  ← 新增
                                       │  (NSView 子类，30x18)         │
                                       │   • 状态点 (颜色由 status 决定)│
                                       │   • AgentCode 文本 ("CL"/"CD")│
                                       │   • context% 数字            │
                                       └──────────────────────────────┘
                                                       │
                                              onClick → NSPopover
                                                       │
                                       ┌───────────────┴──────────────┐
                                       │  LiveActivityPopoverView      │  ← 新增 (SwiftUI)
                                       │   • 复用 currentSessionUsageCard
                                       │   • 复用 metricStrip
                                       │   • 实时刷新（Timer 3s）      │
                                       └──────────────────────────────┘
```

#### 2.2.A 接入点（不改代码的情况下要做的事）

1. **入口单例化**：`AgentMonitorOverviewStore` 当前挂在 `ContentView` 里（`@StateObject`），需要在 `AIMacCleanerApp.swift` 的 `App` 初始化里直接构造一个全局实例，存到 `AppDelegate` 或 `@StateObject` 中。
2. **数据流**：把 `overviewStore.refresh()` 的 `Timer.publish(every: 5)` **上移**到 `App` 层（避免 popover 关闭时停止刷新）；store 已经是 `@MainActor ObservableObject`，subscribe 简单。
3. **活跃会话排序**：以 `latestActivity` desc 取第一条作为「主显示」；多于 1 个时 icon 旁用「+N」标识。

#### 2.3.A 核心示例代码

**新增 `Services/LiveActivityStatusItem.swift`**（仅示例，未落盘到项目）

```swift
// AIMacCleaner/Services/LiveActivityStatusItem.swift
import AppKit
import SwiftUI
import Combine

/// 方案 A：把「概览 - 当前活跃会话」实时打到 macOS 菜单栏
/// - NSStatusItem 左侧 22x22 icon + 右侧 60x18 自定义 NSView
/// - 状态点颜色对应 status，文本显示 AgentCode + context%
/// - 点击弹出 NSPopover，popover 里复用 AgentCommandDashboardView 风格的小卡片
@MainActor
final class LiveActivityStatusItem {
    static let shared = LiveActivityStatusItem()

    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private var cancellables = Set<AnyCancellable>()

    // 强引用 store，避免 popover 关闭后数据断流
    private weak var store: AgentMonitorOverviewStore?

    private init() {}

    func attach(to store: AgentMonitorOverviewStore) {
        self.store = store

        // 1. 注册 status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "shield.lefthalf.filled",
                                   accessibilityDescription: "AgentGuard")
            button.image?.isTemplate = true
            button.target = self
            button.action = #selector(togglePopover(_:))
        }

        // 2. 右侧挂一个自定义 NSView 显示活跃会话摘要
        let compactView = CompactLiveActivityView()
        compactView.translatesAutoresizingMaskIntoConstraints = false
        compactView.widthAnchor.constraint(equalToConstant: 92).isActive = true
        compactView.heightAnchor.constraint(equalToConstant: 22).isActive = true
        statusItem.addAttributedTitle(NSAttributedString())  // 占位
        // 用 customView 模式更稳：
        if let button = statusItem.button {
            button.addSubview(compactView)
            compactView.frame = NSRect(x: button.bounds.width, y: 0,
                                       width: 92, height: 22)
        }
        self.compactView = compactView

        // 3. popover
        popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 380, height: 360)
        popover.contentViewController = NSHostingController(
            rootView: LiveActivityPopoverView(store: store)
        )

        // 4. 订阅 store.sessions，节流刷新 UI
        store.$sessions
            .receive(on: DispatchQueue.main)
            .throttle(for: .seconds(2), scheduler: DispatchQueue.main, latest: true)
            .sink { [weak self] sessions in
                self?.render(sessions: sessions)
            }
            .store(in: &cancellables)
    }

    private weak var compactView: CompactLiveActivityView?

    private func render(sessions: [AgentMonitorSessionSnapshot]) {
        let active = sessions.filter { isActive($0) }
        let primary = active.max { (a, b) in
            (a.latestActivity ?? .distantPast) < (b.latestActivity ?? .distantPast)
        }
        compactView?.update(session: primary, extraCount: max(0, active.count - 1))
    }

    private func isActive(_ s: AgentMonitorSessionSnapshot) -> Bool {
        ["Thinking", "Executing", "Waiting", "Paused"].contains(s.status) ||
        (!s.currentTask.isEmpty && s.status != "History" && s.status != "Done")
    }

    @objc private func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }
}

// MARK: - 紧凑视图（22 高，纯手绘，不依赖 SwiftUI 渲染开销）
final class CompactLiveActivityView: NSView {
    private let dotLayer = CAShapeLayer()
    private let codeLabel = NSTextField(labelWithString: "—")
    private let percentLabel = NSTextField(labelWithString: "")
    private let extraLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        dotLayer.frame = NSRect(x: 0, y: 6, width: 8, height: 8)
        dotLayer.path = NSBezierPath(ovalIn: dotLayer.bounds).cgPath
        dotLayer.fillColor = NSColor.systemGray.cgColor
        layer?.addSublayer(dotLayer)

        codeLabel.font = .systemFont(ofSize: 11, weight: .semibold)
        codeLabel.textColor = .labelColor
        codeLabel.frame = NSRect(x: 12, y: 4, width: 28, height: 14)
        addSubview(codeLabel)

        percentLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        percentLabel.textColor = .secondaryLabelColor
        percentLabel.frame = NSRect(x: 40, y: 4, width: 36, height: 14)
        addSubview(percentLabel)

        extraLabel.font = .systemFont(ofSize: 10, weight: .medium)
        extraLabel.textColor = .tertiaryLabelColor
        extraLabel.frame = NSRect(x: 76, y: 4, width: 14, height: 14)
        addSubview(extraLabel)
    }

    required init?(coder: NSCoder) { fatalError() }

    func update(session: AgentMonitorSessionSnapshot?, extraCount: Int) {
        guard let s = session else {
            dotLayer.fillColor = NSColor.systemGray.cgColor
            codeLabel.stringValue = "—"
            percentLabel.stringValue = "等待"
            extraLabel.stringValue = ""
            return
        }
        dotLayer.fillColor = color(for: s.status).cgColor
        codeLabel.stringValue = agentCode(s.agentName)
        let pct = Int((s.contextPercent * 100).rounded())
        percentLabel.stringValue = "\(pct)%"
        extraLabel.stringValue = extraCount > 0 ? "+\(extraCount)" : ""
    }

    private func color(for status: String) -> NSColor {
        switch status {
        case "Waiting":   return .systemBlue
        case "Paused":    return .systemOrange
        case "Thinking":  return .systemPurple
        case "Executing": return .systemGreen
        case "History":   return .systemGray
        case "Done":      return .systemTeal
        default:          return .systemGray
        }
    }

    private func agentCode(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("codex")     { return "CD" }
        if name.localizedCaseInsensitiveContains("claude")    { return "CL" }
        if name.localizedCaseInsensitiveContains("opencode")  { return "OC" }
        if name.localizedCaseInsensitiveContains("gemini")    { return "GM" }
        if name.localizedCaseInsensitiveContains("cursor")    { return "CU" }
        return String(name.prefix(2)).uppercased()
    }
}

// MARK: - Popover 视图（SwiftUI，复用概览页风格）
struct LiveActivityPopoverView: View {
    @ObservedObject var store: AgentMonitorOverviewStore
    @EnvironmentObject var localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .foregroundStyle(.green)
                Text(localizer.overviewLiveActivity)
                    .font(.headline)
                Spacer()
                Button("打开主界面") { openMain() }
                    .buttonStyle(.borderless)
            }

            if let session = store.sessions.filter(Self.isActive).first {
                ActiveSessionRow(session: session)
            } else {
                Text(localizer.overviewNoActiveSession)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(width: 360)

        // 后台持续刷新（即使 popover 关闭也保持）
        .onAppear { store.refresh() }
    }

    static func isActive(_ s: AgentMonitorSessionSnapshot) -> Bool {
        ["Thinking", "Executing", "Waiting", "Paused"].contains(s.status) ||
        (!s.currentTask.isEmpty && s.status != "History" && s.status != "Done")
    }

    private func openMain() {
        NSApp.activate(ignoringOtherApps: true)
        // 切到概览页的逻辑可复用 ContentView 的 selectedTab 切换
    }
}

struct ActiveSessionRow: View {
    let session: AgentMonitorSessionSnapshot
    @EnvironmentObject var localizer: Localizer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.agentName).font(.headline)
                Spacer()
                Text(statusText(session.status))
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(statusColor(session.status).opacity(0.15))
                    .foregroundStyle(statusColor(session.status))
                    .clipShape(Capsule())
            }
            HStack(spacing: 12) {
                Label(session.projectName, systemImage: "folder")
                Label("\(Int(session.contextPercent * 100))% / \(windowText(session.contextWindow))",
                      systemImage: "rectangle.compress.vertical")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(session.currentTask)
                .font(.callout)
                .lineLimit(3)
            ProgressView(value: session.contextPercent)
                .progressViewStyle(.linear)
                .tint(statusColor(session.status))
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    // 复用 ContentView 的 statusText / statusColor / windowText 逻辑
    private func statusText(_ s: String) -> String { /* 复用 ContentView:4439 */ }
    private func statusColor(_ s: String) -> Color { /* 复用 ContentView:4451 */ }
    private func windowText(_ w: Int) -> String { /* 复用 ContentView:4539 */ }
}
```

**修改 `AIMacCleanerApp.swift`（一行启动）**

```swift
@main
struct AIMacCleanerApp: App {
    @StateObject private var overviewStore = AgentMonitorOverviewStore()
    @StateObject private var localizer = Localizer.shared
    @StateObject private var service = ScannerService()

    init() {
        // 挂载菜单栏实时活动
        LiveActivityStatusItem.shared.attach(to: AgentMonitorOverviewStore.shared)
        // ↑ 简化：把 AgentMonitorOverviewStore 改成单例或在 AppState 里持有
    }

    var body: some Scene {
        WindowGroup { ContentView(overviewStore: overviewStore) }
    }
}
```

#### 2.4.A 风险与依赖

- ⚠️ **不需**新增 App Group / Extension / 系统权限
- ⚠️ `NSStatusItem` 在 macOS 13 上完全可用
- ⚠️ `NSPopover` 在 `LSUIElement=false`（项目当前）下行为正常；如果以后打开「仅菜单栏常驻」模式，要保证 popover 点击外部能关闭
- ⚠️ **菜单栏图标会跟着 SwiftUI 主题色（深色/浅色）自适应**，因为用 `isTemplate = true`

#### 2.5.A 实施步骤（不影响业务）

1. 把 `AgentMonitorOverviewStore` 的 `init` 暴露为单例（最小侵入：加一个 `static let shared`）。
2. 在 `AIMacCleanerApp.init()` 里调 `LiveActivityStatusItem.shared.attach(to: ...)`。
3. 在设置面板加一个「在菜单栏显示实时活动」开关（@AppStorage 即可），默认开。
4. 退出行为：「仅保留菜单栏」时（项目已有这个选项）保证 status item 持续工作。

---

### 方案 B：真正的 macOS Live Activity（ActivityKit + WidgetKit）—— 进阶

**用户感知**：菜单栏右侧的「实时活动」胶囊、控制中心卡片。会话状态变化时自动推送更新。
**最低系统**：macOS 14 (Sonoma) 及以上
**代价**：必须新增一个 **Widget Extension target**；Info.plist 加 `NSSupportsLiveActivities = YES`；重新签名。

#### 2.1.B 架构图

```
┌───── Main App (AIMacCleaner.app) ─────┐    ┌─── Widget Extension ────┐
│                                        │    │                          │
│ AgentMonitorOverviewStore              │    │  AgentLiveActivityWidget │
│   ↓ 监听 sessions 变化                 │    │   ↓                      │
│ LiveActivityCenter                     │◄──►│   ActivityConfiguration   │
│   ↓                                    │    │   ↓                      │
│ Activity<AgentSessionAttributes>       │    │   DynamicIsland(compact) │
│   • .request / .update / .end          │    │   DynamicIsland(expanded)│
│                                        │    │   DynamicIsland(minimal) │
│ Attributes (静态字段)                   │    │                          │
│ ContentState (动态字段)                 │    │                          │
└────────────────────────────────────────┘    └──────────────────────────┘
```

#### 2.2.B 共享数据模型（必须能被 main app 和 widget 同时看到）

新增 `Shared/AgentSessionAttributes.swift`（两个 target 都加进来）：

```swift
import ActivityKit
import Foundation

// 静态：会话开始时确定，整个生命周期不变
public struct AgentSessionAttributes: ActivityAttributes {
    public typealias ContentState = AgentSessionState

    public let agentName: String          // "Claude Code"
    public let sessionId: String          // "a1b2c3d4"
    public let projectName: String        // "AIMacCleaner"
    public let projectPath: String
    public let sourcePath: String
    public let model: String

    public init(agentName: String, sessionId: String, projectName: String,
                projectPath: String, sourcePath: String, model: String) {
        self.agentName = agentName
        self.sessionId = sessionId
        self.projectName = projectName
        self.projectPath = projectPath
        self.sourcePath = sourcePath
        self.model = model
    }
}

// 动态：会随时间变化（每次 update 都重发）
public struct AgentSessionState: Codable, Hashable {
    public enum Status: String, Codable, Hashable {
        case waiting = "Waiting"
        case paused = "Paused"
        case thinking = "Thinking"
        case executing = "Executing"
        case done = "Done"
        case history = "History"
    }
    public var status: Status
    public var currentTask: String
    public var contextPercent: Double      // 0.0~1.0
    public var contextWindow: Int
    public var inputTokens: Int
    public var outputTokens: Int
    public var cacheReadTokens: Int
    public var turnCount: Int
    public var memoryMB: Int?
    public var runningToolCount: Int
    public var latestActivity: Date

    public init(status: Status, currentTask: String, contextPercent: Double,
                contextWindow: Int, inputTokens: Int, outputTokens: Int,
                cacheReadTokens: Int, turnCount: Int, memoryMB: Int?,
                runningToolCount: Int, latestActivity: Date) {
        self.status = status
        self.currentTask = currentTask
        self.contextPercent = contextPercent
        self.contextWindow = contextWindow
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.turnCount = turnCount
        self.memoryMB = memoryMB
        self.runningToolCount = runningToolCount
        self.latestActivity = latestActivity
    }

    public var totalTokens: Int { inputTokens + outputTokens + cacheReadTokens }
}
```

#### 2.3.B Widget Extension

新增 target `AgentActivityWidget`（Xcode → File → New → Target → Widget Extension，**不要勾**「Include Live Activity」再取消，直接选 Widget Extension 然后选 Live Activity 类型）。

**`AgentActivityWidget/AgentActivityWidgetBundle.swift`**

```swift
import WidgetKit
import SwiftUI

@main
struct AgentActivityWidgetBundle: WidgetBundle {
    var body: some Widget {
        AgentSessionLiveActivity()
    }
}
```

**`AgentActivityWidget/AgentSessionLiveActivity.swift`**

```swift
import ActivityKit
import WidgetKit
import SwiftUI

struct AgentSessionLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: AgentSessionAttributes.self) { context in
            // 锁屏 / 通知中心卡片（macOS 上是控制中心 / 通知中心）
            LockScreenView(state: context.state, attributes: context.attributes)
                .padding(16)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            // 灵动岛风格（macOS 上由系统映射到菜单栏「实时活动」胶囊）
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    AgentBadge(agentName: context.attributes.agentName)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    StatusPill(status: context.state.status)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.projectName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(context.state.currentTask)
                            .font(.callout)
                            .lineLimit(2)
                        ProgressView(value: context.state.contextPercent)
                            .tint(color(for: context.state.status))
                        HStack {
                            Text("\(Int(context.state.contextPercent * 100))% / \(windowText(context.state.contextWindow))")
                            Spacer()
                            Text("\(context.state.turnCount) 轮 · \(context.state.runningToolCount) 工具")
                        }
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    }
                }
            } compactLeading: {
                AgentBadge(agentName: context.attributes.agentName, compact: true)
            } compactTrailing: {
                Text("\(Int(context.state.contextPercent * 100))%")
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Circle()
                    .fill(color(for: context.state.status))
                    .frame(width: 12, height: 12)
            }
            .keylineTint(color(for: context.state.status))
        }
    }

    private func color(for status: AgentSessionState.Status) -> Color {
        switch status {
        case .waiting:   return .blue
        case .paused:    return .orange
        case .thinking:  return .purple
        case .executing: return .green
        case .done:      return .teal
        case .history:   return .gray
        }
    }
    private func windowText(_ w: Int) -> String {
        guard w > 0 else { return "—" }
        if w >= 1_000_000 { return String(format: "%.1fM", Double(w)/1_000_000) }
        if w >= 1_000 { return String(format: "%.1fk", Double(w)/1_000) }
        return "\(w)"
    }
}

struct LockScreenView: View {
    let state: AgentSessionState
    let attributes: AgentSessionAttributes
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                AgentBadge(agentName: attributes.agentName)
                Spacer()
                Text(state.status.rawValue)
                    .font(.caption)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.ultraThinMaterial)
                    .clipShape(Capsule())
            }
            Text(attributes.projectName).font(.headline)
            Text(state.currentTask).font(.callout).lineLimit(2)
            ProgressView(value: state.contextPercent)
        }
    }
}

struct AgentBadge: View {
    let agentName: String
    var compact: Bool = false
    var body: some View {
        Text(code(agentName))
            .font(compact ? .caption2 : .caption.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color(agentName).opacity(0.25))
            .foregroundStyle(color(agentName))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    private func code(_ name: String) -> String {
        if name.localizedCaseInsensitiveContains("codex")    { return "CD" }
        if name.localizedCaseInsensitiveContains("claude")   { return "CL" }
        if name.localizedCaseInsensitiveContains("opencode") { return "OC" }
        if name.localizedCaseInsensitiveContains("gemini")   { return "GM" }
        if name.localizedCaseInsensitiveContains("cursor")   { return "CU" }
        return String(name.prefix(2)).uppercased()
    }
    private func color(_ name: String) -> Color {
        if name.localizedCaseInsensitiveContains("codex")    { return .teal }
        if name.localizedCaseInsensitiveContains("claude")   { return .purple }
        if name.localizedCaseInsensitiveContains("opencode") { return .green }
        return .blue
    }
}

struct StatusPill: View {
    let status: AgentSessionState.Status
    var body: some View {
        Text(status.rawValue)
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
    }
}
```

#### 2.4.B Main App 侧控制器

新增 `Services/LiveActivityCenter.swift`：

```swift
import ActivityKit
import os.log

@MainActor
final class LiveActivityCenter {
    static let shared = LiveActivityCenter()
    private let log = Logger(subsystem: "com.aimaccleaner.app", category: "LiveActivity")
    private var activities: [String: Activity<AgentSessionAttributes>] = [:]

    private init() {}

    /// 是否可用：macOS 14+ 且用户开启 + 系统设置允许
    var isAvailable: Bool {
        if #available(macOS 14.0, *) {
            return ActivityAuthorizationInfo().areActivitiesEnabled
        }
        return false
    }

    /// 启动或更新一个 Live Activity（key = session.id）
    func upsert(session: AgentMonitorSessionSnapshot) {
        guard isAvailable else { return }
        let attrs = AgentSessionAttributes(
            agentName: session.agentName,
            sessionId: session.sessionId,
            projectName: session.projectName,
            projectPath: session.projectPath,
            sourcePath: session.sourcePath,
            model: session.model
        )
        let state = AgentSessionState(
            status: AgentSessionState.Status(rawValue: session.status) ?? .waiting,
            currentTask: session.currentTask,
            contextPercent: session.contextPercent,
            contextWindow: session.contextWindow,
            inputTokens: session.tokens.input,
            outputTokens: session.tokens.output,
            cacheReadTokens: session.tokens.cacheRead,
            turnCount: session.turnCount,
            memoryMB: session.memoryMB,
            runningToolCount: session.runningToolCount,
            latestActivity: session.latestActivity ?? Date()
        )

        if let existing = activities[session.id] {
            Task { await existing.update(ActivityContent(state: state, staleDate: nil)) }
        } else {
            do {
                let activity = try Activity<AgentSessionAttributes>.request(
                    attributes: attrs,
                    content: ActivityContent(state: state, staleDate: nil),
                    pushType: nil
                )
                activities[session.id] = activity
            } catch {
                log.error("Activity.request failed: \(error.localizedDescription)")
            }
        }
    }

    func end(sessionId: String) {
        guard let a = activities.removeValue(forKey: sessionId) else { return }
        Task { await a.end(nil, dismissalPolicy: .immediate) }
    }

    func endAll() {
        for (_, a) in activities {
            Task { await a.end(nil, dismissalPolicy: .immediate) }
        }
        activities.removeAll()
    }
}
```

#### 2.5.B 接入点

`AgentMonitorOverviewStore.refreshRealtime()` 在更新 `sessions` 后，diff 出新增/变更/结束的 session，调用 `LiveActivityCenter.shared`：

```swift
// 在 ContentView.swift:808 self.sessions = ... 之后加：
diffForLiveActivity(old: previousIDs, new: self.sessions.map(\.id)).forEach { change in
    switch change {
    case .added(let s), .updated(let s): LiveActivityCenter.shared.upsert(session: s)
    case .removed(let id):               LiveActivityCenter.shared.end(sessionId: id)
    }
}
```

#### 2.6.B 工程改动清单

| 改动 | 文件 | 类型 |
|---|---|---|
| `NSSupportsLiveActivities = YES` | `Info.plist` | 改 |
| `LSMinimumSystemVersion` 升到 14.0 | `Info.plist` / `project.yml` | 改 |
| 新增 Widget Extension target | `AIMacCleaner.xcodeproj` | 加 |
| `AgentSessionAttributes.swift` | 共享给两个 target | 新增 |
| `AgentSessionLiveActivity.swift` | Widget Extension | 新增 |
| `AgentActivityWidgetBundle.swift` | Widget Extension | 新增 |
| `LiveActivityCenter.swift` | Main app | 新增 |
| `ActivityKit.framework` 链接 | 两个 target | 改 |
| `WidgetKit.framework` 链接 | Widget Extension | 改 |
| 代码签名（Widget Extension 必须随主 app 签） | `AIMacCleaner.entitlements` | 改 |

#### 2.7.B 风险与坑

- ⚠️ Widget Extension 是单独的进程，**不能直接访问主 app 的 `AgentMonitorOverviewStore`** —— 数据必须通过 `ActivityContent` 序列化过去（这就是为啥 `ContentState` 必须是 `Codable`）
- ⚠️ App Sandbox 下 Live Activity **OK**，但 Widget Extension 需要自己的 entitlements
- ⚠️ macOS 14.0 早期版本有 Live Activity 显示问题，建议把 `LSMinimumSystemVersion` 直接拉到 14.4
- ⚠️ 系统限制：每个 app 同时最多 ~10 个 Live Activity，概览里活跃会话可能远超 10，要做 top-N 策略
- ⚠️ Activity 的 `pushType` 留 `nil`（本地更新），主 app 死了就停；如果想要会话结束后还能看摘要，要再保存一个 Watch app / Handoff

---

### 方案 C：Dock 角标 + 菜单栏数字（最轻量）

**用户感知**：Dock 图标右下角显示活跃会话数 + 菜单栏图标右侧显示小数字。
**最低系统**：macOS 11+。
**不覆盖「灵动岛」** 但能给出「一直在看」的视觉锚点。

```swift
@MainActor
final class DockActivityBadge {
    static let shared = DockActivityBadge()
    private init() {}

    func update(activeCount: Int, primary: AgentMonitorSessionSnapshot?) {
        let tile = NSApp.dockTile
        tile.badgeLabel = activeCount > 0 ? "\(activeCount)" : nil
        tile.display()

        // 如果有 status item，加数字
        // (复用方案 A 的 status item)
    }
}
```

适用场景：用户其实只想要「瞥一眼就知道有几个 AI 在跑」，不需要看任务详情。

---

## 3. 方案选择决策树

```
Q1: 用户要的是「实时看到活跃会话状态」还是「和 iPhone 灵动岛一比一复刻」？
    │
    ├─ 一比一复刻 ──→  暂不支持（macOS 没有灵动岛硬件）
    │
    └─ 实时状态 ──┬─ 想要展开看详情 ─→  方案 A（NSStatusItem + Popover）★推荐
                  ├─ 想要控制中心那种系统级卡片 ─→  方案 B（Live Activity）
                  └─ 只想瞥一眼数量 ──→  方案 C（Dock 角标）
```

**我的建议（如果要拍板）**：

- **第一步：方案 A 落地**（1~2 天）
  - 不需要新 target
  - 兼容 macOS 13
  - 体验上「菜单栏右侧的小卡片 + 点开 popover」**和 iPhone 灵动岛展开态视觉等价**

- **第二步：如果用户强烈要「Live Activity / 控制中心」效果**：再上方案 B
  - 需要拆 Widget Extension
  - 升 macOS 14+
  - 改签名链路

---

## 4. 复用建议（不改代码也要先记住的事实）

写代码时这几个点必须照搬现有实现，不能新造轮子：

1. **活跃判定** = `ContentView.swift:3611` 的 `isActiveSession` 逻辑（status ∈ {Thinking, Executing, Waiting, Paused} 或有 task 且非 History/Done）
2. **状态颜色映射** = `ContentView.swift:4451` `statusColor`
3. **状态文案映射** = `ContentView.swift:4439` `statusText`
4. **AgentCode / AgentColor** = `ContentView.swift:4473-4487`
5. **短路径 / 配置根** = `ContentView.swift:4489-4527`
6. **窗口 / Token 格式化** = `ContentView.swift:4539-4550`
7. **数据源** = `AgentMonitorOverviewStore.sessions`（`ContentView.swift:744`）
8. **刷新节流** = `refreshRealtime` 里 3 秒节流（`ContentView.swift:787-789`）

> 建议把 `statusText / statusColor / agentCode / agentColor / windowText / compactCount` 抽到 `Localizer` 或新 `Models/SessionFormatting.swift`，避免方案 A/B 各自复制一份。

---

## 5. 测试与验收

不论哪个方案，验收用例都一致：

| 场景 | 期望 |
|---|---|
| 启动一个 Claude Code agent，思考中 | 状态点 = 紫色，文本 = "CL"，context% 实时跳 |
| 切换到 Executing | 状态点 = 绿色，进度条/文字变化 |
| 等待用户输入（Waiting） | 状态点 = 蓝色 |
| 暂停（Paused） | 状态点 = 橙色 |
| 全部结束 | 状态点 = 灰色，文本 = "等待" 或 "—" |
| 多个 agent 同时活跃 | 主显示按 `latestActivity` 最新，其余用 "+N" |
| 退出 / 重启 app | 重建 status item / live activity，**不残留历史** |
| 离线 / 沙盒受限 | 优雅降级到「等待」状态，不崩 |
| 长时间运行（>2h） | 无内存泄漏，CALayer 释放，Combine 订阅清理 |

---

## 6. 不在本文档范围内（避免范围蔓延）

- 推送更新（push-based Live Activity，需要后端）—— 项目当前是本地扫描，不需要
- Handoff 到 iPhone —— 项目是 macOS 原生
- 快捷指令（Siri Shortcuts）触发 Live Activity —— 可以但不是这次需求
- 多语言（方案 A/B 的 UI 文本必须走 `Localizer`，**不要再写死中英文字符串**）
