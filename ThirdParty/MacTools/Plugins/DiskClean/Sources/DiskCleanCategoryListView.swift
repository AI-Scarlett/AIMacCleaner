import SwiftUI
import MacToolsPluginKit

// MARK: - Grouping

/// Data for one category card. The view derives it from the candidate list and holds no extra state.
struct DiskCleanCategoryGroup: Identifiable, Equatable, Sendable {
    let category: DiskCleanCategoryID
    let candidates: [DiskCleanCandidate]
    let selectableCount: Int
    let selectedCount: Int
    /// Total reclaimable bytes for every selectable candidate in this category.
    /// This is deliberately independent of checkbox state: the category header describes
    /// what the scan found, while `selectedEstimatedBytes` describes the pending action.
    let cleanableEstimatedBytes: Int64
    let selectedEstimatedBytes: Int64

    var id: String { category.rawValue }

    /// Grouped by `DiskCleanCategoryID.displayOrder` (low risk → high). Empty categories are omitted.
    static func groups(
        candidates: [DiskCleanCandidate],
        selection: DiskCleanSelectionProjection
    ) -> [DiskCleanCategoryGroup] {
        // Complete, allowed zero-allocation entries cannot reclaim measurable disk space. Keep
        // them in the scan artifact/audit, but do not flood the review list with "0 KB" rows.
        let visibleCandidates = candidates.filter { candidate in
            guard candidate.safety.isCleanable,
                  let result = candidate.sizeResult,
                  result.completeness.isComplete else {
                return true
            }
            return result.estimatedBytes > 0
        }
        let candidatesByCategory = Dictionary(grouping: visibleCandidates, by: \.category)
        return DiskCleanCategoryID.displayOrder.compactMap { category in
            guard let items = candidatesByCategory[category], !items.isEmpty else { return nil }
            let selectable = items.filter { selection.isSelectable($0.id) }
            let selected = items.filter { selection.isSelected($0.id) }
            return DiskCleanCategoryGroup(
                category: category,
                candidates: items,
                selectableCount: selectable.count,
                selectedCount: selected.count,
                cleanableEstimatedBytes: selectable.reduce(0) { $0 + max($1.estimatedBytes, 0) },
                selectedEstimatedBytes: selected.reduce(0) { $0 + max($1.estimatedBytes, 0) }
            )
        }
    }
}

// MARK: - Category card list

/// Category card list on the detail page (design §8.3 item 3).
struct DiskCleanCategoryListView: View {
    let groups: [DiskCleanCategoryGroup]
    let selection: DiskCleanSelectionProjection
    /// Per-item terminal status from the last run, used for badges such as "content changed".
    let outcomesByCandidateID: [DiskCleanCandidate.ID: DiskCleanExecutionItemResult.Outcome]
    let localization: PluginLocalization
    let isInteractionEnabled: Bool
    let onToggleCandidate: (DiskCleanCandidate.ID, Bool) -> Void
    let onToggleCategory: (DiskCleanCategoryID, Bool) -> Void

    @Binding var expandedCategories: Set<DiskCleanCategoryID>

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.sectionHeaderContent) {
            ForEach(groups) { group in
                DiskCleanCategoryCard(
                    group: group,
                    state: selection.state(of: group.category),
                    selection: selection,
                    outcomesByCandidateID: outcomesByCandidateID,
                    localization: localization,
                    isInteractionEnabled: isInteractionEnabled,
                    isExpanded: expandedCategories.contains(group.category),
                    onToggleExpanded: {
                        if expandedCategories.contains(group.category) {
                            expandedCategories.remove(group.category)
                        } else {
                            expandedCategories.insert(group.category)
                        }
                    },
                    onToggleCandidate: onToggleCandidate,
                    onToggleCategory: onToggleCategory
                )
            }
        }
    }
}

// MARK: - Category cards

private struct DiskCleanCategoryCard: View {
    let group: DiskCleanCategoryGroup
    let state: DiskCleanCategorySelectionState
    let selection: DiskCleanSelectionProjection
    let outcomesByCandidateID: [DiskCleanCandidate.ID: DiskCleanExecutionItemResult.Outcome]
    let localization: PluginLocalization
    let isInteractionEnabled: Bool
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onToggleCandidate: (DiskCleanCandidate.ID, Bool) -> Void
    let onToggleCategory: (DiskCleanCategoryID, Bool) -> Void
    @State private var isReviewPresented = false
    @State private var reviewedCandidates: [DiskCleanCandidate] = []

