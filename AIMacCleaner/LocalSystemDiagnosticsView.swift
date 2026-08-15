import AppKit
import Darwin
import Foundation
import SwiftUI

struct LocalSystemDiagnosticsView: View {
    @EnvironmentObject private var localizer: Localizer
    @StateObject private var model: LocalSystemDiagnosticsModel
    private let includesNetwork: Bool

    init(includesNetwork: Bool = true) {
        self.includesNetwork = includesNetwork
        _model = StateObject(wrappedValue: LocalSystemDiagnosticsModel(includesNetwork: includesNetwork))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                PageHeader(
                    icon: includesNetwork ? "network" : "checklist",
                    title: includesNetwork
                        ? localizer.t("本机诊断", en: "Local Diagnostics")
                        : localizer.t("本机巡检", en: "Local System Audit"),
                    subtitle: includesNetwork
                        ? localizer.t("检查出口网络、启动项和本机隐私动作。", en: "Inspect network egress, launch items, and local privacy actions.")
                        : localizer.t("检查启动项并执行明确的本机隐私动作；网络诊断已统一到 IP 概览插件。", en: "Audit launch items and run explicit local privacy actions. Network diagnostics now live in the IP Overview plugin."),
                    color: Theme.Colors.teal
                ) {
                    Button {
                        model.refresh()
                    } label: {
                        Label(
                            model.isRefreshing ? localizer.t("诊断中", en: "Checking") : localizer.refresh,
                            systemImage: "arrow.clockwise"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.isRefreshing)
                }

                diagnosticSummary

                if includesNetwork {
                    HStack(alignment: .top, spacing: Theme.Spacing.lg) {
                        networkPanel
                        privacyPanel
                    }
                } else {
                    privacyPanel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                launchItemsPanel

                if let error = model.lastErrorMessage {
                    statusBanner(text: error, icon: "exclamationmark.triangle.fill", color: Theme.Colors.warning)
                } else if let message = model.statusMessage {
                    statusBanner(text: message, icon: "checkmark.circle.fill", color: Theme.Colors.success)
                }
            }
            .padding(Theme.Spacing.xl)
        }
        .task {
            model.refreshIfNeeded()
        }
    }

