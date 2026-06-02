import SwiftUI

struct PlanApprovalSheetView: View {
    @EnvironmentObject var localizer: Localizer
    let plan: PendingPlan
    let session: SessionState
    let onResponse: (String, String?) -> Void
    let onDefer: () -> Void

    @State private var customMessage: String = ""

    var body: some View {
        VStack(spacing: 0) {
            compactHeader

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    Text(plan.content)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(.black.opacity(0.05))
                        .cornerRadius(8)

                    if !plan.permissions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(localizer.agentRequestedPermissions + ":")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(.secondary)
                            FlowLayout(spacing: 4) {
                                ForEach(plan.permissions, id: \.self) { perm in
                                    HStack(spacing: 3) {
                                        Image(systemName: permissionIcon(perm))
                                            .font(.system(size: 8))
                                        Text(perm)
                                            .font(.system(size: 10))
                                    }
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.orange.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                        }
                    }

                    if !plan.attachments.isEmpty {
                        ApprovalAttachmentStrip(attachments: plan.attachments)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            Divider()

            VStack(spacing: 6) {
                HStack(spacing: 8) {
                    Button(action: { onResponse("reject", customMessage.isEmpty ? nil : customMessage) }) {
                        Text(localizer.agentReject)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.red.opacity(0.1))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)

                    Button(action: { onResponse("approve", customMessage.isEmpty ? nil : customMessage) }) {
                        Text(localizer.agentApprove)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .background(.green)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }

                Button(action: { onResponse("modify", customMessage.isEmpty ? nil : customMessage) }) {
                    Text(localizer.agentModifyApprove)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.blue)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.blue.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: onDefer) {
                    Text(localizer.agentDecideLater)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.secondary.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                TextField(localizer.agentFeedbackPlaceholder, text: $customMessage)
                    .textFieldStyle(.plain)
                    .font(.system(size: 11))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.primary.opacity(0.06))
                    .cornerRadius(6)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .onAppear(perform: resetInput)
        .onChange(of: planIdentity) { _ in
            resetInput()
        }
    }

    private var planIdentity: String {
        "\(session.id)|\(plan.title)|\(plan.content)"
    }

    private func resetInput() {
        customMessage = ""
    }

    private var compactHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "list.clipboard.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.cyan)
                .frame(width: 24, height: 24)
                .background(.cyan.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 1) {
                Text(plan.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(localizer.agentCenterPlan)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private func permissionIcon(_ perm: String) -> String {
        let lower = perm.lowercased()
        if lower.contains("file") || lower.contains("write") || lower.contains("delete") {
            return "doc.fill"
        }
        if lower.contains("read") {
            return "book.fill"
        }
        if lower.contains("execute") || lower.contains("run") || lower.contains("shell") {
            return "terminal.fill"
        }
        if lower.contains("network") || lower.contains("internet") {
            return "network"
        }
        if lower.contains("process") {
            return "cpu"
        }
        return "lock.fill"
    }
}