    var body: some View {
        VStack(spacing: 0) {
            header
            if isExpanded {
                PluginSettingsListDivider()
                candidateRows
            }
        }
        .diskCleanSurface(.elevated)
        .sheet(isPresented: $isReviewPresented) {
            categoryReview
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            DiskCleanTriStateCheckbox(
                state: state,
                // Non-default candidates are reviewed before an explicit category selection.
                // A checked or mixed state clears the category.
                onToggle: toggleCategory,
                help: checkboxHelp
            )
            .disabled(!isInteractionEnabled || !state.isSelectable)

            DiskCleanIconBadge(
                symbolName: group.category.symbolName,
                tint: categoryTint,
                size: 36
            )

            Button(action: onToggleExpanded) {
              VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(group.category.title(localization: localization))
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                Text(group.category.consequence(localization: localization))
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(countSummary)
                    .font(PluginSettingsTheme.Typography.statusBadge)
                    .foregroundStyle(.secondary)
                if group.selectedCount == 0 && group.selectableCount > 0 {
                    Text(localization.string("detail.category.reviewHint", defaultValue: "点击复选框可选择本类项目；需复核的内容会先列出供你确认。"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

            Text(DiskCleanFormat.approximateBytes(group.cleanableEstimatedBytes, localization: localization))
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .frame(width: DiskCleanFormat.byteColumnWidth, alignment: .trailing)

            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(PluginSettingsTheme.Typography.rowIcon)
            }
            .buttonStyle(.borderless)
            .help(
                isExpanded
                    ? localization.string("detail.category.collapse", defaultValue: "收起项目")
                    : localization.string("detail.category.expand", defaultValue: "展开项目")
            )
        }
        .pluginSettingsListRowPadding(interactive: true)
    }

    private var candidateRows: some View {
        VStack(spacing: 0) {
            ForEach(group.candidates) { candidate in
                DiskCleanCandidateRow(
                    candidate: candidate,
                    isSelected: selection.isSelected(candidate.id),
                    isSelectable: selection.isSelectable(candidate.id),
                    outcome: outcomesByCandidateID[candidate.id],
                    localization: localization,
                    isInteractionEnabled: isInteractionEnabled,
                    onToggle: { onToggleCandidate(candidate.id, $0) }
                )
                if candidate.id != group.candidates.last?.id {
                    PluginSettingsListDivider()
                }
            }
        }
    }

    private var countSummary: String {
        localization.format(
            "detail.category.counts",
            defaultValue: "共 %d 项 · 可清理 %d 项 · 已选 %d 项",
            group.candidates.count,
            group.selectableCount,
            group.selectedCount
        )
    }

    private var checkboxHelp: String {
        state.isChecked
            ? localization.string("detail.category.deselectAll", defaultValue: "取消选择本类全部项目")
            : localization.string("detail.category.selectVisible", defaultValue: "选择本类可清理项目")
    }

    private var selectableCandidates: [DiskCleanCandidate] {
        group.candidates.filter { selection.isSelectable($0.id) }
    }

    private func toggleCategory() {
        if state.isChecked {
            onToggleCategory(group.category, false)
        } else if selectableCandidates.contains(where: { !DiskCleanSelectionModel.isSelectedByDefault($0) }) {
            reviewedCandidates = selectableCandidates
            if !isExpanded { onToggleExpanded() }
            isReviewPresented = true
        } else {
            onToggleCategory(group.category, true)
        }
    }

    private var categoryReview: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(localization.format("detail.category.reviewTitle", defaultValue: "复核 %@ 的 %d 项", group.category.title(localization: localization), reviewedCandidates.count))
                .font(.headline)
            Text(localization.string("detail.category.reviewMessage", defaultValue: "这些内容未被默认选中。请核对路径和影响，确认后只会勾选项目；删除仍由清理按钮执行。"))
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(reviewedCandidates) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(DiskCleanFormat.approximateBytes(candidate.estimatedBytes, localization: localization))
                                .font(.caption).foregroundStyle(.secondary)
                            Text(reviewConsequence(candidate))
                                .font(.caption).foregroundStyle(candidate.recoveryClass == .originalData ? .red : .orange)
                        }
                        Divider()
                    }
                }
            }
            .frame(maxHeight: 320)
            HStack {
                Button(localization.string("detail.action.cancelClean", defaultValue: "取消")) { isReviewPresented = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(localization.format("detail.category.confirmSelection", defaultValue: "选择这 %d 项", reviewedCandidates.count)) {
                    guard reviewedCandidates == selectableCandidates else { isReviewPresented = false; return }
                    onToggleCategory(group.category, true)
                    isReviewPresented = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isInteractionEnabled || reviewedCandidates != selectableCandidates)
            }
        }
        .padding(24)
        .frame(width: 580)
    }

    private func reviewConsequence(_ candidate: DiskCleanCandidate) -> String {
        switch candidate.recoveryClass {
        case .regenerable:
            return localization.string("detail.category.reviewRegenerable", defaultValue: "可重新构建；可能近期仍在使用或所在仓库有未提交改动，请确认暂时不需要这些产物。")
        case .downloadRequired:
            return localization.string("detail.category.reviewDownload", defaultValue: "删除后需要重新下载或安装依赖，离线时可能无法恢复使用。")
        case .originalData:
            return localization.string("detail.category.reviewOriginal", defaultValue: "包含原始文件，不能靠重新构建恢复。请确认已有备份或确实不再需要。")
        }
    }

    private var categoryTint: Color {
        switch group.category {
        case .developer, .systemCaches, .virtualization, .developerArtifacts:
            return .orange
        case .installers:
            return .green
        case .userFiles, .advisorFindings:
            return .red
        case .aiTools:
            return DiskCleanVisual.accent
        case .logs:
            return .indigo
        case .userEssentials, .appCaches, .browsers, .cloudOffice, .communication:
            return .blue
        }
    }
}

