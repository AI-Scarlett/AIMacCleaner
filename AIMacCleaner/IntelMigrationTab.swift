import SwiftUI

struct IntelMigrationTab: View {
    @StateObject private var scanner = IntelMigrationScanner()
    @EnvironmentObject var localizer: Localizer
    @State private var searchText = ""
    @State private var filterType: IntelAppInfo.IntelAppType?
    @State private var showIntelOnly = true
    @State private var selectedAppId: String?
    @State private var showUninstallConfirm = false
    @State private var pendingUninstallApp: IntelAppInfo?

    var filteredApps: [IntelAppInfo] {
        var apps = scanner.intelApps
        if showIntelOnly {
            apps = apps.filter { $0.architecture.isIntel }
        }
        if let ft = filterType {
            apps = apps.filter { $0.appType == ft }
        }
        if !searchText.isEmpty {
            apps = apps.filter { $0.displayName.localizedCaseInsensitiveContains(searchText) }
        }
        return apps
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
                            scanner.scanAll()
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

            if scanner.intelApps.isEmpty && !scanner.isScanning {
                emptyView
            } else {
                appList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("确认卸载", isPresented: $showUninstallConfirm) {
            Button("取消", role: .cancel) {}
            Button("卸载", role: .destructive) {
                if let app = pendingUninstallApp {
                    _ = scanner.uninstallIntel(app: app)
                }
            }
        } message: {
            if let app = pendingUninstallApp {
                Text("确定要卸载「\(app.displayName)」吗？此操作不可撤销。")
            }
        }
    }

    private var statsBar: some View {
        HStack(spacing: 16) {
            StatBadge(
                icon: "cpu",
                label: "Intel 应用",
                value: "\(scanner.intelCount)",
                color: Color.red
            )
            StatBadge(
                icon: "arrow.triangle.2.circlepath",
                label: "通用二进制",
                value: "\(scanner.universalCount)",
                color: Color.blue
            )
            StatBadge(
                icon: "cpu",
                label: "ARM 原生",
                value: "\(scanner.armCount)",
                color: Color.green
            )
            if scanner.intelCount > 0 {
                StatBadge(
                    icon: "externaldrive",
                    label: "可释放空间",
                    value: scanner.totalIntelSizeFormatted,
                    color: Color.orange
                )
            }
            Spacer()
            Toggle("仅显示 Intel", isOn: $showIntelOnly)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(label: "全部", isSelected: filterType == nil) {
                filterType = nil
            }
            ForEach(IntelAppInfo.IntelAppType.allCases, id: \.self) { type in
                FilterChip(
                    label: type.rawValue,
                    icon: type.icon,
                    isSelected: filterType == type
                ) {
                    filterType = type
                }
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("搜索应用...", text: $searchText)
                    .textFieldStyle(.plain)
                    .frame(width: 150)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color(nsColor: .textBackgroundColor))
            .cornerRadius(6)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    private var appList: some View {
        List(selection: $selectedAppId) {
            ForEach(filteredApps) { app in
                IntelAppRow(app: app, scanner: scanner)
                    .tag(app.id)
                    .contextMenu {
                        Button("搜索 ARM 版本") {
                            Task { await scanner.searchDownloadLink(for: app) }
                        }
                        Button("卸载 Intel 版本", role: .destructive) {
                            pendingUninstallApp = app
                            showUninstallConfirm = true
                        }
                        if app.appType == .homebrew {
                            Button("重新安装 ARM 版本") {
                                _ = scanner.reinstallWithARM(app: app)
                            }
                        }
                        Divider()
                        Button("在 Finder 中显示") {
                            NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "")
                        }
                    }
            }
        }
        .listStyle(.inset)
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text("未发现 Intel 应用")
                .font(.title2)
                .fontWeight(.medium)
            Text("您的 Mac 上所有应用均已原生支持 Apple Silicon")
                .font(.subheadline)
                .foregroundColor(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IntelAppRow: View {
    let app: IntelAppInfo
    @ObservedObject var scanner: IntelMigrationScanner

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: app.appType.icon)
                .font(.title3)
                .foregroundColor(app.appType.color)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.displayName)
                        .fontWeight(.medium)
                    Text(app.architecture.badge)
                        .font(.caption2)
                        .fontWeight(.bold)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(app.architecture.color.opacity(0.15))
                        .foregroundColor(app.architecture.color)
                        .cornerRadius(4)
                    Text(app.appType.rawValue)
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(app.appType.color.opacity(0.1))
                        .foregroundColor(app.appType.color)
                        .cornerRadius(4)
                }
                Text(app.path)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(app.sizeFormatted)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 70, alignment: .trailing)

            if app.version != nil {
                Text("v\(app.version!)")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .frame(width: 50, alignment: .trailing)
            }

            HStack(spacing: 6) {
                if app.isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20)
                }

                if app.architecture.isIntel {
                    Button {
                        Task { await scanner.searchDownloadLink(for: app) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("搜索 ARM 版本")

                    if app.appType == .homebrew {
                        Button {
                            _ = scanner.reinstallWithARM(app: app)
                        } label: {
                            Image(systemName: "arrow.down.circle")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .help("重新安装 ARM 版本")
                    }

                    Button {
                        scanner.uninstallIntel(app: app)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .foregroundColor(.red)
                    .help("卸载 Intel 版本")
                }

                if let url = app.downloadURL {
                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help("打开下载链接")
                }
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
