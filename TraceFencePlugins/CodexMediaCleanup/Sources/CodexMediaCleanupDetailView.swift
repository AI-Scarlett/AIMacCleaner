import AppKit
import MacToolsPluginKit
import SwiftUI

struct CodexMediaCleanupDetailView: View {
    @ObservedObject var controller: CodexMediaCleanupController
    let localization: PluginLocalization
    @State private var pendingOperation: CodexMediaOperation?
    @State private var selectedBackupIDs: Set<CodexMediaBackupBatch.ID> = []
    @State private var isConfirmingBackupDeletion = false

    private var snapshot: CodexMediaCleanupSnapshot { controller.snapshot }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            productDescription
            workflow
            safetyNotice
            scopeAndActions
            if snapshot.isBusy { progressCard }
            if let report = snapshot.scanReport { scanSummary(report) }
            if let report = snapshot.repairReport { operationSummary(report) }
            backupManagement
            if snapshot.requiresRestartValidation { restartValidation }
            operationLog
            if let error = snapshot.errorMessage { errorCard(error) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .confirmationDialog(
            confirmationTitle,
            isPresented: Binding(
                get: { pendingOperation != nil },
                set: { if !$0 { pendingOperation = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(t("confirm.start", "我已暂停任务；等待 Codex 完全退出后执行")) {
                guard let operation = pendingOperation else { return }
                pendingOperation = nil
                controller.run(operation)
            }
            Button(t("action.cancel", "取消"), role: .cancel) { pendingOperation = nil }
        } message: {
            Text(t(
                "confirm.message",
                "请先暂停所有 Codex 任务并完全退出客户端。TraceFence 不会强制结束进程；它会等待 Codex 和文件句柄全部关闭，逐文件建立并校验备份，再原子替换。完成后必须重新启动 Codex 并验证历史对话。"
            ))
        }
        .confirmationDialog(
            backupDeletionTitle,
            isPresented: $isConfirmingBackupDeletion,
            titleVisibility: .visible
        ) {
            Button(t("backup.delete.confirm", "永久删除所选备份"), role: .destructive) {
                let selected = selectedBackupIDs
                selectedBackupIDs.removeAll()
                controller.deleteBackups(ids: selected)
            }
            Button(t("action.cancel", "取消"), role: .cancel) {}
        } message: {
            Text(t(
                "backup.delete.warning",
                "删除后将无法用这些批次恢复修复前的 Codex 会话。当前会话和媒体对象不会被删除；此操作不可撤销。"
            ))
        }
        .onChange(of: snapshot.backupBatches.map(\.id)) { _, validIDs in
            selectedBackupIDs.formIntersection(Set(validIDs))
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
                Text(t("metadata.title", "Codex 媒体整理"))
                    .font(.title2.bold())
                Text(t("detail.subtitle", "TraceFence PluginKit 4 原生插件 · 本机离线处理"))
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

    private var productDescription: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(t("description.title", "这个插件解决什么问题"), systemImage: "sparkles.rectangle.stack")
                .font(.headline)
            Text(t(
                "metadata.description",
                "清理重复媒体文件，降低磁盘空间占用；并修复会话记录中的无效 image_url，避免历史对话再次触发图片地址格式错误。"
            ))
                .font(.callout)
            Text("Invalid 'input[51].content[2].image_url'. Expected a valid URL, but got a value with an invalid format.")
                .font(.caption.monospaced())
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.red.opacity(0.055), in: RoundedRectangle(cornerRadius: 9))
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
    }

    private var workflow: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("workflow.title", "完整工作流")).font(.headline)
            workflowStep(
                number: 1,
                title: t("workflow.scan", "扫描"),
                detail: t("workflow.scanDetail", "只读分析重复媒体、可释放空间和无效 image_url。"),
                complete: snapshot.scanReport != nil
            )
            workflowStep(
                number: 2,
                title: t("workflow.pause", "暂停任务并完全退出 Codex"),
                detail: t("workflow.pauseDetail", "所有写入操作都会等待进程和会话文件句柄关闭。"),
                complete: snapshot.lastOperation != nil || snapshot.requiresRestartValidation
            )
            workflowStep(
                number: 3,
                title: t("workflow.execute", "选择清理、修复或清理并修复"),
                detail: t("workflow.executeDetail", "逐文件备份、SHA-256 校验、原子替换；失败自动回滚。"),
                complete: snapshot.lastOperation != nil
            )
            workflowStep(
                number: 4,
                title: t("workflow.validate", "完全重启 Codex 并验证历史对话"),
                detail: t("workflow.validateDetail", "打开包含图片的历史对话，确认图片可见并能继续发送消息。"),
                complete: snapshot.historyConversationValidated
            )
        }
        .padding(14)
        .background(.blue.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.blue.opacity(0.12)))
    }

    private func workflowStep(number: Int, title: String, detail: String, complete: Bool) -> some View {
        HStack(alignment: .top, spacing: 11) {
            ZStack {
                Circle().fill(complete ? Color.green : Color.secondary.opacity(0.14))
                if complete {
                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                } else {
                    Text("\(number)").font(.caption.bold()).foregroundStyle(.secondary)
                }
            }
            .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var safetyNotice: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label(t("safety.title", "兼容性与数据安全"), systemImage: "shield.checkered")
                .font(.headline)
            Text(t(
                "safety.body",
                "有效模型历史必须保留 Responses API 可接受的 data:image Base64。清理只外置已被 compaction 取代的副本和非模型事件副本；修复会把有效历史中不兼容的 file:// 引用恢复为经过 SHA-256 校验的 Base64。"
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
            Text(t(
                "safety.warning",
                "插件不删除原始媒体对象，不联网、不上传会话内容。损坏、缺失、仍在占用或未通过校验的文件会直接跳过。"
            ))
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
                Text(t("actions.title", "操作")).font(.headline)
                Spacer()
                Toggle(t("scope.archived", "包括已归档任务"), isOn: Binding(
                    get: { snapshot.includeArchivedSessions },
                    set: { controller.setIncludeArchivedSessions($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(snapshot.isBusy)
                if snapshot.isBusy {
                    Button(t("action.stop", "停止"), role: .cancel) { controller.cancelCurrentOperation() }
                }
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                actionTile(
                    title: t("action.readOnlyScan", "扫描"),
                    detail: t("action.scanDetail", "只读统计，不改文件"),
                    icon: "magnifyingglass",
                    color: .blue,
                    enabled: controller.canScan
                ) { controller.scan() }
                actionTile(
                    title: t("operation.cleanup", "清理"),
                    detail: cleanupActionDetail,
                    icon: "internaldrive",
                    color: .orange,
                    enabled: controller.canCleanup
                ) { pendingOperation = .cleanup }
                actionTile(
                    title: t("operation.repair", "修复"),
                    detail: repairActionDetail,
                    icon: "wrench.and.screwdriver",
                    color: .purple,
                    enabled: controller.canRepair
                ) { pendingOperation = .repair }
                actionTile(
                    title: t("operation.cleanupAndRepair", "清理并修复"),
                    detail: combinedActionDetail,
                    icon: "checkmark.shield",
                    color: .green,
                    enabled: controller.canCleanupAndRepair
                ) { pendingOperation = .cleanupAndRepair }
            }

            if snapshot.scanReport == nil {
                Label(t("actions.scanFirst", "请先运行扫描，TraceFence 才会开放对应操作。"), systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Label(t(
                    "actions.pauseReminder",
                    "实施清理或修复前，请暂停全部 Codex 任务并完全退出客户端。"
                ), systemImage: "pause.circle.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 12))
    }

    private func actionTile(
        title: String,
        detail: String,
        icon: String,
        color: Color,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? color : .secondary)
                    .frame(width: 30, height: 30)
                    .background(color.opacity(enabled ? 0.11 : 0.04), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.callout.weight(.semibold))
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                Spacer(minLength: 0)
            }
            .padding(11)
            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
            .background(.background.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(color.opacity(enabled ? 0.18 : 0.06)))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.55)
    }

    private var progressCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(phaseText, systemImage: "clock.arrow.circlepath")
                    .font(.headline)
                Spacer()
                if snapshot.totalFiles > 0, snapshot.phase != .waitingForCodex {
                    Text("\(snapshot.completedFiles)/\(snapshot.totalFiles)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            if snapshot.phase == .waitingForCodex {
                ProgressView()
                Text(t(
                    "status.waitingForCodex",
                    "正在等待 Codex/ChatGPT 完全退出。请先保存工作并暂停所有任务；TraceFence 不会强制退出客户端。"
                ))
                    .font(.callout)
                    .foregroundStyle(.orange)
            } else {
                ProgressView(
                    value: Double(snapshot.completedFiles),
                    total: Double(max(snapshot.totalFiles, 1))
                )
                if !snapshot.currentFile.isEmpty {
                    Text(snapshot.currentFile)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(14)
        .background(.orange.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private func scanSummary(_ report: CodexMediaScanReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(t("scan.title", "扫描结果")).font(.headline)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                metric(t("metric.sessions", "会话文件"), "\(report.scannedFiles)", "doc.text.magnifyingglass")
                metric(t("metric.affected", "需要处理"), "\(report.affectedFiles)", "wrench.and.screwdriver")
                metric(t("metric.externalizable", "可清理副本"), "\(report.reclaimableOccurrences)", "square.stack.3d.down.right")
                metric(t("metric.retained", "有效历史保留"), "\(report.retainedEffectiveOccurrences)", "checkmark.shield")
                metric(t("metric.invalidURL", "无效 image_url"), "\(report.invalidEffectiveFileURLs)", "exclamationmark.triangle")
                metric(t("metric.reclaimable", "预计可释放"), Self.bytes(report.estimatedReclaimableBytes), "internaldrive")
            }
            if report.malformedFiles > 0 || report.missingMediaObjects > 0 {
                Text(localization.format(
                    "scan.warningFormat",
                    defaultValue: "有 %lld 个损坏 JSONL、%lld 个缺失或未通过校验的媒体对象；这些文件会跳过，不会冒险改写。",
                    Int64(report.malformedFiles),
                    Int64(report.missingMediaObjects)
                ))
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    private func operationSummary(_ report: CodexMediaRepairReport) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(
                localization.format(
                    "result.titleFormat",
                    defaultValue: "最近一次操作：%@",
                    operationName(report.operation)
                ),
                systemImage: "checkmark.seal.fill"
            )
                .font(.headline)
                .foregroundStyle(.green)
            Text(localization.format(
                "repair.summaryFormat",
                defaultValue: "处理 %lld 个会话，清理 %lld 个重复媒体副本，修复 %lld 个 API 不兼容引用，释放约 %@。",
                Int64(report.repairedFileCount),
                Int64(report.replacementCount),
                Int64(report.restorationCount),
                Self.bytes(report.reclaimedBytes)
            ))
            HStack {
                Button(t("action.openReport", "打开报告")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: report.reportPath)])
                }
                if let backup = report.files.first?.backupPath {
                    Button(t("action.showBackup", "查看备份")) {
                        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: backup)])
                    }
                }
            }
            if !report.skippedFiles.isEmpty {
                Text(localization.format(
                    "repair.skippedFormat",
                    defaultValue: "%lld 个文件因占用、损坏或安全校验失败而跳过。详情见报告。",
                    Int64(report.skippedFiles.count)
                ))
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(14)
        .background(.green.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
    }

    private var backupManagement: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Label(t("backup.title", "修复备份"), systemImage: "archivebox.fill")
                    .font(.headline)
                Text(localization.format(
                    "backup.totalFormat",
                    defaultValue: "%lld 批 · 约 %@",
                    Int64(snapshot.backupBatches.count),
                    Self.bytes(snapshot.backupAllocatedBytes)
                ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    if selectedBackupIDs.count == snapshot.backupBatches.count {
                        selectedBackupIDs.removeAll()
                    } else {
                        selectedBackupIDs = Set(snapshot.backupBatches.map(\.id))
                    }
                } label: {
                    Text(selectedBackupIDs.count == snapshot.backupBatches.count && !snapshot.backupBatches.isEmpty
                        ? t("backup.deselectAll", "取消全选")
                        : t("backup.selectAll", "全选"))
                }
                .disabled(!controller.canManageBackups || snapshot.backupBatches.isEmpty)

                Button {
                    controller.refreshBackups()
                } label: {
                    Label(t("backup.refresh", "刷新"), systemImage: "arrow.clockwise")
                }
                .disabled(!controller.canManageBackups)

                Button(role: .destructive) {
                    isConfirmingBackupDeletion = true
                } label: {
                    Label(
                        localization.format(
                            "backup.deleteSelectedFormat",
                            defaultValue: "永久删除 %lld 批",
                            Int64(selectedBackupIDs.count)
                        ),
                        systemImage: "trash"
                    )
                }
                .disabled(!controller.canManageBackups || selectedBackupIDs.isEmpty)
            }

            Text(t(
                "backup.description",
                "每次清理或修复前创建的完整回滚点。确认历史对话正常后，可手动永久删除旧批次释放空间；默认不会自动选择或删除。"
            ))
                .font(.callout)
                .foregroundStyle(.secondary)

            if snapshot.isScanningBackups || snapshot.isDeletingBackups {
                HStack(spacing: 9) {
                    ProgressView().controlSize(.small)
                    Text(snapshot.isDeletingBackups
                        ? t("backup.deleting", "正在校验并永久删除所选备份…")
                        : t("backup.scanning", "正在统计备份的物理占用…"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else if snapshot.backupBatches.isEmpty {
                Label(t("backup.empty", "没有可管理的修复备份"), systemImage: "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(snapshot.backupBatches) { batch in
                        backupRow(batch)
                        if batch.id != snapshot.backupBatches.last?.id { Divider() }
                    }
                }
                .background(.background.opacity(0.52), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.secondary.opacity(0.12)))
            }

            if let result = snapshot.lastBackupCleanupResult {
                Label(
                    localization.format(
                        "backup.resultFormat",
                        defaultValue: "已删除 %lld 批、%lld 个文件（约 %@）；APFS 即时增加 %@ 可用空间。",
                        Int64(result.removedBatchCount),
                        Int64(result.removedFileCount),
                        Self.bytes(result.removedAllocatedBytes),
                        Self.bytes(result.immediatelyReclaimedBytes)
                    ),
                    systemImage: "checkmark.circle.fill"
                )
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        }
        .padding(14)
        .background(.orange.opacity(0.045), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.orange.opacity(0.14)))
    }

    private func backupRow(_ batch: CodexMediaBackupBatch) -> some View {
        HStack(alignment: .top, spacing: 11) {
            Toggle("", isOn: Binding(
                get: { selectedBackupIDs.contains(batch.id) },
                set: { selected in
                    if selected { selectedBackupIDs.insert(batch.id) }
                    else { selectedBackupIDs.remove(batch.id) }
                }
            ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .disabled(!controller.canManageBackups)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 7) {
                    Text(batch.id).font(.callout.weight(.semibold)).textSelection(.enabled)
                    Text(backupStatusText(batch.reportStatus))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(backupStatusColor(batch.reportStatus))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(backupStatusColor(batch.reportStatus).opacity(0.1), in: Capsule())
                }
                Text(localization.format(
                    "backup.rowDetailFormat",
                    defaultValue: "%@ · %lld 个文件 · %@",
                    Self.bytes(batch.allocatedBytes),
                    Int64(batch.fileCount),
                    Self.date(batch.createdAt)
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(t("backup.show", "查看")) {
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: batch.path)])
            }
            if let reportPath = batch.reportPath {
                Button(t("backup.showReport", "报告")) {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: reportPath)])
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var selectedBackupBytes: Int64 {
        snapshot.backupBatches
            .filter { selectedBackupIDs.contains($0.id) }
            .reduce(0) { $0 + max($1.allocatedBytes, 0) }
    }

    private var backupDeletionTitle: String {
        localization.format(
            "backup.delete.titleFormat",
            defaultValue: "永久删除 %lld 个备份批次（约 %@）？",
            Int64(selectedBackupIDs.count),
            Self.bytes(selectedBackupBytes)
        )
    }

    private func backupStatusText(_ status: CodexMediaBackupReportStatus) -> String {
        switch status {
        case .completed: t("backup.status.completed", "报告完整")
        case .interrupted: t("backup.status.interrupted", "操作中断")
        case .unavailable: t("backup.status.unavailable", "无报告")
        }
    }

    private func backupStatusColor(_ status: CodexMediaBackupReportStatus) -> Color {
        switch status {
        case .completed: .green
        case .interrupted: .orange
        case .unavailable: .secondary
        }
    }

    private var restartValidation: some View {
        VStack(alignment: .leading, spacing: 11) {
            Label(t("validation.title", "必须完成：重启与历史对话验证"), systemImage: "arrow.clockwise.circle.fill")
                .font(.headline)
                .foregroundStyle(snapshot.historyConversationValidated ? .green : .orange)
            Text(t(
                "validation.body",
                "写入阶段已经在 Codex 完全退出后完成。现在请启动全新的客户端进程，打开一个包含图片的历史对话，确认图片正常显示，并继续发送一条消息验证会话可用。"
            ))
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                Button {
                    controller.restartCodexClient()
                } label: {
                    Label(
                        snapshot.codexRestarted
                            ? t("validation.restarted", "Codex 已重新启动")
                            : t("validation.restart", "完全重启 Codex"),
                        systemImage: snapshot.codexRestarted ? "checkmark.circle.fill" : "arrow.clockwise"
                    )
                }
                .disabled(snapshot.codexRestarted)

                Button {
                    controller.markHistoryConversationValidated()
                } label: {
                    Label(
                        snapshot.historyConversationValidated
                            ? t("validation.done", "历史对话已验证")
                            : t("validation.mark", "标记历史对话验证完成"),
                        systemImage: snapshot.historyConversationValidated ? "checkmark.seal.fill" : "checkmark.seal"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!snapshot.codexRestarted || snapshot.historyConversationValidated)
            }
        }
        .padding(14)
        .background((snapshot.historyConversationValidated ? Color.green : Color.orange).opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke((snapshot.historyConversationValidated ? Color.green : Color.orange).opacity(0.2))
        )
    }

    private var operationLog: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(t("log.title", "执行日志"), systemImage: "list.bullet.rectangle")
                    .font(.headline)
                Spacer()
                Text(localization.format(
                    "log.countFormat",
                    defaultValue: "%lld 条",
                    Int64(snapshot.logs.count)
                ))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if snapshot.logs.isEmpty {
                            Text(t("log.empty", "运行扫描后，这里会逐项显示时间、阶段、文件和结果。"))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        ForEach(snapshot.logs) { entry in
                            HStack(alignment: .top, spacing: 8) {
                                Text(Self.time(entry.timestamp))
                                    .foregroundStyle(.secondary)
                                Image(systemName: logIcon(entry.level))
                                    .foregroundStyle(logColor(entry.level))
                                    .frame(width: 13)
                                Text(entry.message)
                                    .foregroundStyle(entry.level == .error ? Color.red : Color.primary)
                                    .textSelection(.enabled)
                            }
                            .font(.caption.monospaced())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                    .padding(10)
                }
                .frame(minHeight: 150, maxHeight: 230)
                .background(Color.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                .onChange(of: snapshot.logs.last?.id) { _, id in
                    if let id { withAnimation { proxy.scrollTo(id, anchor: .bottom) } }
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
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

    private var cleanupActionDetail: String {
        guard let report = snapshot.scanReport else { return t("action.scanRequired", "需先扫描") }
        return localization.format(
            "action.cleanupDetailFormat",
            defaultValue: "%lld 个副本 · 约 %@",
            Int64(report.reclaimableOccurrences),
            Self.bytes(report.estimatedReclaimableBytes)
        )
    }

    private var repairActionDetail: String {
        guard let report = snapshot.scanReport else { return t("action.scanRequired", "需先扫描") }
        return localization.format(
            "action.repairDetailFormat",
            defaultValue: "%lld 个无效 image_url",
            Int64(report.invalidEffectiveFileURLs)
        )
    }

    private var combinedActionDetail: String {
        guard let report = snapshot.scanReport else { return t("action.scanRequired", "需先扫描") }
        return localization.format(
            "action.combinedDetailFormat",
            defaultValue: "%lld 个副本 + %lld 个引用",
            Int64(report.reclaimableOccurrences),
            Int64(report.invalidEffectiveFileURLs)
        )
    }

    private var confirmationTitle: String {
        guard let operation = pendingOperation else { return t("confirm.title", "确认操作") }
        return localization.format(
            "confirm.titleFormat",
            defaultValue: "暂停 Codex 后执行“%@”？",
            operationName(operation)
        )
    }

    private var phaseText: String {
        switch snapshot.phase {
        case .idle: t("phase.idle", "待扫描")
        case .scanning: t("phase.scanning", "扫描中")
        case .scanned: t("phase.scanned", "扫描完成")
        case .waitingForCodex: t("phase.waiting", "等待 Codex 完全退出")
        case .cleaning: t("phase.cleaning", "清理中")
        case .repairing: t("phase.repairing", "修复中")
        case .cleaningAndRepairing: t("phase.cleaningAndRepairing", "清理并修复中")
        case .completed: t("phase.completed", "处理完成")
        }
    }

    private func operationName(_ operation: CodexMediaOperation) -> String {
        switch operation {
        case .cleanup: t("operation.cleanup", "清理")
        case .repair: t("operation.repair", "修复")
        case .cleanupAndRepair: t("operation.cleanupAndRepair", "清理并修复")
        }
    }

    private func logIcon(_ level: CodexMediaLogLevel) -> String {
        switch level {
        case .info: "circle.fill"
        case .success: "checkmark.circle.fill"
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        }
    }

    private func logColor(_ level: CodexMediaLogLevel) -> Color {
        switch level {
        case .info: .blue
        case .success: .green
        case .warning: .orange
        case .error: .red
        }
    }

    private func t(_ key: String, _ defaultValue: String) -> String {
        localization.string(key, defaultValue: defaultValue)
    }

    private static func time(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private static func date(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }
}