// MARK: - Candidate row

private struct DiskCleanCandidateRow: View {
    let candidate: DiskCleanCandidate
    let isSelected: Bool
    let isSelectable: Bool
    let outcome: DiskCleanExecutionItemResult.Outcome?
    let localization: PluginLocalization
    let isInteractionEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: PluginSettingsTheme.Spacing.rowContentControl) {
            Toggle("", isOn: Binding(get: { isSelected }, set: { onToggle($0) }))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!isInteractionEnabled || !isSelectable)

            VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.rowTitleDescription) {
                Text(candidate.displayName)
                    .font(PluginSettingsTheme.Typography.rowTitle)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text(candidate.path)
                    .font(PluginSettingsTheme.Typography.monospacedValue)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                if !badges.isEmpty {
                    HStack(spacing: PluginSettingsTheme.Spacing.controlCluster) {
                        ForEach(badges) { badge in
                            DiskCleanBadgeLabel(badge: badge)
                        }
                    }
                }
            }

            Spacer(minLength: PluginSettingsTheme.Spacing.rowContentControl)

            Text(sizeText)
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .foregroundStyle(candidate.sizeResult == nil ? Color.secondary : Color.primary)
                .frame(width: DiskCleanFormat.byteColumnWidth, alignment: .trailing)
        }
        .pluginSettingsListRowPadding()
    }

    /// Unresolved sizes show "calculating…" rather than "0 bytes"—the latter would look like an empty item.
    private var sizeText: String {
        guard candidate.sizeResult != nil else {
            return localization.string("detail.candidate.sizing", defaultValue: "计算中…")
        }
        return DiskCleanFormat.approximateBytes(candidate.estimatedBytes, localization: localization)
    }

    private var badges: [DiskCleanBadge] {
        DiskCleanBadge.badges(for: candidate, outcome: outcome, localization: localization)
    }
}

// MARK: - Badges

struct DiskCleanBadge: Identifiable, Equatable, Sendable {
    enum Tone: Equatable, Sendable {
        case neutral
        case warning
    }

    let id: String
    let text: String
    let tone: Tone

