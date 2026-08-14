import AppKit
import MacToolsPluginKit
import SwiftUI

struct CodexMediaCleanupDetailView: View {
    @ObservedObject var controller: CodexMediaCleanupController
    let localization: PluginLocalization
    @State private var showsRepairConfirmation = false

    private var snapshot: CodexMediaCleanupSnapshot { controller.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            safetyNotice
            scopeAndActions
            if let report = snapshot.scanReport { scanSummary(report) }
            if let report = snapshot.repairReport { repairSummary(report) }
            if let error = snapshot.errorMessage { errorCard(error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            "备份后修复 Codex 会话？",
            isPresented: $showsRepairConfirmation,
            titleVisibility: .visible
        ) {
            Button("等待 Codex 退出并开始修复") {
                controller.repairWhenCodexStops()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("TraceFence 不会强制退出 Codex。插件会独立等待进程和文件句柄关闭，逐文件校验备份后再原子替换。")
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "photo.stack.fill")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.purple)
                .frame(width: 48, height: 48)
                .background(.purple.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text("Codex 媒体整理")
                    .font(.title2.bold())
                Text("TraceFence PluginKit 4 原生插件 · 本机离线处理")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            phaseBadge
        }
    }

    private var phaseBadge: some View {
        Label(phaseText, systemImage: snapshot.isBusy ? "clock.arrow.circlepath" : "checkmark.shield")
            .font(.caption.bold())
            .foregroundStyle(snapshot.isBusy ? .orange : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
    }

    private var safetyNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("兼容性优先", systemImage: "shield.checkered")
                .font(.headline)
            Text("有效模型历史必须保留 Responses API 可接受的 data:image Base64。插件只外置已被 compaction 取代的副本和非模型事件副本；如果有效历史被错误改成 file://，会从已校验的 SHA-256 原始文件恢复 Base64。")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("因此在 Codex 当前接口下，“磁盘里绝对只留一份、有效历史也不留 Base64”会再次触发 invalid image_url，本插件不会采用这种不兼容模式。")
                .font(.caption)
                .foregroundStyle(.orange)
        }
        .padding(14)
        .background(.purple.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.purple.opacity(0.18)))
    }

    private var scopeAndActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle("包括已归档任务", isOn: Binding(
                    get: { snapshot.includeArchivedSessions },
                    set: { controller.setIncludeArchivedSessions($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(snapshot.isBusy)
                Spacer()
                if snapshot.isBusy {
                    Button("停止", role: .cancel) { controller.cancelCurrentOperation() }
                }
                Button("只读扫描") { controller.scan() }
                    .disabled(!controller.canScan)
                Button("备份并修复") { showsRepairConfirmation = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!controller.canRepair)
            }
            if snapshot.phase == .waitingForCodex {
                Label("正在等待 ChatGPT/Codex 完全退出；TraceFence 插件仍在运行。", systemImage: "hourglass")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if snapshot.phase == .repairing {
                ProgressView(value: Double(snapshot.completedFiles), total: Double(max(snapshot.totalFiles, 1)))
                Text(snapshot.currentFile)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func scanSummary(_ report: CodexMediaScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("扫描结果").font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                metric("会话文件", "\(report.scannedFiles)", "doc.text.magnifyingglass")
                metric("需要处理", "\(report.affectedFiles)", "wrench.and.screwdriver")
                metric("可外置副本", "\(report.reclaimableOccurrences)", "square.stack.3d.down.right")
                metric("有效历史保留", "\(report.retainedEffectiveOccurrences)", "checkmark.shield")
                metric("无效 image_url", "\(report.invalidEffectiveFileURLs)", "exclamationmark.triangle")
                metric("预计可收回", Self.bytes(report.estimatedReclaimableBytes), "internaldrive")
            }
            if report.malformedFiles > 0 || report.missingMediaObjects > 0 {
                Text("有 \(report.malformedFiles) 个损坏 JSONL、\(report.missingMediaObjects) 个缺失或未通过校验的媒体对象；这些文件会跳过，不会冒险改写。")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func repairSummary(_ report: CodexMediaRepairReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("最近一次修复", systemImage: "checkmark.seal.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("已修复 \(report.repairedFileCount) 个会话，外置 \(report.replacementCount) 个过期副本，恢复 \(report.restorationCount) 个 API 不兼容引用，收回约 \(Self.bytes(report.reclaimedBytes))。")
            HStack {
                Button("打开报告") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: report.reportPath)])
                }
                if let backup = report.files.first?.backupPath {
                    Button("查看备份") {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backup)])
                    }
                }
            }
            if !report.skippedFiles.isEmpty {
                Text("\(report.skippedFiles.count) 个文件因占用、损坏或安全校验失败而跳过。详情见报告。")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private func errorCard(_ message: String) -> some View {
        Label(message, systemImage: "xmark.octagon.fill")
            .font(.callout)
            .foregroundStyle(.red)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.red.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
    }

    private func metric(_ title: String, _ value: String, _ icon: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.purple)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.headline.monospacedDigit())
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(10)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 9))
    }

    private var phaseText: String {
        switch snapshot.phase {
        case .idle: "待扫描"
        case .scanning: "扫描中"
        case .scanned: "扫描完成"
        case .waitingForCodex: "等待 Codex"
        case .repairing: "修复中"
        case .completed: "已完成"
        }
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
