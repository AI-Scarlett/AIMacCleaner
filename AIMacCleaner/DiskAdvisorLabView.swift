import SwiftUI
import Foundation

enum DiskAdvisorRecommendation: String, Codable, CaseIterable, Sendable {
    case clean
    case review
    case keep

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .clean: return localizer.t("建议清理", en: "Clean")
        case .review: return localizer.t("需要确认", en: "Review")
        case .keep: return localizer.t("建议保留", en: "Keep")
        }
    }

    var color: Color {
        switch self {
        case .clean: return Theme.Colors.success
        case .review: return Theme.Colors.warning
        case .keep: return Theme.Colors.textSecondary
        }
    }
}

enum DiskAdvisorRisk: String, Codable, CaseIterable, Sendable {
    case safe
    case caution
    case danger
    case unknown

    func label(_ localizer: Localizer) -> String {
        switch self {
        case .safe: return localizer.riskSafe
        case .caution: return localizer.riskCaution
        case .danger: return localizer.riskDangerous
        case .unknown: return localizer.t("未知", en: "Unknown")
        }
    }

    var color: Color {
        switch self {
        case .safe: return Theme.Colors.success
        case .caution: return Theme.Colors.warning
        case .danger: return Theme.Colors.danger
        case .unknown: return Theme.Colors.textSecondary
        }
    }
}

struct DiskAdvisorCandidate: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let path: String
    let size: Int64
    let fileCount: Int
    let isDirectory: Bool
    let modifiedDate: Date?
    let category: String
    let localHint: String
    var recommendation: DiskAdvisorRecommendation
    var risk: DiskAdvisorRisk
    var reason: String
    var impact: String
    var confidence: Double
    var source: String
    var analyzedAt: Date?

    var displayPath: String {
        path.replacingOccurrences(of: SandboxPaths.realHomeDirectory, with: "~")
    }

    var isAISafeClean: Bool {
        recommendation == .clean && risk == .safe
    }
}

private struct DiskAdvisorLLMResult: Codable {
    let id: String
    let recommendation: DiskAdvisorRecommendation?
    let risk: DiskAdvisorRisk?
    let reason: String?
    let impact: String?
    let confidence: Double?
}

@MainActor
final class DiskAdvisorLabStore: ObservableObject {
    @Published var candidates: [DiskAdvisorCandidate] = []
    @Published var selectedIDs: Set<String> = []
    @Published var isScanning = false
    @Published var isAnalyzing = false
    @Published var statusMessage = ""
    @Published var errorMessage: String?
    @Published var cleanedSize: Int64 = 0
    @Published var cleanedCount = 0

    var selectedCandidates: [DiskAdvisorCandidate] {
        candidates.filter { selectedIDs.contains($0.id) }
    }

    var selectedSize: Int64 {
        selectedCandidates.reduce(Int64(0)) { $0 + $1.size }
    }

    var suggestedCleanSize: Int64 {
        candidates.filter(\.isAISafeClean).reduce(Int64(0)) { $0 + $1.size }
    }

    var suggestedCleanCount: Int {
        candidates.filter(\.isAISafeClean).count
    }

    func scan(authorizedRoots: Set<String>? = nil, localizer: Localizer) async {
        guard !isScanning else { return }
        isScanning = true
        errorMessage = nil
        statusMessage = localizer.t("正在扫描常见大文件、缓存和构建产物...", en: "Scanning common large files, caches, and build artifacts...")
        defer { isScanning = false }

        let roots = authorizedRoots
        let found = await Task.detached(priority: .userInitiated) {
            DiskAdvisorScanner.scan(authorizedRoots: roots)
        }.value

        candidates = found
        selectedIDs.removeAll()
        statusMessage = found.isEmpty
            ? localizer.t("没有发现明显候选项。", en: "No obvious candidates found.")
            : localizer.t("发现 \(found.count) 个候选项，建议再进行 AI 分析。", en: "Found \(found.count) candidates. Run AI analysis next.")
    }