    /// Per-item badges (design §8.3): in use / whitelist / protected / partial-reason / content changed / mount point / calculating.
    ///
    /// Order is priority: first "what happened on the last cleanup", then "why it cannot be selected now".
    static func badges(
        for candidate: DiskCleanCandidate,
        outcome: DiskCleanExecutionItemResult.Outcome?,
        localization: PluginLocalization
    ) -> [DiskCleanBadge] {
        var badges: [DiskCleanBadge] = []

        if let outcome {
            badges.append(contentsOf: self.badges(for: outcome, localization: localization))
        }

        badges.append(recoveryBadge(for: candidate.recoveryClass, localization: localization))

        // Candidate-local facts (P2 repo status, installer age) come before safety status:
        // they explain "why this item was not selected by default"—the first question users ask when something is unchecked.
        badges += candidate.notes.compactMap { badge(for: $0, localization: localization) }

        switch candidate.safety {
        case .allowed:
            break
        case let .inUse(processName):
            badges.append(
                DiskCleanBadge(
                    id: "inUse",
                    text: localization.format("badge.inUse", defaultValue: "使用中：%@", processName),
                    tone: .warning
                )
            )
        case .whitelisted:
            badges.append(
                DiskCleanBadge(
                    id: "whitelisted",
                    text: localization.string("badge.whitelisted", defaultValue: "白名单"),
                    tone: .neutral
                )
            )
        case .protected:
            badges.append(
                DiskCleanBadge(
                    id: "protected",
                    text: localization.string("badge.protected", defaultValue: "受保护"),
                    tone: .neutral
                )
            )
        case .invalid:
            badges.append(
                DiskCleanBadge(
                    id: "invalid",
                    text: localization.string("badge.invalid", defaultValue: "路径不安全"),
                    tone: .neutral
                )
            )
        case .requiresAdmin:
            badges.append(
                DiskCleanBadge(
                    id: "requiresAdmin",
                    text: localization.string("badge.requiresAdmin", defaultValue: "需要管理员"),
                    tone: .neutral
                )
            )
        }

        guard let sizeResult = candidate.sizeResult else {
            badges.append(
                DiskCleanBadge(
                    id: "sizing",
                    text: localization.string("badge.sizing", defaultValue: "计算中"),
                    tone: .neutral
                )
            )
            return badges
        }

        let reasons = sizeResult.completeness.partialReasons
        // Mount points are listed separately: not "incomplete sizing", but "this directory contains another volume; deleting it would cross boundaries".
        if reasons.contains(.crossedMountPoint) {
            badges.append(
                DiskCleanBadge(
                    id: "crossedMountPoint",
                    text: localization.string("badge.crossedMountPoint", defaultValue: "含挂载点"),
                    tone: .warning
                )
            )
        }
        let otherReasons = reasons.subtracting([.crossedMountPoint])
        if !otherReasons.isEmpty {
            badges.append(
                DiskCleanBadge(
                    id: "partial",
                    text: localization.format(
                        "badge.partial",
                        defaultValue: "扫描不完整：%@",
                        DiskCleanFormat.partialReasons(otherReasons, localization: localization)
                    ),
                    tone: .warning
                )
            )
        }

        return badges
    }

    private static func recoveryBadge(
        for recoveryClass: DiskCleanRecoveryClass,
        localization: PluginLocalization
    ) -> DiskCleanBadge {
        switch recoveryClass {
        case .regenerable:
            return DiskCleanBadge(
                id: "recovery.regenerable",
                text: localization.string("badge.recovery.regenerable", defaultValue: "可本地再生"),
                tone: .neutral
            )
        case .downloadRequired:
            return DiskCleanBadge(
                id: "recovery.downloadRequired",
                text: localization.string("badge.recovery.downloadRequired", defaultValue: "需重新下载"),
                tone: .warning
            )
        case .originalData:
            return DiskCleanBadge(
                id: "recovery.originalData",
                text: localization.string("badge.recovery.originalData", defaultValue: "原始数据"),
                tone: .warning
            )
        }
    }

