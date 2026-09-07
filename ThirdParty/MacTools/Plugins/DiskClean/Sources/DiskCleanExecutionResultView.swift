import SwiftUI
import MacToolsPluginKit

/// Every cleanup entry presents the same receipt; an action must never end with only
/// a disabled Clean button or estimates that imply Trash has freed disk capacity.
struct DiskCleanExecutionResultView: View {
    let result: DiskCleanExecutionResult
    let localization: PluginLocalization
    let onRescan: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(result.wasCancelled
                     ? localization.string("detail.result.stopped", defaultValue: "清理已停止，已完成的项目如下")
                     : localization.string("detail.result.title", defaultValue: "清理结果"))
                    .font(.headline)
                Spacer()
                Button(localization.string("detail.action.rescan", defaultValue: "重新扫描"), action: onRescan)
                    .buttonStyle(.bordered)
            }
            Text(localization.format(
                result.mode == .trash ? "detail.result.trashSummary" : "detail.result.deleteSummary",
                defaultValue: result.mode == .trash
                    ? "已移到废纸篓 %d 项 · 已跳过 %d 项 · 未完成 %d 项"
                    : "已删除 %d 项 · 已跳过 %d 项 · 未完成 %d 项",
                result.removedCount, result.skippedCount, result.failedCount
            ))
            Text(localization.format("detail.result.disposedEstimate", defaultValue: "已处理文件估算大小：%@", DiskCleanFormat.bytes(result.reclaimedBytes)))
                .font(.subheadline)
            if let space = result.spaceMeasurement {
                Text(localization.format("detail.result.availableBeforeAfter", defaultValue: "磁盘可用：%@ → %@", DiskCleanFormat.bytes(space.availableBefore), DiskCleanFormat.bytes(space.availableAfter)))
                    .font(.subheadline.monospacedDigit())
                Text(localization.format("detail.result.availableChange", defaultValue: "本次观测变化：%@", signedBytes(space.availableChange)))
                    .font(.subheadline.monospacedDigit())
            } else {
                Text(localization.string("detail.result.spaceUnavailable", defaultValue: "暂时无法读取磁盘可用空间；文件估算大小不代表实际释放量。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Text(result.mode == .trash
                 ? localization.string("detail.result.trashSpaceNote", defaultValue: "文件仍在废纸篓中，不会立即释放空间。本次没有清空废纸篓。")
                 : localization.string("detail.result.spaceNote", defaultValue: "可用空间受其他程序写入、APFS 快照和延迟回收影响，可能与文件估算大小不同。"))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(incompleteItems, id: \.candidateID) { item in
                Divider()
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.path).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                    Text(reason(item.outcome)).font(.caption).foregroundStyle(.orange)
                    if let stagedName = DiskCleanFormat.stagedName(of: item.outcome) {
                        Text(localization.format("detail.result.stagedName", defaultValue: "暂存名：%@", stagedName))
                            .font(.caption).textSelection(.enabled)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .diskCleanSurface(.accented)
    }

    private var incompleteItems: [DiskCleanExecutionItemResult] {
        result.itemResults.filter {
            switch $0.outcome {
            case .removed, .trashed: return false
            default: return true
            }
        }
    }

    private func signedBytes(_ bytes: Int64) -> String {
        if bytes == 0 { return "0 B" }
        return (bytes > 0 ? "+" : "−") + DiskCleanFormat.bytes(abs(bytes))
    }

    private func reason(_ outcome: DiskCleanExecutionItemResult.Outcome) -> String {
        switch outcome {
        case .changedSinceScan:
            return localization.string("detail.result.changedRetry", defaultValue: "扫描后内容已变化，未删除。请重新扫描再选择。")
        case let .skipped(safety):
            switch safety {
            case let .inUse(processName):
                return localization.format("detail.result.inUse", defaultValue: "%@ 正在使用，已跳过。关闭相关程序后重新扫描。", processName)
            case let .whitelisted(rule):
                return localization.format("detail.result.whitelisted", defaultValue: "已按保护名单跳过：%@", rule)
            case let .protected(reason), let .invalid(reason), let .requiresAdmin(reason):
                return reason
            case .allowed:
                return localization.string("detail.result.skipped", defaultValue: "已跳过")
            }
        default:
            return DiskCleanFormat.attentionGuidance(outcome, localization: localization)
        }
    }
}