    private var diagnosticSummary: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: Theme.Spacing.md),
                count: includesNetwork ? 4 : 2
            ),
            spacing: Theme.Spacing.md
        ) {
            if includesNetwork {
                summaryTile(
                    title: localizer.t("出口 IP", en: "Public IP"),
                    value: model.snapshot.primaryPublicIP?.displayValue ?? localizer.t("等待", en: "Waiting"),
                    detail: model.snapshot.primaryPublicIP?.subtitle ?? localizer.t("刷新后显示", en: "Shown after refresh"),
                    icon: "globe",
                    color: Theme.Colors.info
                )
                summaryTile(
                    title: localizer.t("本地地址", en: "Local IPs"),
                    value: "\(model.snapshot.localAddresses.count)",
                    detail: model.snapshot.localAddresses.first?.displayValue ?? localizer.t("未读取", en: "Not read"),
                    icon: "network",
                    color: Theme.Colors.teal
                )
                summaryTile(
                    title: localizer.t("连通性", en: "Reachability"),
                    value: "\(model.snapshot.reachableCount)/\(max(model.snapshot.connectivity.count, 1))",
                    detail: localizer.t("关键端点", en: "Key endpoints"),
                    icon: "point.3.connected.trianglepath.dotted",
                    color: model.snapshot.hasConnectivityWarning ? Theme.Colors.warning : Theme.Colors.success
                )
            }
            summaryTile(
                title: localizer.t("启动项", en: "Launch Items"),
                value: "\(model.snapshot.launchItems.count)",
                detail: model.snapshot.launchRiskSummary(localizer),
                icon: "bolt.badge.clock",
                color: model.snapshot.hasLaunchWarnings ? Theme.Colors.warning : Theme.Colors.purple
            )
            if !includesNetwork {
                summaryTile(
                    title: localizer.t("网络工具", en: "Network Tools"),
                    value: localizer.t("已迁移", en: "Moved"),
                    detail: localizer.t("使用 IP 概览插件", en: "Use the IP Overview plugin"),
                    icon: "puzzlepiece.extension.fill",
                    color: Theme.Colors.info
                )
            }
        }
    }

    private func summaryTile(title: String, value: String, detail: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 28, height: 28)
                    .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                Spacer()
            }
            Text(value)
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(title)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text(detail)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .cardStyle(padding: Theme.Spacing.md)
    }

    private var networkPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: localizer.t("出口与连通性", en: "Egress and Reachability"), icon: "antenna.radiowaves.left.and.right")

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(model.snapshot.publicEndpoints) { endpoint in
                    endpointRow(endpoint)
                }
            }

            Divider().overlay(Theme.Colors.separator.opacity(0.7))

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(model.snapshot.connectivity) { target in
                    connectivityRow(target)
                }
            }

            if !model.snapshot.localAddresses.isEmpty {
                Divider().overlay(Theme.Colors.separator.opacity(0.7))
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Text(localizer.t("本机网卡", en: "Local Interfaces"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    ForEach(model.snapshot.localAddresses.prefix(8)) { address in
                        HStack(spacing: Theme.Spacing.sm) {
                            Text(address.interface)
                                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 58, alignment: .leading)
                            Text(address.displayValue)
                                .font(.system(size: 11, weight: .regular, design: .monospaced))
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .lineLimit(1)
                            Spacer(minLength: 0)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .cardStyle(padding: Theme.Spacing.lg)
    }

    private func endpointRow(_ endpoint: PublicEndpointResult) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            diagnosticStatusIcon(endpoint.statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(endpoint.title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(endpoint.subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer(minLength: Theme.Spacing.sm)
            Text(endpoint.displayValue)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private func connectivityRow(_ target: ConnectivityResult) -> some View {
        HStack(spacing: Theme.Spacing.md) {
            diagnosticStatusIcon(target.statusColor)
            VStack(alignment: .leading, spacing: 2) {
                Text(target.name)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(target.detail)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
            }
            Spacer()
            Text(target.latencyText(localizer))
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(target.statusColor)
        }
        .padding(.vertical, Theme.Spacing.xs)
    }

    private var privacyPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader(title: localizer.t("本机动作", en: "Local Actions"), icon: "hand.raised.fill")

            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Image(systemName: "doc.on.clipboard")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Theme.Colors.accent)
                    .frame(width: 34, height: 34)
                    .background(Theme.Colors.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t("清空剪贴板", en: "Clear Clipboard"))
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t("只清空当前系统剪贴板，不读取剪贴板历史。", en: "Clears the current pasteboard without reading clipboard history."))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                model.clearClipboard(localizer)
            } label: {
                Label(localizer.t("立即清空", en: "Clear Now"), systemImage: "xmark.bin.fill")
                    .font(Theme.Font.captionMedium)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Divider().overlay(Theme.Colors.separator.opacity(0.7))

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text(localizer.t("上架版边界", en: "App Store Boundary"))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                boundaryLine(localizer.t("只做只读巡检和明确按钮动作。", en: "Read-only checks and explicit user actions only."))
                boundaryLine(localizer.t("不安装 helper，不调用 sudo，不修改启动项。", en: "No helper installs, sudo, or launch item mutation."))
                boundaryLine(localizer.t("官网版可单独开启高级维护。", en: "Direct builds can enable advanced maintenance separately."))
            }
        }
        .frame(width: 320, alignment: .topLeading)
        .cardStyle(padding: Theme.Spacing.lg)
    }

    private func boundaryLine(_ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.xs) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.success)
                .padding(.top, 1)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var launchItemsPanel: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.md) {
                SectionHeader(title: localizer.t("启动项只读巡检", en: "Launch Item Audit"), icon: "bolt.badge.clock")
                Spacer()
                Text(localizer.t("不修改 launchctl 状态", en: "No launchctl changes"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
            }

            if model.snapshot.launchItems.isEmpty {
                emptyLaunchState
            } else {
                LazyVStack(spacing: Theme.Spacing.sm) {
                    ForEach(model.snapshot.launchItems.prefix(18)) { item in
                        launchItemRow(item)
                    }
                    if model.snapshot.launchItems.count > 18 {
                        Text(localizer.t("还有 \(model.snapshot.launchItems.count - 18) 个启动项已收起。", en: "\(model.snapshot.launchItems.count - 18) more launch items are collapsed."))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Theme.Spacing.xs)
                    }
                }
            }
        }
        .cardStyle(padding: Theme.Spacing.lg)
    }

    private var emptyLaunchState: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            diagnosticStatusIcon(Theme.Colors.textTertiary)
            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.t("未读取到启动项", en: "No launch items read"))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(localizer.t("上架包可能需要用户授权相关目录后才能看到更多项目。", en: "The App Store build may need folder authorization to see more entries."))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.sidebarBg.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func launchItemRow(_ item: LaunchAuditItem) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            diagnosticStatusIcon(item.risk.color)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(item.label)
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(item.scopeLabel(localizer))
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(item.risk.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(item.risk.color.opacity(0.10), in: Capsule())
                    Spacer(minLength: 0)
                }
                Text(item.commandLine)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(1)
                Text(item.path)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 4) {
                Text(item.risk.label(localizer))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(item.risk.color)
                if item.runAtLoad {
                    Text(localizer.t("登录加载", en: "Run at load"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .background(Theme.Colors.sidebarBg.opacity(0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func diagnosticStatusIcon(_ color: Color) -> some View {
        Circle()
            .fill(color.opacity(0.14))
            .frame(width: 24, height: 24)
            .overlay {
                Circle()
                    .fill(color)
                    .frame(width: 8, height: 8)
            }
    }

    private func statusBanner(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Font.captionMedium)
            Text(text)
                .font(Theme.Font.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(color)
        .padding(Theme.Spacing.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }
}

@MainActor
private final class LocalSystemDiagnosticsModel: ObservableObject {
    @Published private(set) var snapshot = LocalDiagnosticsSnapshot()
    @Published private(set) var isRefreshing = false
    @Published private(set) var statusMessage: String?
    @Published private(set) var lastErrorMessage: String?

    private var hasLoaded = false
    private let includesNetwork: Bool

    init(includesNetwork: Bool = true) {
        self.includesNetwork = includesNetwork
    }

    func refreshIfNeeded() {
        guard !hasLoaded else { return }
        refresh()
    }

    func refresh() {
        guard !isRefreshing else { return }
        hasLoaded = true
        isRefreshing = true
        statusMessage = nil
        lastErrorMessage = nil

        Task {
            await performRefresh()
        }
    }

    func clearClipboard(_ localizer: Localizer) {
        NSPasteboard.general.clearContents()
        statusMessage = localizer.t("剪贴板已清空。", en: "Clipboard cleared.")
        lastErrorMessage = nil
    }

    private func performRefresh() async {
        async let launchItems = Task.detached(priority: .utility) {
            Self.scanLaunchItems()
        }.value
        if includesNetwork {
            async let localAddresses = Task.detached(priority: .utility) {
                Self.collectLocalAddresses()
            }.value
            async let primaryIP = fetchPublicEndpoint(
                id: "primary-egress",
                title: "Global egress",
                url: URL(string: "https://api.ipify.org?format=json")
            )
            async let secondaryIP = fetchPublicEndpoint(
                id: "secondary-egress",
                title: "Backup egress",
                url: URL(string: "https://ifconfig.me/ip")
            )
            async let connectivity = runConnectivityChecks()
            snapshot = await LocalDiagnosticsSnapshot(
                publicEndpoints: [primaryIP, secondaryIP],
                localAddresses: localAddresses,
                connectivity: connectivity,
                launchItems: launchItems,
                refreshedAt: Date()
            )
        } else {
            // Website builds delegate all public-IP, interface, reachability,
            // leak and quality checks to the independently updated IP Overview
            // plugin. Do not start a second network scanner here.
            snapshot = await LocalDiagnosticsSnapshot(
                launchItems: launchItems,
                refreshedAt: Date()
            )
        }
        isRefreshing = false
        statusMessage = "Local diagnostics refreshed."
    }

    private func fetchPublicEndpoint(id: String, title: String, url: URL?) async -> PublicEndpointResult {
        guard let url else {
            return PublicEndpointResult(id: id, title: title, value: nil, error: "Invalid URL", latencyMS: nil)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.setValue("TraceFence Local Diagnostics", forHTTPHeaderField: "User-Agent")

        let started = Date()
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let latency = max(1, Int(Date().timeIntervalSince(started) * 1000))
            guard let http = response as? HTTPURLResponse, (200..<500).contains(http.statusCode) else {
                return PublicEndpointResult(id: id, title: title, value: nil, error: "No response", latencyMS: latency)
            }
            let value = Self.publicIPValue(from: data)
            return PublicEndpointResult(id: id, title: title, value: value, error: value == nil ? "No IP in response" : nil, latencyMS: latency)
        } catch {
            return PublicEndpointResult(id: id, title: title, value: nil, error: error.localizedDescription, latencyMS: nil)
        }
    }

    private func runConnectivityChecks() async -> [ConnectivityResult] {
        let targets = [
            ConnectivityTarget(id: "apple", name: "Apple", url: URL(string: "https://www.apple.com/library/test/success.html")),
            ConnectivityTarget(id: "github", name: "GitHub", url: URL(string: "https://github.com")),
            ConnectivityTarget(id: "openai", name: "OpenAI API", url: URL(string: "https://api.openai.com")),
            ConnectivityTarget(id: "baidu", name: "Baidu", url: URL(string: "https://www.baidu.com"))
        ]

        return await withTaskGroup(of: ConnectivityResult.self, returning: [ConnectivityResult].self) { group in
            for target in targets {
                group.addTask {
                    await Self.checkConnectivity(target)
                }
            }

            var results: [ConnectivityResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { $0.id < $1.id }
        }
    }

    private nonisolated static func checkConnectivity(_ target: ConnectivityTarget) async -> ConnectivityResult {
        guard let url = target.url else {
            return ConnectivityResult(id: target.id, name: target.name, reachable: false, latencyMS: nil, detail: "Invalid URL")
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        request.httpMethod = "GET"
        request.setValue("TraceFence Local Diagnostics", forHTTPHeaderField: "User-Agent")

        let started = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let latency = max(1, Int(Date().timeIntervalSince(started) * 1000))
            guard let http = response as? HTTPURLResponse else {
                return ConnectivityResult(id: target.id, name: target.name, reachable: false, latencyMS: latency, detail: "No HTTP response")
            }
            return ConnectivityResult(
                id: target.id,
                name: target.name,
                reachable: (200..<500).contains(http.statusCode),
                latencyMS: latency,
                detail: "HTTP \(http.statusCode)"
            )
        } catch {
            return ConnectivityResult(id: target.id, name: target.name, reachable: false, latencyMS: nil, detail: error.localizedDescription)
        }
    }

    private nonisolated static func collectLocalAddresses() -> [LocalNetworkAddress] {
        var addresses: [LocalNetworkAddress] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let addr = ptr.pointee.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard !name.hasPrefix("lo") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let length = socklen_t(addr.pointee.sa_len)
            let result = getnameinfo(
                addr,
                length,
                &host,
                socklen_t(host.count),
                nil,
                0,
                NI_NUMERICHOST
            )
            guard result == 0 else { continue }

            let value = String(cString: host)
            guard !value.isEmpty, !value.hasPrefix("fe80") else { continue }
            addresses.append(LocalNetworkAddress(interface: name, address: value, family: family == AF_INET ? "IPv4" : "IPv6"))
        }

        return Array(
            Dictionary(grouping: addresses, by: { "\($0.interface)-\($0.address)" })
                .compactMap { $0.value.first }
                .sorted { lhs, rhs in
                    if lhs.interface == rhs.interface { return lhs.address < rhs.address }
                    return lhs.interface < rhs.interface
                }
        )
    }

    private nonisolated static func scanLaunchItems() -> [LaunchAuditItem] {
        let home = SandboxPaths.realHomeDirectory
        let roots: [(LaunchAuditScope, URL)] = [
            (.user, URL(fileURLWithPath: home).appendingPathComponent("Library/LaunchAgents", isDirectory: true)),
            (.sharedAgent, URL(fileURLWithPath: "/Library/LaunchAgents", isDirectory: true)),
            (.sharedDaemon, URL(fileURLWithPath: "/Library/LaunchDaemons", isDirectory: true))
        ]

        var items: [LaunchAuditItem] = []
        for (scope, root) in roots {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            ) else {
                continue
            }

            for case let url as URL in enumerator where url.pathExtension == "plist" {
                guard let item = launchItem(from: url, scope: scope) else { continue }
                items.append(item)
            }
        }

        return items.sorted { lhs, rhs in
            if lhs.risk.sortRank == rhs.risk.sortRank { return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending }
            return lhs.risk.sortRank > rhs.risk.sortRank
        }
    }

    private nonisolated static func launchItem(from url: URL, scope: LaunchAuditScope) -> LaunchAuditItem? {
        guard let data = try? Data(contentsOf: url),
              let object = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil),
              let plist = object as? [String: Any] else {
            return nil
        }

        let label = stringValue(plist["Label"]) ?? url.deletingPathExtension().lastPathComponent
        let program = stringValue(plist["Program"])
        let arguments = (plist["ProgramArguments"] as? [Any])?.compactMap(stringValue) ?? []
        let runAtLoad = plist["RunAtLoad"] as? Bool ?? false
        let disabled = plist["Disabled"] as? Bool ?? false
        let keepAlive = plist["KeepAlive"] != nil
        let command = program ?? arguments.first ?? "No executable"
        let risk = LaunchAuditRisk(scope: scope, command: command, runAtLoad: runAtLoad, keepAlive: keepAlive, disabled: disabled)

        return LaunchAuditItem(
            label: label,
            command: command,
            arguments: arguments,
            path: url.path,
            scope: scope,
            runAtLoad: runAtLoad,
            keepAlive: keepAlive,
            disabled: disabled,
            risk: risk
        )
    }

    private nonisolated static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String: return string
        case let number as NSNumber: return number.stringValue
        default: return nil
        }
    }

    private nonisolated static func publicIPValue(from data: Data) -> String? {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let ip = object["ip"] as? String {
            return ip.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let raw = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .first
            .map(String.init)
        return raw?.isEmpty == false ? raw : nil
    }
}

private struct LocalDiagnosticsSnapshot: Sendable {
    var publicEndpoints: [PublicEndpointResult] = []
    var localAddresses: [LocalNetworkAddress] = []
    var connectivity: [ConnectivityResult] = []
    var launchItems: [LaunchAuditItem] = []
    var refreshedAt: Date?

    var primaryPublicIP: PublicEndpointResult? {
        publicEndpoints.first(where: { $0.value != nil }) ?? publicEndpoints.first
    }

    var reachableCount: Int {
        connectivity.filter(\.reachable).count
    }

    var hasConnectivityWarning: Bool {
        !connectivity.isEmpty && reachableCount < connectivity.count
    }

    var hasLaunchWarnings: Bool {
        launchItems.contains { $0.risk == .review || $0.risk == .privileged }
    }

    func launchRiskSummary(_ localizer: Localizer) -> String {
        let flagged = launchItems.filter { $0.risk == .review || $0.risk == .privileged }.count
        guard flagged > 0 else {
            return localizer.t("只读巡检", en: "Read-only audit")
        }
        return localizer.t("\(flagged) 个需关注", en: "\(flagged) need review")
    }
}

private struct PublicEndpointResult: Identifiable, Sendable {
    let id: String
    let title: String
    let value: String?
    let error: String?
    let latencyMS: Int?

    var displayValue: String {
        value ?? "Unavailable"
    }

    var subtitle: String {
        if let latencyMS {
            return error ?? "\(latencyMS) ms"
        }
        return error ?? "Waiting"
    }

    var statusColor: Color {
        value == nil ? Theme.Colors.warning : Theme.Colors.success
    }
}

private struct ConnectivityTarget: Sendable {
    let id: String
    let name: String
    let url: URL?
}

private struct ConnectivityResult: Identifiable, Sendable {
    let id: String
    let name: String
    let reachable: Bool
    let latencyMS: Int?
    let detail: String

    var statusColor: Color {
        reachable ? Theme.Colors.success : Theme.Colors.warning
    }

    func latencyText(_ localizer: Localizer) -> String {
        guard reachable else { return localizer.t("失败", en: "Fail") }
        guard let latencyMS else { return localizer.t("可达", en: "OK") }
        return "\(latencyMS) ms"
    }
}

private struct LocalNetworkAddress: Identifiable, Sendable {
    var id: String { "\(interface)-\(address)" }
    let interface: String
    let address: String
    let family: String

    var displayValue: String {
        "\(address) \(family)"
    }
}

private enum LaunchAuditScope: String, Sendable {
    case user
    case sharedAgent
    case sharedDaemon
}

private enum LaunchAuditRisk: Sendable {
    case normal
    case review
    case privileged

    init(scope: LaunchAuditScope, command: String, runAtLoad: Bool, keepAlive: Bool, disabled: Bool) {
        if disabled {
            self = .normal
        } else if scope == .sharedDaemon {
            self = .privileged
        } else if keepAlive || runAtLoad || command.hasPrefix("/Library/") || command.hasPrefix("/usr/local/") || command.hasPrefix("/opt/homebrew/") {
            self = .review
        } else {
            self = .normal
        }
    }

    var color: Color {
        switch self {
        case .normal: Theme.Colors.success
        case .review: Theme.Colors.warning
        case .privileged: Theme.Colors.danger
        }
    }

    var sortRank: Int {
        switch self {
        case .normal: 0
        case .review: 1
        case .privileged: 2
        }
    }

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .normal: localizer.t("正常", en: "Normal")
        case .review: localizer.t("关注", en: "Review")
        case .privileged: localizer.t("特权", en: "Privileged")
        }
    }
}

private struct LaunchAuditItem: Identifiable, Sendable {
    var id: String { path }
    let label: String
    let command: String
    let arguments: [String]
    let path: String
    let scope: LaunchAuditScope
    let runAtLoad: Bool
    let keepAlive: Bool
    let disabled: Bool
    let risk: LaunchAuditRisk

    var commandLine: String {
        if arguments.count > 1 {
            return arguments.prefix(4).joined(separator: " ")
        }
        return command
    }

    func scopeLabel(_ localizer: Localizer) -> String {
        switch scope {
        case .user: return localizer.t("用户", en: "User")
        case .sharedAgent: return localizer.t("共享", en: "Shared")
        case .sharedDaemon: return localizer.t("守护", en: "Daemon")
        }
    }
}