    func analyze(config: AIConfig?, localizer: Localizer) async {
        guard !isAnalyzing else { return }
        if candidates.isEmpty {
            await scan(localizer: localizer)
        }
        guard !candidates.isEmpty else { return }

        isAnalyzing = true
        errorMessage = nil
        statusMessage = localizer.t("正在调用 AI 生成清理建议...", en: "Asking AI for cleanup recommendations...")
        defer { isAnalyzing = false }

        do {
            let response = try await DiskAdvisorAIClient.analyze(candidates: Array(candidates.prefix(60)), config: config)
            apply(results: response.results, source: response.source, localizer: localizer)
            statusMessage = localizer.t("AI 已完成分析。", en: "AI analysis complete.")
        } catch {
            let nsError = error as NSError
            statusMessage = localizer.t("AI 分析失败，已保留本地规则建议。", en: "AI analysis failed; local rule suggestions are still available.")
            if nsError.domain == "DiskAdvisor", nsError.code == 5 {
                statusMessage = localizer.t("AI 返回格式不完整，已保留本地规则建议。", en: "AI returned an incomplete format; local rule suggestions are still available.")
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func selectSuggestedClean() {
        selectedIDs = Set(candidates.filter(\.isAISafeClean).map(\.id))
    }

    func clearSelection() {
        selectedIDs.removeAll()
    }

    func removeCleaned(ids: Set<String>, cleanedSize: Int64) {
        candidates.removeAll { ids.contains($0.id) }
        selectedIDs.subtract(ids)
        self.cleanedSize = cleanedSize
        cleanedCount = ids.count
    }

    private func apply(results: [DiskAdvisorLLMResult], source: String, localizer: Localizer) {
        let mapped = results.reduce(into: [String: DiskAdvisorLLMResult]()) { partial, result in
            partial[result.id] = result
        }
        let now = Date()
        candidates = candidates.map { item in
            var updated = item
            guard let result = mapped[item.id] else { return updated }
            if let recommendation = result.recommendation {
                updated.recommendation = recommendation
            }
            if let risk = result.risk {
                updated.risk = risk
            }
            if let reason = result.reason?.trimmingCharacters(in: .whitespacesAndNewlines), !reason.isEmpty {
                updated.reason = reason
            }
            if let impact = result.impact?.trimmingCharacters(in: .whitespacesAndNewlines), !impact.isEmpty {
                updated.impact = impact
            }
            updated.confidence = min(max(result.confidence ?? updated.confidence, 0), 1)
            updated.source = source
            updated.analyzedAt = now
            return updated
        }
    }
}

struct DiskAdvisorLabView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @StateObject private var store = DiskAdvisorLabStore()
    @StateObject private var licenseService = DirectLicenseService.shared
    @State private var searchText = ""
    @State private var showAISettings = false
    @State private var showSubscriptionSettings = false
    @State private var showDeleteConfirm = false
    @State private var showExternalAIConsent = false
    @State private var showCleanResult = false
    @State private var paywallMessage = ""

    private var filteredCandidates: [DiskAdvisorCandidate] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return store.candidates }
        return store.candidates.filter {
            $0.name.lowercased().contains(query)
                || $0.displayPath.lowercased().contains(query)
                || $0.category.lowercased().contains(query)
                || $0.reason.lowercased().contains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                icon: "sparkles",
                title: localizer.t("AI 磁盘顾问", en: "AI Disk Advisor"),
                subtitle: SandboxPaths.isSandboxed
                    ? localizer.t("扫描用户授权目录，并用 AI 判断可清理项", en: "Scan user-authorized folders and review cleanup candidates with AI")
                    : localizer.t("用 Apple Intelligence 或自定义模型判断可清理项", en: "Use Apple Intelligence or your model to review cleanup candidates"),
                color: Theme.Colors.purple
            ) {
                HStack(spacing: Theme.Spacing.sm) {
                    Button {
                        showAISettings = true
                    } label: {
                        Label(localizer.t("AI 设置", en: "AI Settings"), systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .secondary, minHeight: 34))

                    Button {
                        Task { await scanWithAuthorization(promptForAccess: true) }
                    } label: {
                        Label(store.isScanning ? localizer.tokenScopeScanning : scanButtonTitle, systemImage: "magnifyingglass")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))
                    .disabled(store.isScanning || store.isAnalyzing)

                    Button {
                        requestAIAnalysis()
                    } label: {
                        Label(store.isAnalyzing ? localizer.t("分析中", en: "Analyzing") : localizer.t("AI 分析", en: "AI Analyze"), systemImage: "sparkles")
                    }
                    .buttonStyle(BrandButtonStyle(color: Theme.Colors.purple, variant: .primary, minHeight: 34))
                    .disabled(store.isScanning || store.isAnalyzing)
                }
            }

            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    statusStrip
                    summaryGrid
                    actionBar
                    candidateList
                }
                .padding(Theme.Spacing.xl)
            }
        }
        .sheet(isPresented: $showAISettings) {
            AIConfigView()
                .environmentObject(service)
                .environmentObject(localizer)
        }
        .sheet(isPresented: $showSubscriptionSettings) {
            SettingsView(initialTab: .license)
                .environmentObject(service)
                .environmentObject(localizer)
                .environmentObject(licenseService)
        }
        .alert(localizer.t("需要 TraceFence Standard", en: "TraceFence Standard required"), isPresented: Binding(
            get: { !paywallMessage.isEmpty },
            set: { if !$0 { paywallMessage = "" } }
        )) {
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                Button(localizer.t("管理订阅", en: "Manage Subscription")) {
                    showSubscriptionSettings = true
                    paywallMessage = ""
                }
            } else {
                Button(localizer.t("订阅 Standard", en: "Subscribe Standard")) {
                    licenseService.openPurchasePage()
                    paywallMessage = ""
                }
            }
            Button(localizer.cancelBtn, role: .cancel) {
                paywallMessage = ""
            }
        } message: {
            Text(paywallMessage)
        }
        .alert(localizer.confirmDelete, isPresented: $showDeleteConfirm) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.deleteBtn, role: .destructive) {
                performDelete()
            }
        } message: {
            Text(localizer.t(
                "将 \(store.selectedCandidates.count) 个项目移到废纸篓，预计释放 \(service.formatSize(store.selectedSize))。请确认这些项目不再需要。",
                en: "Move \(store.selectedCandidates.count) items to Trash, estimated \(service.formatSize(store.selectedSize)). Confirm these items are no longer needed."
            ))
        }
        .alert(localizer.t("提示", en: "Notice"), isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button(localizer.ok, role: .cancel) {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert(localizer.t("确认发送元数据", en: "Confirm Metadata Sharing"), isPresented: $showExternalAIConsent) {
            Button(localizer.cancelBtn, role: .cancel) {}
            Button(localizer.t("继续分析", en: "Continue")) {
                Task { await analyzeWithCurrentModel() }
            }
        } message: {
            Text(localizer.t(
                "如果需要使用第三方模型，TraceFence 会把候选项的路径、名称、大小、文件数、修改时间和本地规则提示发送到你配置的外部模型服务。不发送文件内容。",
                en: "If an external model is needed, TraceFence will send candidate paths, names, sizes, file counts, modification dates, and local rule hints to your configured external model provider. File contents are not sent."
            ))
        }
        .sheet(isPresented: $showCleanResult) {
            cleanResultSheet
        }
        .onAppear {
            licenseService.refreshTrialState()
            if store.candidates.isEmpty {
                Task { await scanWithAuthorization(promptForAccess: false) }
            }
        }
    }

    private var statusStrip: some View {
        CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg) {
            HStack(spacing: Theme.Spacing.md) {
                ZStack {
                    if diskAdvisorIsBusy {
                        RadarScanGlyph(color: diskAdvisorActivityColor)
                            .scaleEffect(1.35)
                    } else {
                        Circle()
                            .fill(Theme.Colors.purple.opacity(0.12))
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(Theme.Colors.purple)
                    }
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 4) {
                    Text(activeModelText)
                        .font(Theme.Font.subheadlineMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(store.statusMessage.isEmpty ? AppleIntelligenceService.availabilitySummary() : store.statusMessage)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                if diskAdvisorIsBusy {
                    VStack(alignment: .trailing, spacing: Theme.Spacing.xs) {
                        ScanningStatusPill(title: diskAdvisorActivityTitle, color: diskAdvisorActivityColor)
                        ScanningProgressCaption(detail: diskAdvisorActivityDetail, color: diskAdvisorActivityColor)
                    }
                    .frame(minWidth: 220, maxWidth: 340, alignment: .trailing)
                }
            }
        }
    }

    private var diskAdvisorIsBusy: Bool {
        store.isScanning || store.isAnalyzing
    }

    private var diskAdvisorActivityColor: Color {
        store.isAnalyzing ? Theme.Colors.purple : Theme.Colors.info
    }

    private var diskAdvisorActivityTitle: String {
        store.isAnalyzing ? localizer.t("分析中", en: "Analyzing") : localizer.t("扫描中", en: "Scanning")
    }

    private var diskAdvisorActivityDetail: String {
        if !store.statusMessage.isEmpty {
            return store.statusMessage
        }
        if store.isAnalyzing {
            return localizer.t("正在把候选项交给 AI 判断清理风险…", en: "Asking AI to review cleanup risk…")
        }
        return localizer.t("正在扫描常见大文件、缓存和构建产物…", en: "Scanning large files, caches, and build artifacts…")
    }

    private var summaryGrid: some View {
        LazyVGrid(columns: [
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md),
            GridItem(.flexible(), spacing: Theme.Spacing.md)
        ], spacing: Theme.Spacing.md) {
            StatCardView(icon: "internaldrive", iconColor: Theme.Colors.info, title: localizer.t("候选项", en: "Candidates"), value: "\(store.candidates.count)", subtitle: SandboxPaths.isSandboxed ? localizer.t("授权目录", en: "Authorized folders") : localizer.t("有边界扫描", en: "Bounded scan"))
            StatCardView(icon: "sparkles", iconColor: Theme.Colors.purple, title: localizer.t("AI 建议", en: "AI Suggested"), value: "\(store.suggestedCleanCount)", subtitle: service.formatSize(store.suggestedCleanSize))
            StatCardView(icon: "checkmark.circle.fill", iconColor: Theme.Colors.success, title: localizer.t("已勾选", en: "Selected"), value: "\(store.selectedIDs.count)", subtitle: service.formatSize(store.selectedSize))
            StatCardView(icon: "trash", iconColor: Theme.Colors.warning, title: localizer.t("执行方式", en: "Action"), value: localizer.t("废纸篓", en: "Trash"), subtitle: localizer.t("可恢复", en: "Recoverable"))
        }
    }

    private var actionBar: some View {
        CardView(padding: Theme.Spacing.md, cornerRadius: Theme.Radius.lg, showShadow: false) {
            HStack(spacing: Theme.Spacing.md) {
                FilterSearchBar(placeholder: localizer.t("搜索路径、类型或原因", en: "Search path, category, or reason"), text: $searchText)
                    .frame(maxWidth: 360)

                Spacer()

                Button {
                    store.selectSuggestedClean()
                } label: {
                    Label(localizer.t("选择安全建议", en: "Select Safe"), systemImage: "checkmark.circle")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.success, variant: .secondary, minHeight: 34))
                .disabled(store.suggestedCleanCount == 0)

                Button {
                    store.clearSelection()
                } label: {
                    Label(localizer.t("清空选择", en: "Clear"), systemImage: "xmark.circle")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                .disabled(store.selectedIDs.isEmpty)

                Button {
                    confirmDelete()
                } label: {
                    Label(localizer.t("清理所选", en: "Clean Selected"), systemImage: "trash")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .primary, minHeight: 34))
                .disabled(store.selectedIDs.isEmpty)
            }
        }
    }

    private var candidateList: some View {
        VStack(spacing: Theme.Spacing.md) {
            if filteredCandidates.isEmpty {
                CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                    VStack(spacing: Theme.Spacing.md) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(Theme.Colors.textTertiary)
                        Text(localizer.t("暂无候选项", en: "No Candidates"))
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        Text(localizer.t("运行扫描后会显示可分析的磁盘项目。", en: "Run a scan to list disk items for analysis."))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            } else {
                ForEach(filteredCandidates) { candidate in
                    candidateRow(candidate)
                }
            }
        }
    }

    private func candidateRow(_ candidate: DiskAdvisorCandidate) -> some View {
        CardView(padding: Theme.Spacing.lg, cornerRadius: Theme.Radius.lg, showShadow: false) {
            HStack(alignment: .top, spacing: Theme.Spacing.md) {
                Button {
                    toggle(candidate)
                } label: {
                    Image(systemName: store.selectedIDs.contains(candidate.id) ? "checkmark.square.fill" : "square")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(store.selectedIDs.contains(candidate.id) ? Theme.Colors.accent : Theme.Colors.textTertiary)
                        .frame(width: 26, height: 26)
                }
                .buttonStyle(.plain)

                Image(systemName: candidate.isDirectory ? "folder.fill" : "doc.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(candidate.recommendation.color)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.sm) {
                        Text(candidate.name)
                            .font(Theme.Font.subheadlineMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .lineLimit(1)
                        PillBadge(text: candidate.recommendation.label(localizer), color: candidate.recommendation.color, size: .medium)
                        PillBadge(text: candidate.risk.label(localizer), color: candidate.risk.color, size: .medium)
                        Spacer()
                        Text(service.formatSize(candidate.size))
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(Theme.Colors.textPrimary)
                    }

                    Text(candidate.displayPath)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)

                    Text(candidate.reason)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: Theme.Spacing.sm) {
                        Label(candidate.category, systemImage: "tag")
                        Label(candidate.source, systemImage: "brain.head.profile")
                        Label(confidenceText(candidate.confidence), systemImage: "gauge.with.dots.needle.67percent")
                        if let modified = candidate.modifiedDate {
                            Label(shortDate(modified), systemImage: "clock")
                        }
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)

                    if !candidate.impact.isEmpty {
                        Text(candidate.impact)
                            .font(Theme.Font.caption)
                            .foregroundStyle(candidate.risk.color)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private var cleanResultSheet: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(Theme.Colors.success)

            Text(localizer.cleanComplete)
                .font(Theme.Font.title2Bold)
                .foregroundStyle(Theme.Colors.textPrimary)

            CardView(padding: Theme.Spacing.xl, cornerRadius: Theme.Radius.lg) {
                VStack(spacing: Theme.Spacing.md) {
                    Text(service.formatSize(store.cleanedSize))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(Theme.Colors.success)
                    Text("\(localizer.total) \(store.cleanedCount) \(localizer.itemsLabel)")
                        .font(Theme.Font.subheadline)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                .frame(maxWidth: 240)
            }

            Button { showCleanResult = false } label: {
                Text(localizer.ok)
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(.white)
                    .frame(width: 120)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(Theme.Gradients.accent)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
            }
            .buttonStyle(.plain)
        }
        .padding(Theme.Spacing.xxl)
        .frame(width: 380)
    }

    private var activeModelText: String {
        let config = service.aiConfig
        let model = config?.model?.trimmingCharacters(in: .whitespacesAndNewlines)
        switch config?.providerMode ?? .automatic {
        case .automatic:
            if config?.usesExternalProvider == true {
                return localizer.t("自动：Apple，失败后使用 \(model ?? "External")", en: "Auto: Apple, fallback to \(model ?? "External")")
            }
            return localizer.t("自动：Apple Intelligence", en: "Auto: Apple Intelligence")
        case .apple:
            return "Apple Intelligence"
        case .external:
            return localizer.t("第三方模型：\(model ?? "")", en: "External model: \(model ?? "")")
        }
    }

    private var scanButtonTitle: String {
        SandboxPaths.isSandboxed
            ? localizer.t("授权并扫描", en: "Authorize & Scan")
            : localizer.t("扫描", en: "Scan")
    }

    private var shouldAskExternalAIConsent: Bool {
        guard let config = service.aiConfig else { return false }
        switch config.providerMode {
        case .external:
            return true
        case .automatic:
            return config.usesExternalProvider
        case .apple:
            return false
        }
    }

    private func scanWithAuthorization(promptForAccess: Bool) async {
        if SandboxPaths.isSandboxed {
            let roots = service.authorizedLocalScanRoots(promptForAccess: promptForAccess)
            guard !roots.isEmpty else {
                store.statusMessage = localizer.t(
                    "请选择要扫描的文件夹。TraceFence 只会读取你授权的目录。",
                    en: "Choose folders to scan. TraceFence only reads directories you authorize."
                )
                if promptForAccess {
                    store.errorMessage = localizer.t(
                        "Mac App Store 版本需要先授权文件夹，才能扫描磁盘项目。",
                        en: "The Mac App Store build needs folder authorization before scanning disk items."
                    )
                }
                return
            }
            await store.scan(authorizedRoots: roots, localizer: localizer)
        } else {
            await store.scan(localizer: localizer)
        }
    }

    private func requestAIAnalysis() {
        if shouldAskExternalAIConsent {
            showExternalAIConsent = true
        } else {
            Task { await analyzeWithCurrentModel() }
        }
    }

    private func analyzeWithCurrentModel() async {
        if store.candidates.isEmpty {
            await scanWithAuthorization(promptForAccess: true)
        }
        await store.analyze(config: service.aiConfig, localizer: localizer)
    }

    private func toggle(_ candidate: DiskAdvisorCandidate) {
        if store.selectedIDs.contains(candidate.id) {
            store.selectedIDs.remove(candidate.id)
        } else {
            store.selectedIDs.insert(candidate.id)
        }
    }

    private func confirmDelete() {
        licenseService.refreshTrialState()
        guard TraceFenceEntitlementPolicy.canUseProFeatures else {
            if TraceFenceDistributionPolicy.currentChannel.isAppStore {
                paywallMessage = localizer.t(
                    "订阅 TraceFence Standard 后可执行 AI 建议的清理操作。",
                    en: "Subscribe to TraceFence Standard to run cleanup actions recommended by AI Disk Advisor."
                )
            } else {
                paywallMessage = localizer.t(
                    "试用期可以扫描、浏览和预览 AI 建议；执行清理需要激活 TraceFence Standard。",
                    en: "The trial can scan, browse, and preview AI suggestions. Cleanup execution requires TraceFence Standard."
                )
            }
            return
        }
        showDeleteConfirm = true
    }

    private func performDelete() {
        let selected = store.selectedCandidates
        let targets = selected.map { (id: $0.id, path: $0.path, size: $0.size, fileCount: $0.fileCount) }
        Task {
            let result = await service.deleteAdvisedPaths(targets)
            let succeededIDs = Set((result.results ?? []).filter { $0.success == true }.compactMap { $0.id })
            let cleaned = selected.filter { succeededIDs.contains($0.id) }.reduce(Int64(0)) { $0 + $1.size }
            store.removeCleaned(ids: succeededIDs, cleanedSize: cleaned)
            service.refreshDiskInfo()
            showCleanResult = !succeededIDs.isEmpty
            if (result.failed ?? 0) > 0 {
                store.errorMessage = localizer.t("部分项目未能移到废纸篓，请检查权限或文件是否仍存在。", en: "Some items could not be moved to Trash. Check permissions or whether they still exist.")
            }
        }
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private func confidenceText(_ confidence: Double) -> String {
        "\(Int((confidence * 100).rounded()))%"
    }
}

private enum DiskAdvisorAIClient {
    struct Response {
        let results: [DiskAdvisorLLMResult]
        let source: String
    }

    static func analyze(candidates: [DiskAdvisorCandidate], config: AIConfig?) async throws -> Response {
        let instructions = """
        You are TraceFence's disk cleanup advisor for macOS.
        You only receive metadata: path, size, file count, modified date, category, and a local rule hint.
        Do not claim that you inspected file contents.
        Be conservative: user documents, source code, credentials, archives that may be needed for App Store upload, and project data should be keep or review.
        Recommend clean only for clearly generated caches, logs, downloaded installers, package caches, and build artifacts.
        Return strict JSON only, no markdown, no commentary.
        Return either a raw array or {"results":[...]}.
        Schema: [{"id":"same id","recommendation":"clean|review|keep","risk":"safe|caution|danger|unknown","reason":"short reason","impact":"what may happen after cleanup","confidence":0.0}]
        """

        let prompt = "Analyze these macOS disk cleanup candidates:\n\(payload(for: candidates))"
        switch config?.providerMode ?? .automatic {
        case .apple:
            do {
                let result = try await AppleIntelligenceService.generate(
                    instructions: instructions,
                    prompt: prompt,
                    maximumResponseTokens: 4096
                )
                return Response(results: try parse(result.content), source: result.modelName)
            } catch {
                throw NSError(domain: "DiskAdvisor", code: 10, userInfo: [NSLocalizedDescriptionKey: "\(AppleIntelligenceService.displayName): \(error.localizedDescription)"])
            }
        case .external:
            return try await callExternal(config: config, instructions: instructions, prompt: prompt)
        case .automatic:
            do {
                let result = try await AppleIntelligenceService.generate(
                    instructions: instructions,
                    prompt: prompt,
                    maximumResponseTokens: 4096
                )
                return Response(results: try parse(result.content), source: result.modelName)
            } catch {
                guard hasExternalProvider(config) else {
                    throw NSError(domain: "DiskAdvisor", code: 10, userInfo: [NSLocalizedDescriptionKey: "\(AppleIntelligenceService.displayName): \(error.localizedDescription)"])
                }
                return try await callExternal(config: config, instructions: instructions, prompt: prompt)
            }
        }
    }

    private static func hasExternalProvider(_ config: AIConfig?) -> Bool {
        guard let config else { return false }
        let key = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = config.model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return !key.isEmpty && !model.isEmpty && model != AIConfig.appleIntelligenceModel
    }

    private static func callExternal(config: AIConfig?, instructions: String, prompt: String) async throws -> Response {
        guard let config, hasExternalProvider(config) else {
            throw NSError(domain: "DiskAdvisor", code: 1, userInfo: [NSLocalizedDescriptionKey: "请在 AI 设置里选择第三方模型，并填写 API Key 与模型名。"])
        }
        let apiKey = config.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard let url = config.chatCompletionsURL else {
            throw NSError(domain: "DiskAdvisor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Invalid API URL."])
        }

        let body: [String: Any] = [
            "model": config.model ?? "deepseek-chat",
            "messages": [
                ["role": "system", "content": instructions],
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.1,
            "max_tokens": 4096
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 90
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "DiskAdvisor", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid HTTP response."])
        }
        guard http.statusCode == 200 else {
            let detail = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "DiskAdvisor", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode) @ \(url.absoluteString): \(detail.prefix(220))"])
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw NSError(domain: "DiskAdvisor", code: 4, userInfo: [NSLocalizedDescriptionKey: "Invalid model response."])
        }
        return Response(results: try parse(content), source: config.model ?? "External Model")
    }

    private static func payload(for candidates: [DiskAdvisorCandidate]) -> String {
        let formatter = ISO8601DateFormatter()
        let items: [[String: Any]] = candidates.map { item in
            [
                "id": item.id,
                "name": item.name,
                "path": item.displayPath,
                "size_bytes": item.size,
                "file_count": item.fileCount,
                "is_directory": item.isDirectory,
                "modified": item.modifiedDate.map { formatter.string(from: $0) } ?? "",
                "category": item.category,
                "local_hint": item.localHint,
                "local_recommendation": item.recommendation.rawValue,
                "local_risk": item.risk.rawValue
            ]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items, options: [.prettyPrinted]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }

    private static func parse(_ raw: String) throws -> [DiskAdvisorLLMResult] {
        for candidate in jsonCandidates(from: raw) {
            if let results = decodeResults(from: candidate) {
                return results
            }
            if let repaired = repairCommonJSONIssues(candidate),
               let results = decodeResults(from: repaired) {
                return results
            }
        }
        throw NSError(domain: "DiskAdvisor", code: 5, userInfo: [NSLocalizedDescriptionKey: "AI returned text instead of structured cleanup advice."])
    }

    private static func decodeResults(from text: String) -> [DiskAdvisorLLMResult]? {
        guard let data = text.data(using: .utf8) else { return nil }
        if let decoded = try? JSONDecoder().decode([DiskAdvisorLLMResult].self, from: data) {
            return decoded
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return decodeResults(from: object)
    }

    private static func decodeResults(from object: Any) -> [DiskAdvisorLLMResult]? {
        if let array = object as? [[String: Any]] {
            let results = array.compactMap { result(from: $0) }
            return results.isEmpty ? nil : results
        }
        guard let dictionary = object as? [String: Any] else { return nil }
        if let result = result(from: dictionary) {
            return [result]
        }
        for key in ["results", "items", "recommendations", "candidates", "data"] {
            if let nested = dictionary[key], let results = decodeResults(from: nested) {
                return results
            }
        }
        return nil
    }

    private static func result(from dictionary: [String: Any]) -> DiskAdvisorLLMResult? {
        guard let id = stringValue(dictionary["id"] ?? dictionary["path"] ?? dictionary["name"]),
              !id.isEmpty else {
            return nil
        }
        return DiskAdvisorLLMResult(
            id: id,
            recommendation: recommendation(from: dictionary["recommendation"] ?? dictionary["action"] ?? dictionary["decision"]),
            risk: risk(from: dictionary["risk"] ?? dictionary["risk_level"] ?? dictionary["safety"]),
            reason: stringValue(dictionary["reason"] ?? dictionary["why"] ?? dictionary["summary"]),
            impact: stringValue(dictionary["impact"] ?? dictionary["effect"] ?? dictionary["after_cleanup"]),
            confidence: confidence(from: dictionary["confidence"] ?? dictionary["score"])
        )
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func recommendation(from value: Any?) -> DiskAdvisorRecommendation? {
        guard let raw = stringValue(value)?.lowercased() else { return nil }
        if let exact = DiskAdvisorRecommendation(rawValue: raw) { return exact }
        if containsAnyPhrase(raw, [
            "do not delete", "don't delete", "dont delete", "not safe",
            "unsafe", "must keep", "should keep", "keep", "retain",
            "preserve", "danger"
        ]) {
            return .keep
        }
        let tokens = wordTokens(raw)
        if !tokens.isDisjoint(with: ["review", "check", "confirm", "caution"]) {
            return .review
        }
        if !tokens.isDisjoint(with: ["clean", "delete", "remove", "trash"]) {
            return .clean
        }
        return nil
    }

    private static func risk(from value: Any?) -> DiskAdvisorRisk? {
        guard let raw = stringValue(value)?.lowercased() else { return nil }
        if let exact = DiskAdvisorRisk(rawValue: raw) { return exact }
        if containsAnyPhrase(raw, ["not safe", "unsafe"]) {
            return .danger
        }
        let tokens = wordTokens(raw)
        if !tokens.isDisjoint(with: ["danger", "dangerous", "high", "risky"]) {
            return .danger
        }
        if !tokens.isDisjoint(with: ["caution", "medium", "review"]) {
            return .caution
        }
        if !tokens.isDisjoint(with: ["safe", "low"]) {
            return .safe
        }
        if !tokens.isDisjoint(with: ["unknown", "unclear"]) {
            return .unknown
        }
        return nil
    }

    private static func containsAnyPhrase(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains { text.contains($0) }
    }

    private static func wordTokens(_ text: String) -> Set<String> {
        Set(text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty })
    }

    private static func confidence(from value: Any?) -> Double? {
        if let double = value as? Double { return min(max(double, 0), 1) }
        if let number = value as? NSNumber { return min(max(number.doubleValue, 0), 1) }
        guard var text = stringValue(value) else { return nil }
        let isPercent = text.contains("%")
        text = text.replacingOccurrences(of: "%", with: "")
        guard let parsed = Double(text) else { return nil }
        return min(max(isPercent || parsed > 1 ? parsed / 100 : parsed, 0), 1)
    }

    private static func jsonCandidates(from raw: String) -> [String] {
        let stripped = raw
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("```") }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        var candidates: [String] = []
        func append(_ text: String) {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !candidates.contains(trimmed) else { return }
            candidates.append(trimmed)
        }

        append(stripped)
        if let array = fragment(in: stripped, opening: "[", closing: "]") {
            append(array)
        }
        if let object = fragment(in: stripped, opening: "{", closing: "}") {
            append(object)
        }
        return candidates
    }

    private static func fragment(in text: String, opening: Character, closing: Character) -> String? {
        guard let start = text.firstIndex(of: opening),
              let end = text.lastIndex(of: closing),
              start < end else {
            return nil
        }
        return String(text[start...end])
    }

    private static func repairCommonJSONIssues(_ text: String) -> String? {
        var repaired = text
            .replacingOccurrences(of: "\u{feff}", with: "")
            .replacingOccurrences(of: "\u{00a0}", with: " ")
        repaired = repaired.replacingOccurrences(
            of: #",\s*([\]}])"#,
            with: "$1",
            options: .regularExpression
        )
        return repaired == text ? nil : repaired
    }
}

private enum DiskAdvisorScanner {
    private static let minSize: Int64 = 30 * 1024 * 1024
    private static let maxCandidates = 120
    private static let artifactNames: Set<String> = [
        "node_modules", ".next", ".nuxt", ".svelte-kit", "dist", "build", ".build",
        "DerivedData", ".pytest_cache", ".mypy_cache", ".ruff_cache", ".turbo",
        "target", ".gradle", ".parcel-cache", ".cache", "coverage", "__pycache__",
        ".venv", "venv"
    ]
    private static let generatedMediaNames: Set<String> = [
        "cache_videos", "local_videos", "videos", "video", "renders", "rendered",
        "recordings", "captures", "exports", "output", "outputs"
    ]
    private static let generatedTaskNames: Set<String> = [
        "tasks", "jobs", "runs", "workflows"
    ]
    private static let sensitiveNames: Set<String> = [
        ".ssh", ".gnupg", "keychains", "wallet", "wallets", "password", "passwords",
        "secrets", "credentials", "private", "certificates"
    ]

    static func scan(authorizedRoots: Set<String>? = nil) -> [DiskAdvisorCandidate] {
        let home = URL(fileURLWithPath: SandboxPaths.realHomeDirectory, isDirectory: true)
        var seen = Set<String>()
        var results: [DiskAdvisorCandidate] = []

        if let authorizedRoots, !authorizedRoots.isEmpty {
            scanAuthorizedRoots(authorizedRoots, home: home, into: &results, seen: &seen)
            return results
                .sorted { $0.size > $1.size }
                .prefix(maxCandidates)
                .map { $0 }
        }

        scanKnownHighValueDirectories(home: home, into: &results, seen: &seen)
        scanHiddenAppDataDirectories(home: home, into: &results, seen: &seen)
        scanTopLevelChildren(home.appendingPathComponent("Downloads", isDirectory: true), category: "Downloads", into: &results, seen: &seen)
        scanTopLevelChildren(home.appendingPathComponent("Desktop", isDirectory: true), category: "Desktop", into: &results, seen: &seen)

        let exactDirectories: [(String, String)] = [
            ("Library/Caches", "Cache"),
            ("Library/Logs", "Logs"),
            ("Library/Developer/Xcode/DerivedData", "Xcode DerivedData"),
            ("Library/Developer/Xcode/Archives", "Xcode Archives"),
            ("Library/Developer/CoreSimulator/Caches", "Simulator Cache"),
            (".cache", "Developer Cache"),
            (".npm", "Package Cache"),
            (".pnpm-store", "Package Cache"),
            (".gradle/caches", "Package Cache"),
            (".m2/repository", "Package Cache"),
            (".cargo/registry", "Package Cache")
        ]

        for (relative, category) in exactDirectories {
            scanTopLevelChildren(home.appendingPathComponent(relative, isDirectory: true), category: category, into: &results, seen: &seen)
        }

        for root in projectRoots(home: home) {
            scanProjectArtifacts(root, into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { break }
        }
        scanLargeHomeDirectories(home: home, into: &results, seen: &seen)

        return results
            .sorted { $0.size > $1.size }
            .prefix(maxCandidates)
            .map { $0 }
    }

    private static func scanAuthorizedRoots(_ rootPaths: Set<String>, home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        let roots = rootPaths
            .map { URL(fileURLWithPath: $0, isDirectory: true).standardizedFileURL }
            .filter { isDirectory($0) }
            .sorted { $0.path < $1.path }

        for root in roots {
            let category = categoryForAuthorizedRoot(root, home: home)
            if root.path != home.standardizedFileURL.path {
                addCandidate(root, category: category, into: &results, seen: &seen)
            }
            scanTopLevelChildren(root, category: category, into: &results, seen: &seen)
            scanProjectArtifacts(root, into: &results, seen: &seen)

            if root.standardizedFileURL.path == home.standardizedFileURL.path {
                scanHiddenAppDataDirectories(home: home, into: &results, seen: &seen)
                scanLargeHomeDirectories(home: home, into: &results, seen: &seen)
            }

            if results.count >= maxCandidates * 2 { break }
        }
    }

    private static func scanKnownHighValueDirectories(home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        let fileSystemCandidates: [(URL, String, String)] = [
            (URL(fileURLWithPath: "/System/Volumes/Data/private/tmp", isDirectory: true), "Temporary Files", "System temp"),
            (URL(fileURLWithPath: "/private/tmp", isDirectory: true), "Temporary Files", "System temp"),
            (URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld", isDirectory: true), "Simulator dyld Cache", "Simulator dyld cache"),
            (home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true), "Simulator Devices", "Simulator devices"),
            (home.appendingPathComponent(".npm", isDirectory: true), "Package Cache", "npm cache"),
            (home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true), "Xcode DerivedData", "Xcode DerivedData")
        ]

        for (url, category, name) in fileSystemCandidates {
            addCandidate(url, category: category, displayName: name, into: &results, seen: &seen)
        }
    }

    private static func scanHiddenAppDataDirectories(home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: resourceKeys,
            options: []
        ) else {
            return
        }

        for child in children.prefix(300) {
            let lower = child.lastPathComponent.lowercased()
            guard lower.hasPrefix("."),
                  !shouldSkipHomeDirectory(lower),
                  !isSensitive(child) else {
                continue
            }
            addCandidate(child, category: "Hidden App Data", into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { return }
        }
    }

    private static func scanLargeHomeDirectories(home: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: home,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        for child in children.prefix(300) {
            let lower = child.lastPathComponent.lowercased()
            guard isDirectory(child),
                  !shouldSkipHomeDirectory(lower),
                  !isSensitive(child) else {
                continue
            }
            addCandidate(child, category: "Personal Files", into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { return }
        }
    }

    private static func scanTopLevelChildren(_ root: URL, category: String, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard isDirectory(root),
              let children = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsHiddenFiles]
              ) else {
            return
        }

        for child in children.prefix(600) {
            guard !isSensitive(child) else { continue }
            addCandidate(child, category: category, into: &results, seen: &seen)
            if results.count >= maxCandidates * 2 { return }
        }
    }

    private static func scanProjectArtifacts(_ root: URL, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        guard isDirectory(root),
              let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: resourceKeys,
                options: [.skipsPackageDescendants]
              ) else {
            return
        }

        let rootDepth = root.pathComponents.count
        var visited = 0
        for case let url as URL in enumerator {
            visited += 1
            if visited > 80_000 || results.count >= maxCandidates * 2 { break }

            let depth = url.pathComponents.count - rootDepth
            if depth > 6 {
                enumerator.skipDescendants()
                continue
            }
            guard isDirectory(url), !isSensitive(url) else { continue }

            let name = url.lastPathComponent
            let lower = name.lowercased()
            if generatedMediaNames.contains(lower) {
                addCandidate(url, category: lower.contains("cache") ? "Generated Media Cache" : "Generated Media", into: &results, seen: &seen)
                enumerator.skipDescendants()
            } else if generatedTaskNames.contains(lower) {
                addCandidate(url, category: "Generated Task Data", into: &results, seen: &seen)
                enumerator.skipDescendants()
            } else if lower == "logs" || lower == "log" {
                addCandidate(url, category: "Logs", into: &results, seen: &seen)
                enumerator.skipDescendants()
            } else if artifactNames.contains(name) || artifactNames.contains(lower) {
                addCandidate(url, category: "Build Artifact", into: &results, seen: &seen)
                enumerator.skipDescendants()
            } else if shouldSkipDirectory(lower) {
                enumerator.skipDescendants()
            }
        }
    }

    private static func addCandidate(_ url: URL, category: String, displayName: String? = nil, into results: inout [DiskAdvisorCandidate], seen: inout Set<String>) {
        let standardized = url.standardizedFileURL.path
        let canonical = url.resolvingSymlinksInPath().standardizedFileURL.path
        guard !seen.contains(standardized), !seen.contains(canonical) else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized, isDirectory: &isDir) else { return }

        let values = try? url.resourceValues(forKeys: Set(resourceKeys))
        if values?.isSymbolicLink == true { return }

        let (size, fileCount) = sizeOfItem(url)
        guard size >= minSize else { return }
        seen.insert(standardized)
        seen.insert(canonical)

        let modified = values?.contentModificationDate
        let classification = classify(url: url, category: category, modified: modified)
        results.append(DiskAdvisorCandidate(
            id: standardized,
            name: displayName ?? (url.lastPathComponent.isEmpty ? standardized : url.lastPathComponent),
            path: standardized,
            size: size,
            fileCount: fileCount,
            isDirectory: isDir.boolValue,
            modifiedDate: modified,
            category: category,
            localHint: classification.hint,
            recommendation: classification.recommendation,
            risk: classification.risk,
            reason: classification.hint,
            impact: classification.impact,
            confidence: classification.confidence,
            source: "Local Rules",
            analyzedAt: nil
        ))
    }

    private static func classify(url: URL, category: String, modified: Date?) -> (recommendation: DiskAdvisorRecommendation, risk: DiskAdvisorRisk, hint: String, impact: String, confidence: Double) {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        let old = modified.map { Date().timeIntervalSince($0) > 7 * 24 * 60 * 60 } ?? false

        if sensitiveNames.contains(where: { path.contains($0) }) {
            return (.keep, .danger, "路径像凭据、密钥或私密数据，默认保留。", "删除可能导致登录、签名或账户恢复问题。", 0.85)
        }
        if category == "Personal Files" {
            return (.keep, .danger, "这是用户个人资料目录，默认只做占用提示，不建议自动清理。", "删除可能造成个人文件或照片资料丢失。", 0.92)
        }
        if category == "Project Data" {
            return (.keep, .danger, "这是项目根目录，可能包含源码、配置和生成内容；应只清理明确的缓存子目录。", "删除整个项目会造成源码和工作文件丢失。", 0.88)
        }
        if category == "AI Agent Data" {
            return (.review, .caution, "AI Agent 数据通常包含会话历史、索引或本地状态，删除前应确认是否还需要追溯记录。", "删除后可能丢失历史会话、项目上下文或本地 agent 状态。", 0.78)
        }
        if category == "Hidden App Data" {
            return (.review, .caution, "这是用户目录下的大型隐藏应用数据，可能是 Agent、开发工具、包管理器或其它本地状态。", "删除前需要确认来源；它可能包含会话历史、索引、缓存或账户状态。", 0.7)
        }
        if category == "Simulator Devices" {
            return (.review, .caution, "模拟器设备可能包含安装的 App、数据容器和调试状态，可按设备选择删除。", "删除后对应模拟器设备和其中 App 数据会消失，需要重新创建或安装。", 0.76)
        }
        if category == "Simulator dyld Cache" {
            return (.review, .caution, "模拟器 dyld 缓存通常可重建，但位于系统级开发者目录，可能需要权限。", "下次启动模拟器可能重新生成缓存，清理操作也可能被系统权限拒绝。", 0.74)
        }
        if category == "Temporary Files" {
            return (old ? .clean : .review, old ? .safe : .caution, "系统临时目录常见于测试、构建和中间文件，旧文件通常值得清理。", "仍在运行的任务可能依赖近期临时文件；清理前建议关闭相关构建或测试进程。", old ? 0.84 : 0.66)
        }
        if category == "Generated Media Cache" || category == "Generated Task Data" {
            return (.review, .caution, "这是生成视频或任务缓存，通常占用较大，适合用户确认后清理。", "删除后相关生成任务、缓存视频或中间结果可能无法继续复用。", 0.8)
        }
        if category == "Generated Media" {
            return (.review, .caution, "这是生成的视频输出目录，可能既有缓存也有用户想保留的成品。", "删除后可能丢失已经生成的视频结果。", 0.72)
        }
        if category == "App Update Cache" {
            return (.clean, .safe, "应用更新缓存通常可以重新下载。", "下次更新可能需要重新下载安装包。", 0.86)
        }
        if category == "Xcode Archives" || name.hasSuffix(".xcarchive") {
            return (.review, .caution, "Xcode archive 可能用于重新上传、符号化或回溯版本，删除前需要确认。", "删除后可能无法重新提交或定位线上问题。", 0.74)
        }
        if category.contains("Cache") || category == "Logs" || category == "Xcode DerivedData" || category == "Simulator Cache" {
            return (old ? .clean : .review, old ? .safe : .caution, "缓存、日志或派生数据通常可以重建。", "首次重新打开相关工具时可能需要重新索引或下载。", old ? 0.82 : 0.68)
        }
        if category == "Build Artifact" {
            return (old ? .clean : .review, old ? .safe : .caution, "构建产物通常可以由源码重新生成。", "下次构建可能变慢，未提交生成物请先确认。", old ? 0.78 : 0.64)
        }
        if ["dmg", "pkg", "zip", "tar", "gz", "xz", "rar", "7z"].contains(url.pathExtension.lowercased()) {
            return (.review, .caution, "下载的安装包或压缩包可能已经不再需要。", "删除后如需安装或恢复内容，需要重新下载。", 0.62)
        }
        return (.review, .caution, "这是较大的磁盘项目，建议让 AI 进一步判断用途。", "删除前请确认是否仍在使用。", 0.52)
    }

    private static func sizeOfItem(_ url: URL) -> (Int64, Int) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else {
            return (0, 0)
        }

        if !isDir.boolValue {
            let values = try? url.resourceValues(forKeys: [.fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
            return (Int64(size), 1)
        }

        var total: Int64 = 0
        var count = 0
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey],
            options: [.skipsPackageDescendants]
        ) else {
            return (0, 0)
        }

        for case let child as URL in enumerator {
            if count > 60_000 { break }
            let values = try? child.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey, .fileSizeKey])
            if values?.isSymbolicLink == true { continue }
            guard values?.isRegularFile == true else { continue }
            let size = values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? values?.fileSize ?? 0
            total += Int64(size)
            count += 1
        }
        return (total, max(count, 1))
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    private static func isSensitive(_ url: URL) -> Bool {
        let lower = url.lastPathComponent.lowercased()
        return sensitiveNames.contains(lower)
    }

    private static func shouldSkipDirectory(_ lowerName: String) -> Bool {
        [".git", ".svn", ".hg", "pictures", "photos library.photoslibrary", "music", "movies", "library", "applications"].contains(lowerName)
    }

    private static func shouldSkipHomeDirectory(_ lowerName: String) -> Bool {
        let skipped = [
            ".ds_store", ".localized", ".trash", ".ssh", ".gnupg",
            "library", "applications", "developer", "projects", "code", "github",
            "downloads", "desktop", "public", "sites"
        ]
        return skipped.contains(lowerName)
    }

    private static func projectRoots(home: URL) -> [URL] {
        ["Developer", "Projects", "Code", "GitHub", "Documents", "Downloads"]
            .map { home.appendingPathComponent($0, isDirectory: true) }
    }

    private static func categoryForAuthorizedRoot(_ url: URL, home: URL) -> String {
        let path = url.standardizedFileURL.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        if path.contains("/private/tmp") { return "Temporary Files" }
        if path.contains("/coresimulator/devices") { return "Simulator Devices" }
        if path.contains("/coresimulator/caches") { return "Simulator Cache" }
        if name == "deriveddata" { return "Xcode DerivedData" }
        if name == "archives", path.contains("/xcode/") { return "Xcode Archives" }
        if name == "caches" || path.contains("/library/caches") { return "Cache" }
        if name == "logs" || path.contains("/library/logs") { return "Logs" }
        if name.hasPrefix(".") { return "Hidden App Data" }
        if path.hasPrefix(home.appendingPathComponent("Downloads", isDirectory: true).path.lowercased()) { return "Downloads" }
        if path.hasPrefix(home.appendingPathComponent("Desktop", isDirectory: true).path.lowercased()) { return "Desktop" }
        return "Selected Folder"
    }

    private static var resourceKeys: [URLResourceKey] {
        [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey, .contentModificationDateKey, .fileSizeKey, .fileAllocatedSizeKey, .totalFileAllocatedSizeKey]
    }
}
