import SwiftUI
import AppKit

struct PermissionSheetView: View {
    @EnvironmentObject var localizer: Localizer
    let permission: PendingPermission
    let session: SessionState
    let onDecision: (PermissionDecision) -> Void

    @State private var reason: String = ""
    @State private var isDenyInputVisible: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    if let diff = permission.diff, !diff.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizer.agentChanges + ":")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text(diff)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.primary)
                                .padding(7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.black.opacity(0.06))
                                .cornerRadius(6)
                        }
                    }

                    if let options = permission.options, !options.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizer.agentOptions + ":")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 6) {
                                ForEach(options, id: \.self) { opt in
                                    Text(opt)
                                        .font(.system(size: 10))
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 3)
                                        .background(.blue.opacity(0.1))
                                        .cornerRadius(4)
                                }
                            }
                        }
                    }

                    if !permission.attachments.isEmpty {
                        ApprovalAttachmentStrip(attachments: permission.attachments)
                    }

                    if permission.requiresExternalHandling {
                        externalHandlingHint
                    }

                    if isDenyInputVisible {
                        denyInput
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            VStack(spacing: 6) {
                if permission.requiresExternalHandling {
                    HStack(spacing: 8) {
                        decisionButton(
                            title: localizer.agentOpenSourceApp,
                            color: .blue,
                            filled: true
                        ) {
                            onDecision(.openExternal)
                        }

                        decisionButton(
                            title: localizer.agentMarkHandled,
                            color: .secondary,
                            filled: false
                        ) {
                            onDecision(.externalHandled)
                        }
                    }
                } else if isDenyInputVisible {
                    HStack(spacing: 8) {
                        decisionButton(
                            title: localizer.agentCancel,
                            color: .secondary,
                            filled: false
                        ) {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                isDenyInputVisible = false
                            }
                        }

                        decisionButton(
                            title: localizer.agentPermissionNoWithReason,
                            color: .red,
                            filled: true
                        ) {
                            onDecision(.deny(reason: normalizedReason))
                        }
                    }
                } else {
                    HStack(spacing: 8) {
                        decisionButton(
                            title: localizer.agentPermissionYes,
                            color: .green,
                            filled: false
                        ) {
                            onDecision(.allow)
                        }

                        decisionButton(
                            title: localizer.agentPermissionYesAlways,
                            color: .green,
                            filled: true
                        ) {
                            onDecision(.allowAlways(reason: normalizedReason))
                        }

                        decisionButton(
                            title: localizer.agentPermissionNo,
                            color: .red,
                            filled: false
                        ) {
                            withAnimation(.spring(response: 0.24, dampingFraction: 0.86)) {
                                isDenyInputVisible = true
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .onAppear(perform: resetInput)
        .onChange(of: permissionIdentity) { _ in
            resetInput()
        }
    }

    private var permissionIdentity: String {
        "\(session.id)|\(permission.toolUseId ?? "")|\(permission.toolName)"
    }

    private func resetInput() {
        reason = ""
        isDenyInputVisible = false
    }

    private var externalHandlingHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "arrow.up.forward.app.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 22, height: 22)
                .background(.blue.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 2) {
                Text(localizer.agentExternalApprovalTitle)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(permission.externalActionHint ?? localizer.agentExternalApprovalHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(.blue.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.orange)
                .frame(width: 24, height: 24)
                .background(.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(localizer.agentPermissionRequest)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("\(session.agentType) \(localizer.agentWantsToUseTool) \(permission.toolName)")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var normalizedReason: String? {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private var denyInput: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(localizer.agentDenyReasonOrInstruction)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            ZStack(alignment: .leading) {
                TextEditor(text: $reason)
                    .font(.system(size: 11))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 38, maxHeight: 48)
                    .padding(4)
                    .background(.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(.primary.opacity(0.08), lineWidth: 1)
                    )

                if reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(localizer.agentDenyReasonPlaceholder)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
            }
        }
    }

    private func decisionButton(title: String, color: Color, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? .white : color)
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(filled ? color : color.opacity(0.11))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(color.opacity(filled ? 0 : 0.2), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct ApprovalAttachmentStrip: View {
    @EnvironmentObject var localizer: Localizer
    let attachments: [ApprovalAttachment]

    private var imageAttachments: [ApprovalAttachment] {
        attachments.filter(\.isImage)
    }

    var body: some View {
        if !imageAttachments.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text(localizer.agentDesignPreview)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(imageAttachments) { attachment in
                            ApprovalAttachmentCard(attachment: attachment)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct ApprovalAttachmentCard: View {
    @EnvironmentObject var localizer: Localizer
    let attachment: ApprovalAttachment

    private var image: NSImage? {
        NSImage(contentsOfFile: attachment.path)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 116, height: 64)
                        .clipped()
                } else {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 18, weight: .semibold))
                        Text(localizer.agentImageMissing)
                            .font(.system(size: 9, weight: .medium))
                            .multilineTextAlignment(.center)
                    }
                    .foregroundStyle(.secondary)
                    .frame(width: 116, height: 64)
                }
            }
            .background(.black.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            )

            Text(attachment.displayName)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 116, alignment: .leading)
                .help(attachment.path)

            HStack(spacing: 6) {
                attachmentActionButton(localizer.agentOpenImage, icon: "arrow.up.forward.app") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: attachment.path))
                }
                attachmentActionButton(localizer.agentRevealImage, icon: "folder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: attachment.path)])
                }
            }
        }
        .padding(7)
        .background(.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private func attachmentActionButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 24, height: 22)
                .background(Color.accentColor.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .help(title)
    }
}
