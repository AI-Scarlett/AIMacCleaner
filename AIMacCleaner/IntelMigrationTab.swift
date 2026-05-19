import SwiftUI

struct IntelMigrationTab: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @StateObject private var scanner = IntelMigrationScanner()
    @State private var searchText = ""
    @State private var filterType: IntelAppInfo.IntelAppType?
    @State private var filterArch: IntelAppInfo.BinaryArchitecture?
    @State private var showIntelOnly = true
    @State private var selectedAppId: String?
    @State private var showUninstallConfirm = false
    @State private var pendingUninstallApp: IntelAppInfo?
    @State private var showReplaceConfirm = false
    @State private var pendingReplaceApp: IntelAppInfo?

    var filteredItems: [IntelAppInfo] {
        var items = scanner.items
        if showIntelOnly {
            items = items.filter { $0.architecture.isIntel || $0.architecture == .universal }
        }
        if let ft = filterType {
            items = items.filter { $0.appType == ft }
        }
        if let fa = filterArch {
            items = items.filter { $0.architecture == fa }
        }
        if !searchText.isEmpty {
            items = items.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
        return items.sorted { ($0.architecture.isIntel ? 0 : ($0.architecture == .universal ? 1 : 2)) < ($1.architecture.isIntel ? 0 : ($1.architecture == .universal ? 1 : 2)) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "arrow.triangle.2.circlepath",
                title: "芯片迁移",
                subtitle: "Intel → Apple Silicon",
                color: .purple,
                trailing: {
                    HStack(spacing: 8) {
                        if scanner.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(scanner.scanProgress)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Button {
                            Task {
                                if service.installedApps.isEmpty {
                                    await service.scanInstalledApps()
                                }
                                scanner.scanFromInstalledApps(service.installedApps)
                            }
                        } label: {
                            Label("扫描", systemImage: "magnifyingglass")
                        }
                        .disabled(scanner.isScanning)
                        .buttonStyle(.borderedProminent)
                    }
                }
            )

            statsBar

            filterBar

            if scanner.items.isEmpty && !scanner.isScanning {
                emptyView
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("确认卸载", isPresented: $showUninstallConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let app = pendingUninstallApp {
                    _ = scanner.uninstallOnly(item: app)
                }
            }
        } message: {
            if let app = pendingUninstallApp {
                Text("确定要卸载「\(app.displayName)」吗？此操作不可撤销。")
            }
        }
        .alert("替换为 ARM 版本", isPresented: $showReplaceConfirm) {
            Button("取消", role: .cancel) {}
            Button("替换", role: .destructive) {
                if let app = pendingReplaceApp {
                    _ = scanner.uninstallAndReplace(item: app)
                }
            }
        } message: {
            if let app = pendingReplaceApp {
                Text("将卸载「\(app.displayName)」的 Intel 版本，并尝试安装 ARM 原生版本。")
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            StatBadge(icon: "cpu", label: "需要迁移", value: "\(scanner.intelOnlyCount)", color: Color.red)
            StatBadge(icon: "arrow.triangle.2.circlepath", label: "通用二进制", value: "\(scanner.universalCount)", color: Color.blue)
            StatBadge(icon: "cpu", label: "ARM 原生", value: "\(scanner.armNativeCount)", color: Color.green)
            if scanner.intelOnlyCount > 0 {
                StatBadge(icon: "externaldrive", label: "可释放空间", value: scanner.totalIntelSizeFormatted, color: Color.orange)
            }
            Spacer()
            Text("已扫描 \(scanner.totalScanned) 项")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle("仅显示需迁移", isOn: $showIntelOnly)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(label: "全部", isSelected: filterType == nil) { filterType = nil }
            ForEach(IntelAppInfo.IntelAppType.allCases, id: \.self) { type in
                FilterChip(label: type.rawValue, icon: type.icon, isSelected: filterType == type) {
                    filterType = type
                }
            }
            Divider().frame(height: 16)
            FilterChip(label: "Intel", icon: "cpu", isSelected: filterArch == .x86_64) { filterArch = filterArch == .x86_64 ? nil : .x86_64 }
            FilterChip(label: "通用", icon: "arrow.triangle.2.circlepath", isSelected: filterArch == .universal) { filterArch = filterArch == .universal ? nil : .universal }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("搜索...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 120)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var itemList: some View {
        List(selection: $selectedAppId) {
            ForEach(filteredItems) { item in
                IntelAppRow(item: item, scanner: scanner, onReplace: {
                    pendingReplaceApp = item
                    showReplaceConfirm = true
                }, onUninstall: {
                    pendingUninstallApp = item
                    showUninstallConfirm = true
                })
                .tag(item.id)
            }
        }
        .listStyle(.inset)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            if service.installedApps.isEmpty {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 48))
                    .foregroundColor(.purple)
                Text("点击「扫描」开始检测")
                    .font(.title2)
                    .fontWeight(.medium)
                Text("将扫描所有已安装的APP、依赖和CLI工具的CPU架构")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("所有应用均已适配 Apple Silicon")
                    .font(.title2)
                    .fontWeight(.medium)
                Text("您的 Mac 上没有需要迁移的 Intel 应用")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IntelAppRow: View {
    let item: IntelAppInfo
    @ObservedObject var scanner: IntelMigrationScanner
    let onReplace: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: item.appType.icon)
                .font(.title3)
                .foregroundColor(item.appType.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.displayName)
                        .fontWeight(.medium)
                    Text(item.architecture.badge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(item.architecture.color.opacity(0.15))
                        .foregroundColor(item.architecture.color)
                        .cornerRadius(4)
                    Text(item.appType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(item.appType.color.opacity(0.1))
                        .foregroundColor(item.appType.color)
                        .cornerRadius(4)
                    if item.architecture.isIntel {
                        Text("需迁移")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.15))
                            .foregroundColor(.red)
                            .cornerRadius(4)
                    }
                }
                Text(item.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if let v = item.version, !v.isEmpty {
                Text("v\(v)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            HStack(spacing: 6) {
                if item.isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20)
                }

                if item.architecture.isIntel {
                    Button {
                        onReplace()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                            Text("替换")
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .help("卸载 Intel 版本并安装 ARM 版本")

                    Button {
                        Task { await scanner.searchDownloadLink(for: item) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("搜索 ARM 版本下载链接")
                }

                if item.architecture == .universal {
                    Button {
                        Task { await scanner.searchDownloadLink(for: item) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("搜索纯 ARM 版本")
                }

                if let url = item.downloadURL {
                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("打开下载链接: \(url)")
                }

                Button {
                    onUninstall()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .help("卸载")
            }
        }
        .padding(.vertical, 4)
    }
}

struct StatBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.caption)
                    .fontWeight(.semibold)
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(color.opacity(0.08))
        .cornerRadius(8)
    }
}

struct FilterChip: View {
    let label: String
    var icon: String? = nil
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(.caption2)
                }
                Text(label)
                    .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
            .foregroundColor(isSelected ? .accentColor : .secondary)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.accentColor.opacity(0.3) : Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
