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
                                    isPreScanning = true
                                    await service.scanInstalledApps()
                                    isPreScanning = false
                                }
                                hasScanned = true
                                scanner.scanFromInstalledApps(service.installedApps)
                            }
                        } label: {
                            if isPreScanning {
                                HStack(spacing: 4) {
                                    ProgressView()
                                        .scaleEffect(0.6)
                                    Text(localizer.scanningAppList)
                                        .font(.caption)
                                }
                            } else {
                                Label(localizer.startScan, systemImage: "magnifyingglass")
                            }
                        }
                        .disabled(scanner.isScanning || isPreScanning)
                        .buttonStyle(.borderedProminent)
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
        HStack(spacing: 16) {
            StatBadge(icon: "cpu", label: localizer.needAdaptLabel, value: "\(scanner.intelOnlyCount)", color: Color.red)
            StatBadge(icon: "arrow.triangle.2.circlepath", label: localizer.universalBinLabel, value: "\(scanner.universalCount)", color: Color.blue)
            StatBadge(icon: "cpu", label: localizer.armNative, value: "\(scanner.armNativeCount)", color: Color.green)
            if scanner.intelOnlyCount > 0 {
                StatBadge(icon: "externaldrive", label: localizer.releasableSpace, value: scanner.totalIntelSizeFormatted, color: Color.orange)
            }
            Spacer()
            Text("\(localizer.scannedCount) \(scanner.totalScanned) \(localizer.itemsLabel)")
                .font(.caption)
                .foregroundColor(.secondary)
            Toggle(localizer.showIntelOnly, isOn: $showIntelOnly)
                .toggleStyle(.checkbox)
                .font(.caption)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private var filterBar: some View {
        HStack(spacing: 8) {
            FilterChip(label: localizer.all, isSelected: filterType == nil) { filterType = nil }
            ForEach(IntelAppInfo.IntelAppType.allCases, id: \.self) { type in
                FilterChip(label: type.rawValue, icon: type.icon, isSelected: filterType == type) {
                    filterType = type
                }
            }
            Divider().frame(height: 16)
            FilterChip(label: "Intel", icon: "cpu", isSelected: filterArch == .x86_64) { filterArch = filterArch == .x86_64 ? nil : .x86_64 }
            FilterChip(label: localizer.universalBinary, icon: "arrow.triangle.2.circlepath", isSelected: filterArch == .universal) { filterArch = filterArch == .universal ? nil : .universal }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField(localizer.searchingPlaceholder, text: $searchText)
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
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 48))
                .foregroundColor(.purple)
            Text(localizer.clickScanToDetect)
                .font(.title2)
                .fontWeight(.medium)
            Text("\(localizer.scanDesc1)\n\(localizer.scanDesc2)")
                .font(.subheadline)
                .foregroundColor(.secondary)
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
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.purple)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var scanningView: some View {
        VStack(spacing: 16) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            if isPreScanning {
                Text(localizer.scanningAppList)
                    .font(.headline)
                    .foregroundColor(.purple)
                Text(localizer.firstScanHint)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            } else {
                Text(localizer.detectingArch)
                    .font(.headline)
                    .foregroundColor(.purple)
                Text(scanner.scanProgress.isEmpty ? localizer.detectingArchWithLipo : scanner.scanProgress)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noIntelView: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundColor(.green)
            Text(localizer.allAdapted)
                .font(.title2)
                .fontWeight(.medium)
            Text(localizer.noIntelApps)
                .font(.subheadline)
                .foregroundColor(.secondary)
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
                    Text(item.appType.localizedLabel(localizer))
                        .font(.caption2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(item.appType.color.opacity(0.1))
                        .foregroundColor(item.appType.color)
                        .cornerRadius(4)
                    if item.architecture.isIntel {
                        Text(localizer.needAdapt)
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

                if item.replaceState == .uninstalling || item.replaceState == .installing {
                    ZStack {
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                            .frame(width: 22, height: 22)
                        Circle()
                            .trim(from: 0, to: item.replaceProgress)
                            .stroke(item.replaceState.color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                            .frame(width: 22, height: 22)
                            .rotationEffect(.degrees(-90))
                        Text("\(Int(item.replaceProgress * 100))")
                            .font(.system(size: 7))
                            .fontWeight(.bold)
                            .foregroundColor(item.replaceState.color)
                    }
                    Text(item.replaceState.label)
                        .font(.caption2)
                        .foregroundColor(item.replaceState.color)
                } else if item.replaceState == .completed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                } else if item.replaceState == .failed {
                    Image(systemName: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                } else if item.architecture.isIntel {
                    Button {
                        onReplace()
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.caption2)
                            Text(localizer.replaceBtn)
                                .font(.caption2)
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
                    .help(localizer.uninstallIntelAndInstallARM)

                    Button {
                        Task { await scanner.searchDownloadLink(for: item) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(localizer.searchARMDownload)
                }

                if item.architecture == .universal {
                    Button {
                        Task { await scanner.searchDownloadLink(for: item) }
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(localizer.searchPureARM)
                }

                if let url = item.downloadURL {
                    Button {
                        if let u = URL(string: url) { NSWorkspace.shared.open(u) }
                    } label: {
                        Image(systemName: "arrow.down.to.line")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                    .help(localizer.openDownloadLink + ": \(url)")
                }

                Button {
                    onUninstall()
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .foregroundColor(.red)
                .help(localizer.uninstallLabel)
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
