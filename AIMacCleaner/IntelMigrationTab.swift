import SwiftUI

struct IntelMigrationTab: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @StateObject private var scanner = IntelMigrationScanner()
    @State private var searchText = ""
    @State private var filterType: IntelAppInfo.IntelAppType?
    @State private var filterArch: IntelAppInfo.BinaryArchitecture?
    @State private var showIntelOnly = true
    @State private var hasScanned = false
    @State private var isPreScanning = false
    @State private var selectedAppId: String?
    @State private var showUninstallConfirm = false
    @State private var pendingUninstallApp: IntelAppInfo?
    @State private var showReplaceConfirm = false
    @State private var pendingReplaceApp: IntelAppInfo?

    var filteredItems: [IntelAppInfo] {
        var items = scanner.items
        if showIntelOnly {
            items = items.filter { $0.architecture.isIntel }
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
                title: localizer.navMigration,
                subtitle: localizer.subMigration,
                color: .purple,
                trailing: {
                    HStack(spacing: Theme.Spacing.sm) {
                        if scanner.isScanning {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text(scanner.scanProgress)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Button {
                            Task {
                                if service.installedApps.isEmpty {
                                    isPreScanning = true
                                    await service.scanInstalledApps()
                                    isPreScanning = false
                                }
                                hasScanned = true
                                scanner.scanFromInstalledApps(service.installedApps)
                            }
                        } label: {
                            if isPreScanning {
                                HStack(spacing: Theme.Spacing.xs) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text(localizer.scanningAppList)
                                        .font(Theme.Font.caption)
                                }
                                .foregroundStyle(.white)
                                .padding(.horizontal, Theme.Spacing.md)
                                .padding(.vertical, Theme.Spacing.xs)
                                .background(Theme.Gradients.accent)
                                .clipShape(Capsule())
                            } else {
                                Label(localizer.startScan, systemImage: "magnifyingglass")
                                    .font(Theme.Font.captionMedium)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, Theme.Spacing.md)
                                    .padding(.vertical, Theme.Spacing.xs)
                                    .background(Theme.Gradients.accent)
                                    .clipShape(Capsule())
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(scanner.isScanning || isPreScanning)
                    }
                }
            )

            statsBar

            filterBar

            if !hasScanned && scanner.items.isEmpty && !scanner.isScanning && !isPreScanning {
                emptyView
            } else if (isPreScanning || scanner.isScanning) {
                scanningView
            } else if filteredItems.isEmpty && hasScanned {
                noIntelView
            } else {
                itemList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { scanner.localizer = localizer }
        .alert(localizer.confirmUninstall, isPresented: $showUninstallConfirm) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.uninstallBtn, role: .destructive) {
                if let app = pendingUninstallApp {
                    _ = scanner.uninstallOnly(item: app)
                }
            }
        } message: {
            if let app = pendingUninstallApp {
                Text("\(localizer.confirmUninstallMsg)「\(app.displayName)」？\(localizer.irreversibleMsg)")
            }
        }
        .alert(localizer.replaceARMVersion, isPresented: $showReplaceConfirm) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.replaceBtn, role: .destructive) {
                if let app = pendingReplaceApp {
                    _ = scanner.uninstallAndReplace(item: app)
                }
            }
        } message: {
            if let app = pendingReplaceApp {
                Text("\(localizer.willUninstallIntel)「\(app.displayName)」\(localizer.intelVersionMsg)")
            }
        }
    }

    private var statsBar: some View {
        VStack(spacing: Theme.Spacing.md) {
            DashboardGrid(columns: 4) {
                StatCardView(icon: "cpu", iconColor: Theme.Colors.danger, title: localizer.needAdaptLabel, value: "\(scanner.intelOnlyCount)", subtitle: nil)
                StatCardView(icon: "arrow.triangle.2.circlepath", iconColor: Theme.Colors.info, title: localizer.universalBinLabel, value: "\(scanner.universalCount)", subtitle: nil)
                StatCardView(icon: "cpu", iconColor: Theme.Colors.success, title: localizer.armNative, value: "\(scanner.armNativeCount)", subtitle: nil)
                StatCardView(icon: "externaldrive", iconColor: Theme.Colors.warning, title: localizer.releasableSpace, value: scanner.intelOnlyCount > 0 ? scanner.totalIntelSizeFormatted : "—", subtitle: nil)
            }
            HStack(spacing: Theme.Spacing.lg) {
                if scanner.totalScanned > 0 {
                    let progress = 1.0 - (scanner.totalScanned > 0 ? Double(scanner.intelOnlyCount) / Double(scanner.totalScanned) : 0)
                    ProgressRing(progress: progress, lineWidth: 4, size: 28, color: Theme.Colors.purple, showLabel: true)
                }
                Spacer()
                Text("\(localizer.scannedCount) \(scanner.totalScanned) \(localizer.itemsLabel)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Toggle(localizer.showIntelOnly, isOn: $showIntelOnly)
                    .toggleStyle(.checkbox)
                    .font(Theme.Font.caption)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.md)
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                filterPill(label: localizer.all, isSelected: filterType == nil) { filterType = nil }
                ForEach(IntelAppInfo.IntelAppType.allCases, id: \.self) { type in
                    filterPill(label: type.rawValue, icon: type.icon, isSelected: filterType == type) {
                        filterType = type
                    }
                }
                Rectangle()
                    .fill(Theme.Colors.separator)
                    .frame(width: 1, height: 16)
                filterPill(label: "Intel", icon: "cpu", isSelected: filterArch == .x86_64) { filterArch = filterArch == .x86_64 ? nil : .x86_64 }
                filterPill(label: localizer.universalBinary, icon: "arrow.triangle.2.circlepath", isSelected: filterArch == .universal) { filterArch = filterArch == .universal ? nil : .universal }
                Spacer(minLength: Theme.Spacing.md)
                HStack(spacing: Theme.Spacing.xs) {
                    Image(systemName: "magnifyingglass")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    TextField(localizer.searchingPlaceholder, text: $searchText)
                        .textFieldStyle(.plain)
                        .frame(width: 120)
                }
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.cardBg)
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.sm)
    }

    private func filterPill(label: String, icon: String? = nil, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if let ic = icon {
                    Image(systemName: ic)
                        .font(Theme.Font.caption)
                }
                Text(label)
                    .font(Theme.Font.captionMedium)
            }
            .foregroundStyle(isSelected ? Theme.Colors.accent : Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.sm)
            .padding(.vertical, Theme.Spacing.xs)
            .background(isSelected ? Theme.Colors.accent.opacity(0.12) : Color.clear)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(isSelected ? Theme.Colors.accent.opacity(0.3) : Theme.Colors.separator, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var itemList: some View {
        ScrollView {
            LazyVStack(spacing: Theme.Spacing.sm) {
                ForEach(filteredItems) { item in
                    IntelAppRow(item: item, scanner: scanner, onReplace: {
                        pendingReplaceApp = item
                        showReplaceConfirm = true
                    }, onUninstall: {
                        pendingUninstallApp = item
                        showUninstallConfirm = true
                    })
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.vertical, Theme.Spacing.sm)
        }
    }

    private var emptyView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.purple)
            Text(localizer.clickScanToDetect)
                .font(Theme.Font.title2)
                .fontWeight(.medium)
            Text("\(localizer.scanDesc1)\n\(localizer.scanDesc2)")
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button {
                Task {
                    if service.installedApps.isEmpty {
                        isPreScanning = true
                        await service.scanInstalledApps()
                        isPreScanning = false
                    }
                    hasScanned = true
                    scanner.scanFromInstalledApps(service.installedApps)
                }
            } label: {
                Label(localizer.startScan, systemImage: "magnifyingglass")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Gradients.accent)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            ZStack {
                Circle()
                    .stroke(Theme.Colors.purple.opacity(0.1), lineWidth: 6)
                    .frame(width: 80, height: 80)
                ProgressView()
                    .scaleEffect(1.2)
                    .tint(Theme.Colors.purple)
            }
            if isPreScanning {
                Text(localizer.scanningAppList)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.purple)
                Text(localizer.firstScanHint)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Text(localizer.detectingArch)
                    .font(Theme.Font.headline)
                    .foregroundStyle(Theme.Colors.purple)
                Text(scanner.scanProgress.isEmpty ? localizer.detectingArchWithLipo : scanner.scanProgress)
                    .font(Theme.Font.subheadline)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noIntelView: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.success)
            Text(localizer.allAdapted)
                .font(Theme.Font.title2)
                .fontWeight(.medium)
            Text(localizer.noIntelApps)
                .font(Theme.Font.subheadline)
                .foregroundStyle(Theme.Colors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct IntelAppRow: View {
    let item: IntelAppInfo
    @ObservedObject var scanner: IntelMigrationScanner
    @EnvironmentObject var localizer: Localizer
    let onReplace: () -> Void
    let onUninstall: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: item.appType.icon)
                .font(.title3)
                .foregroundStyle(item.appType.color)
                .frame(width: 32, height: 32)
                .background(item.appType.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Spacing.xs) {
                    Text(item.displayName)
                        .font(Theme.Font.bodyMedium)
                    PillBadge(text: item.architecture.badge, color: archBadgeColor)
                    PillBadge(text: item.appType.localizedLabel(localizer), color: item.appType.color)
                    if item.architecture.isIntel {
                        PillBadge(text: localizer.needAdapt, color: Theme.Colors.danger)
                    }
                }
                Text(item.path)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Text(item.sizeFormatted)
                .font(Theme.Font.captionMedium)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 70, alignment: .trailing)

            if let v = item.version, !v.isEmpty {
                Text("v\(v)")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .frame(width: 50, alignment: .trailing)
            }

            HStack(spacing: Theme.Spacing.xs) {
                if item.isSearching {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 20)
                }

                if item.replaceState == .uninstalling || item.replaceState == .installing {
                    ProgressRing(progress: item.replaceProgress, lineWidth: 2, size: 22, color: item.replaceState.color, bgColor: Color.gray.opacity(0.2), showLabel: false)
                    Text(item.replaceState.localizedLabel(localizer))
                        .font(Theme.Font.caption)
                        .foregroundStyle(item.replaceState.color)
                } else if item.replaceState == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.success)
                } else if item.replaceState == .failed {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.Colors.danger)
                } else if item.architecture.isIntel {
                    Button {
                        onReplace()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(Theme.Font.caption)
                            Text(localizer.replaceBtn)
                                .font(Theme.Font.caption)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.Colors.purple)
                    .help(localizer.uninstallIntelAndInstallARM)

                    Button {
                        Task { await scanner.searchDownloadLink(for: item) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(localizer.searchARMDownload)
                }

                if item.architecture == .universal {
                    Button {
                        Task { await scanner.searchDownloadLink(for: item) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(localizer.searchPureARM)
                }

                if let url = item.downloadURL {
                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(Theme.Font.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(localizer.openDownloadLink + ": \(url)")
                }

                Button {
                    onUninstall()
                } label: {
                    Image(systemName: "trash")
                        .font(Theme.Font.caption)
                }
                .buttonStyle(.bordered)
                .foregroundColor(Theme.Colors.danger)
                .help(localizer.uninstallLabel)
            }
        }
        .cardStyle(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.md)
    }

    private var archBadgeColor: Color {
        switch item.architecture {
        case .x86_64: return Theme.Colors.danger
        case .arm64: return Theme.Colors.success
        case .universal: return Theme.Colors.info
        case .rosetta: return Theme.Colors.warning
        case .unknown: return Theme.Colors.textTertiary
        @unknown default: return Theme.Colors.textTertiary
        }
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