    /// Candidate annotation badges (design §10 P2 badge system).
    ///
    /// "Owning project" is not a badge: it is **locating information**, not a warning; packing it into the capsule row would drown the real
    /// "uncommitted changes" signal. Project path is already expressed by the candidate path itself.
    private static func badge(
        for note: DiskCleanCandidateNote,
        localization: PluginLocalization
    ) -> DiskCleanBadge? {
        switch note {
        case let .repositoryHasChanges(_, reason):
            return DiskCleanBadge(
                id: "repositoryHasChanges",
                text: repositoryChangeText(reason, localization: localization),
                tone: .warning
            )
        case .mayNotBeInstaller:
            return DiskCleanBadge(
                id: "mayNotBeInstaller",
                text: localization.string("badge.mayNotBeInstaller", defaultValue: "未必是安装包"),
                tone: .neutral
            )
        case let .recentlyDownloaded(modifiedAt):
            return DiskCleanBadge(
                id: "recentlyDownloaded",
                text: localization.format(
                    "badge.recentlyDownloaded",
                    defaultValue: "近期下载：%@",
                    DiskCleanFormat.timestamp(modifiedAt)
                ),
                tone: .neutral
            )
        case let .recentlyChanged(modifiedAt):
            return DiskCleanBadge(
                id: "recentlyChanged",
                text: localization.format(
                    "badge.recentlyChanged",
                    defaultValue: "7 天内仍在使用：%@",
                    DiskCleanFormat.timestamp(modifiedAt)
                ),
                tone: .warning
            )
        case .developerProject:
            return nil
        }
    }

    /// Treat check failure separately from real dirt: the former is "could not determine; treat as dirty", writing it as "has uncommitted changes"
    /// would invent a fact the user cannot find in the repo.
    private static func repositoryChangeText(
        _ reason: DiskCleanPurgeGitState.DirtyReason,
        localization: PluginLocalization
    ) -> String {
        switch reason {
        case .uncommittedChanges:
            return localization.string("badge.repository.uncommitted", defaultValue: "仓库有未提交改动")
        case .unpushedCommits:
            return localization.string("badge.repository.unpushed", defaultValue: "仓库有未推送提交")
        case let .inspectionFailed(detail):
            return localization.format(
                "badge.repository.inspectionFailed",
                defaultValue: "无法确认仓库状态：%@",
                detail
            )
        }
    }

    private static func badges(
        for outcome: DiskCleanExecutionItemResult.Outcome,
        localization: PluginLocalization
    ) -> [DiskCleanBadge] {
        switch outcome {
        case .changedSinceScan:
            return [
                DiskCleanBadge(
                    id: "changedSinceScan",
                    text: localization.string("badge.changedSinceScan", defaultValue: "内容已变化，请重新扫描"),
                    tone: .warning
                )
            ]
        case .partiallyDeleted:
            return [
                DiskCleanBadge(
                    id: "partiallyDeleted",
                    text: localization.string("badge.partiallyDeleted", defaultValue: "只删除了一部分"),
                    tone: .warning
                )
            ]
        case .rollbackBlocked:
            return [
                DiskCleanBadge(
                    id: "rollbackBlocked",
                    text: localization.string("badge.rollbackBlocked", defaultValue: "无法放回原处"),
                    tone: .warning
                )
            ]
        case let .failed(message):
            return [DiskCleanBadge(id: "failed", text: message, tone: .warning)]
        case .removed, .trashed, .skipped:
            return []
        }
    }
}

struct DiskCleanBadgeLabel: View {
    let badge: DiskCleanBadge

    var body: some View {
        Text(badge.text)
            .font(PluginSettingsTheme.Typography.statusBadge)
            .foregroundStyle(badge.tone == .warning ? Color.orange : Color.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule().fill(Color(nsColor: .quaternaryLabelColor).opacity(0.4))
            )
    }
}

// MARK: - Tri-state checkbox

/// Tri-state checkbox.
///
/// `Toggle` only has on/off, but category selection must express "partially selected"—categories that contain medium/high items
/// necessarily land in mixed after "select all low-risk"; a two-state control would keep showing "not fully selected"
/// and users would think they mis-clicked.
struct DiskCleanTriStateCheckbox: View {
    let state: DiskCleanCategorySelectionState
    let onToggle: () -> Void
    let help: String

    var body: some View {
        Button(action: onToggle) {
            Image(systemName: symbolName)
                .font(.system(size: 14))
                .foregroundStyle(state.isChecked ? Color.accentColor : Color.secondary)
                .frame(width: PluginSettingsTheme.Size.rowIcon, height: PluginSettingsTheme.Size.rowIcon)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }

    private var symbolName: String {
        switch state {
        case .allSelected:
            return "checkmark.square.fill"
        case .partiallySelected:
            return "minus.square.fill"
        case .noneSelected, .unavailable:
            return "square"
        }
    }
}
