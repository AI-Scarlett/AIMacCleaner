import AppKit
import SwiftUI
import UniformTypeIdentifiers
import MacToolsPluginKit

struct NetworkTrafficDashboardView: View {
    private enum Page: String, CaseIterable, Identifiable {
        case overview
        case connections
        case alerts

        var id: String { rawValue }
    }

    @ObservedObject var viewModel: NetworkTrafficViewModel
    let localization: PluginLocalization
    @State private var page: Page = .overview
    @State private var operationMessage: String?
    @State private var operationIsError = false

    var body: some View {
        ScrollView(.vertical, showsIndicators: true) {
            VStack(alignment: .leading, spacing: 16) {
                captureControls
                statusBanner
                metricGrid
                trafficChart
                pagePicker

                switch page {
                case .overview:
                    overviewPage
                case .connections:
                    connectionsPage
                case .alerts:
                    alertsPage
                }
            }
            .padding(.bottom, 18)
        }
        .onAppear { viewModel.refreshInterfaces() }
    }

    private var captureControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(localization.string("capture.mode", defaultValue: "采集模式"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: captureModeBinding) {
                        Text(localization.string("capture.mode.safe", defaultValue: "安全连接"))
                            .tag(NetworkTrafficCaptureMode.safeSockets)
                        Text(localization.string("capture.mode.raw", defaultValue: "原始抓包"))
                            .tag(NetworkTrafficCaptureMode.rawPackets)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 230)
                    .disabled(viewModel.captureState.isActive)
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(localization.string("capture.interface", defaultValue: "网卡"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Picker("", selection: interfaceBinding) {
                        if viewModel.captureMode == .safeSockets {
                            Text(localization.string("capture.interface.all", defaultValue: "全部网卡"))
                                .tag(NetworkTrafficViewModel.allInterfacesID)
                        }
                        ForEach(viewModel.interfaces) { item in
                            Text(interfaceLabel(item)).tag(item.id)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 190)
                    .disabled(viewModel.captureState.isActive)
                }

                if viewModel.captureState.isActive {
                    Button(role: .destructive) { viewModel.stopCapture() } label: {
                        Label(localization.string("capture.stop", defaultValue: "停止"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button { viewModel.startCapture() } label: {
                        Label(localization.string("capture.start", defaultValue: "开始监控"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button { viewModel.refreshInterfaces() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .help(localization.string("capture.refreshInterfaces", defaultValue: "刷新网卡"))

                Spacer(minLength: 0)
            }

            if viewModel.captureMode == .rawPackets {
                HStack(spacing: 10) {
                    Text("BPF")
                        .font(.caption.monospaced().weight(.semibold))
                        .foregroundStyle(.secondary)
                    TextField(
                        localization.string("capture.bpf.placeholder", defaultValue: "例如：tcp or udp port 53"),
                        text: bpfBinding
                    )
                    .textFieldStyle(.roundedBorder)
                    .disabled(viewModel.captureState.isActive)
                    Text(localization.string("capture.raw.warning", defaultValue: "需要系统 BPF 读取权限；失败时不会自动提权"))
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }

            Divider()

            HStack(spacing: 10) {
                Button(action: choosePCAPForImport) {
                    Label(localization.string("action.importPCAP", defaultValue: "导入 PCAP"), systemImage: "square.and.arrow.down")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.captureState.isActive)

                Button(action: choosePCAPForExport) {
                    Label(localization.string("action.exportPCAP", defaultValue: "导出 PCAP"), systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .disabled(!viewModel.canExportPCAP || viewModel.captureState.isActive)

                Button(action: chooseBlacklist) {
                    Label(localization.string("action.blacklist", defaultValue: "导入 IP 黑名单"), systemImage: "exclamationmark.shield")
                }
                .buttonStyle(.bordered)

                if viewModel.blacklistCount > 0 {
                    Button(role: .destructive) { viewModel.clearBlacklist() } label: {
                        Text(localization.string("action.clearBlacklist", defaultValue: "清空黑名单"))
                    }
                    .buttonStyle(.bordered)
                }

                Toggle(
                    localization.string("action.alertSound", defaultValue: "命中时提示音"),
                    isOn: Binding(
                        get: { viewModel.alertSoundEnabled },
                        set: { viewModel.setAlertSoundEnabled($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)

                Spacer(minLength: 0)

                Button(role: .destructive) { viewModel.clearTraffic() } label: {
                    Label(localization.string("action.clear", defaultValue: "清空记录"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    @ViewBuilder
    private var statusBanner: some View {
        if let error = viewModel.lastError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(error)
                    .font(.callout)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        } else if viewModel.rawFramesWereTruncated {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(.orange)
                Text(localization.string(
                    "capture.truncated",
                    defaultValue: "原始帧已达到 10,000 个或 32 MiB 上限；列表与导出的 PCAP 只包含当前保留的数据。"
                ))
                .font(.callout)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        } else if let operationMessage {
            HStack(spacing: 10) {
                Image(systemName: operationIsError ? "xmark.circle.fill" : "checkmark.circle.fill")
                    .foregroundStyle(operationIsError ? .red : .green)
                Text(operationMessage).font(.callout)
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                (operationIsError ? Color.red : Color.green).opacity(0.10),
                in: RoundedRectangle(cornerRadius: 10)
            )
        }
    }

    private var metricGrid: some View {
        HStack(spacing: 12) {
            metricCard(
                title: localization.string("metric.download", defaultValue: "实时下载"),
                value: NetworkTrafficFormatter.speed(viewModel.currentReceivedRate),
                footnote: "Σ \(NetworkTrafficFormatter.bytes(viewModel.totalReceivedBytes))",
                icon: "arrow.down",
                color: .blue
            )
            metricCard(
                title: localization.string("metric.upload", defaultValue: "实时上传"),
                value: NetworkTrafficFormatter.speed(viewModel.currentSentRate),
                footnote: "Σ \(NetworkTrafficFormatter.bytes(viewModel.totalSentBytes))",
                icon: "arrow.up",
                color: .purple
            )
            metricCard(
                title: localization.string("metric.connections", defaultValue: "连接"),
                value: "\(viewModel.connections.count)",
                footnote: "\(viewModel.totalPackets) packets",
                icon: "point.3.connected.trianglepath.dotted",
                color: .teal
            )
            metricCard(
                title: localization.string("metric.alerts", defaultValue: "风险提醒"),
                value: "\(viewModel.alerts.count)",
                footnote: "\(viewModel.blacklistCount) blacklist IPs",
                icon: "exclamationmark.shield",
                color: viewModel.alerts.isEmpty ? .green : .orange
            )
        }
    }

    private var trafficChart: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(localization.string("chart.title", defaultValue: "最近 120 秒流量"), systemImage: "waveform.path.ecg")
                    .font(.headline)
                Spacer()
                legend(color: .blue, text: localization.string("chart.download", defaultValue: "下载"))
                legend(color: .purple, text: localization.string("chart.upload", defaultValue: "上传"))
            }
            NetworkTrafficRateChart(points: viewModel.history)
                .frame(height: 150)
        }
        .padding(14)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private var pagePicker: some View {
        Picker("", selection: $page) {
            Text(localization.string("page.overview", defaultValue: "概览")).tag(Page.overview)
            Text(localization.string("page.connections", defaultValue: "连接明细")).tag(Page.connections)
            Text(localization.string("page.alerts", defaultValue: "提醒")).tag(Page.alerts)
        }
        .pickerStyle(.segmented)
        .frame(maxWidth: 440)
    }

    private var overviewPage: some View {
        HStack(alignment: .top, spacing: 12) {
            rankingCard(
                title: localization.string("overview.hosts", defaultValue: "流量最高的远程主机"),
                icon: "network",
                rows: viewModel.topHosts.map { ($0.host, NetworkTrafficFormatter.bytes($0.bytes), "\($0.connections) connections") }
            )
            rankingCard(
                title: localization.string("overview.processes", defaultValue: "流量最高的进程"),
                icon: "app.dashed",
                rows: viewModel.topProcesses.map { ($0.name, NetworkTrafficFormatter.bytes($0.bytes), "") }
            )
        }
    }

    private var connectionsPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(
                    localization.string("connections.search", defaultValue: "搜索主机、端口、进程、服务或网卡"),
                    text: $viewModel.searchText
                )
                .textFieldStyle(.roundedBorder)

                Picker("", selection: $viewModel.protocolFilter) {
                    ForEach(NetworkTrafficProtocol.allCases) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                .labelsHidden()
                .frame(width: 110)
            }

            VStack(spacing: 0) {
                connectionHeader
                Divider()
                if viewModel.filteredConnections.isEmpty {
                    Text(localization.string("connections.empty", defaultValue: "还没有符合条件的连接"))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(Array(viewModel.filteredConnections.prefix(200).enumerated()), id: \.element.id) { index, connection in
                        connectionRow(connection)
                        if index < min(viewModel.filteredConnections.count, 200) - 1 { Divider() }
                    }
                }
            }
            .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
        }
    }

    private var alertsPage: some View {
        VStack(spacing: 0) {
            if viewModel.alerts.isEmpty {
                ContentUnavailableView(
                    localization.string("alerts.empty.title", defaultValue: "暂无风险提醒"),
                    systemImage: "checkmark.shield",
                    description: Text(localization.string("alerts.empty.detail", defaultValue: "导入 IP 黑名单后，命中的连接会显示在这里。"))
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(viewModel.alerts) { alert in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "exclamationmark.shield.fill").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(alert.message).font(.callout.weight(.medium))
                            Text(alert.date.formatted(date: .abbreviated, time: .standard))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { viewModel.dismissAlert(alert.id) } label: {
                            Image(systemName: "xmark")
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    Divider()
                }
            }
        }
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private var connectionHeader: some View {
        HStack(spacing: 10) {
            Text("").frame(width: 24)
            Text(localization.string("column.protocol", defaultValue: "协议")).frame(width: 56, alignment: .leading)
            Text(localization.string("column.process", defaultValue: "进程")).frame(width: 120, alignment: .leading)
            Text(localization.string("column.remote", defaultValue: "远程主机")).frame(maxWidth: .infinity, alignment: .leading)
            Text(localization.string("column.service", defaultValue: "服务")).frame(width: 110, alignment: .leading)
            Text("↓").frame(width: 82, alignment: .trailing)
            Text("↑").frame(width: 82, alignment: .trailing)
            Text(localization.string("column.interface", defaultValue: "网卡")).frame(width: 72, alignment: .leading)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private func connectionRow(_ connection: NetworkTrafficConnection) -> some View {
        HStack(spacing: 10) {
            Button { viewModel.toggleFavorite(host: connection.remote.host) } label: {
                Image(systemName: connection.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(connection.isFavorite ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)
            .frame(width: 24)

            Text(connection.protocolKind.rawValue)
                .font(.caption.monospaced().weight(.semibold))
                .foregroundStyle(protocolColor(connection.protocolKind))
                .frame(width: 56, alignment: .leading)
            Text(connection.processName ?? "—")
                .lineLimit(1)
                .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(connection.remote.displayText).font(.system(.body, design: .monospaced))
                    if connection.isBlacklisted {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    }
                }
                Text(connection.state ?? connection.local.displayText)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(connection.serviceName ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(NetworkTrafficFormatter.bytes(connection.receivedBytes))
                .monospacedDigit()
                .frame(width: 82, alignment: .trailing)
            Text(NetworkTrafficFormatter.bytes(connection.sentBytes))
                .monospacedDigit()
                .frame(width: 82, alignment: .trailing)
            Text(connection.interfaceName ?? "—")
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(connection.isBlacklisted ? Color.orange.opacity(0.07) : .clear)
    }

    private func metricCard(
        title: String,
        value: String,
        footnote: String,
        icon: String,
        color: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(value)
                .font(.title2.weight(.semibold))
                .monospacedDigit()
                .lineLimit(1)
            Text(footnote)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(0.20)))
    }

    private func rankingCard(title: String, icon: String, rows: [(String, String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon).font(.headline)
            if rows.isEmpty {
                Text(localization.string("overview.empty", defaultValue: "暂无数据"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 110)
            } else {
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    HStack(spacing: 8) {
                        Text("\(index + 1)").font(.caption.monospaced()).foregroundStyle(.secondary).frame(width: 18)
                        Text(row.0).lineLimit(1)
                        Spacer()
                        if !row.2.isEmpty { Text(row.2).font(.caption2).foregroundStyle(.secondary) }
                        Text(row.1).monospacedDigit().foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    if index < rows.count - 1 { Divider() }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.quaternary))
    }

    private func legend(color: Color, text: String) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var cardBackground: Color { Color(nsColor: .controlBackgroundColor) }

    private var captureModeBinding: Binding<NetworkTrafficCaptureMode> {
        Binding(get: { viewModel.captureMode }, set: { viewModel.setCaptureMode($0) })
    }

    private var interfaceBinding: Binding<String> {
        Binding(get: { viewModel.selectedInterfaceID }, set: { viewModel.setSelectedInterface($0) })
    }

    private var bpfBinding: Binding<String> {
        Binding(get: { viewModel.bpfFilter }, set: { viewModel.setBPFFilter($0) })
    }

    private func interfaceLabel(_ item: NetworkTrafficInterface) -> String {
        let state = item.isUp ? "●" : "○"
        if let description = item.description, !description.isEmpty {
            return "\(state) \(item.name) — \(description)"
        }
        return "\(state) \(item.name)"
    }

    private func protocolColor(_ value: NetworkTrafficProtocol) -> Color {
        switch value {
        case .tcp: .blue
        case .udp: .purple
        case .icmp: .orange
        case .arp: .green
        case .all, .other: .secondary
        }
    }

    private func choosePCAPForImport() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.data]
        panel.message = localization.string("panel.importPCAP.message", defaultValue: "选择 .pcap、.pcapng 或 .cap 文件")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        operationMessage = nil
        operationIsError = false
        viewModel.importPCAP(from: url)
    }

    private func choosePCAPForExport() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "tracefence-network-traffic.pcap"
        panel.allowedContentTypes = [UTType(filenameExtension: "pcap") ?? .data]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try viewModel.exportPCAP(to: url)
            operationMessage = localization.string("export.success", defaultValue: "PCAP 已导出")
            operationIsError = false
        } catch {
            operationMessage = error.localizedDescription
            operationIsError = true
        }
    }

    private func chooseBlacklist() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.plainText, .text]
        panel.message = localization.string("panel.blacklist.message", defaultValue: "每行一个 IP；# 后内容作为注释")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            viewModel.importBlacklist(from: text)
            operationMessage = "已导入 \(viewModel.blacklistCount) 个黑名单 IP"
            operationIsError = false
        } catch {
            operationMessage = error.localizedDescription
            operationIsError = true
        }
    }
}

private struct NetworkTrafficRateChart: View {
    let points: [NetworkTrafficRatePoint]

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                guard points.count > 1 else {
                    let text = Text("Waiting for traffic…").font(.caption).foregroundColor(.secondary)
                    context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
                    return
                }

                let maximum = max(
                    1,
                    points.map { max($0.receivedBytesPerSecond, $0.sentBytesPerSecond) }.max() ?? 1
                )
                let xStep = size.width / CGFloat(max(1, points.count - 1))
                let downPath = path(values: points.map(\.receivedBytesPerSecond), maximum: maximum, xStep: xStep, size: size)
                let upPath = path(values: points.map(\.sentBytesPerSecond), maximum: maximum, xStep: xStep, size: size)
                context.stroke(downPath, with: .color(.blue), lineWidth: 2)
                context.stroke(upPath, with: .color(.purple), lineWidth: 2)
            }
            .background {
                VStack(spacing: 0) {
                    Divider()
                    Spacer()
                    Divider()
                    Spacer()
                    Divider()
                }
                .opacity(0.45)
            }
        }
    }

    private func path(values: [UInt64], maximum: UInt64, xStep: CGFloat, size: CGSize) -> Path {
        var path = Path()
        for (index, value) in values.enumerated() {
            let ratio = CGFloat(Double(value) / Double(maximum))
            let point = CGPoint(x: CGFloat(index) * xStep, y: size.height - ratio * max(1, size.height - 4) - 2)
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}
