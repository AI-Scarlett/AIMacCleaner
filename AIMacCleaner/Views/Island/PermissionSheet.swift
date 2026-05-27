import SwiftUI

struct PermissionSheetView: View {
    @EnvironmentObject var localizer: Localizer
    let permission: PendingPermission
    let session: SessionState
    let onDecision: (PermissionDecision) -> Void

    @State private var alwaysAllow: Bool = false
    @State private var reason: String = ""

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 8) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(.orange)

                Text(localizer.agentPermissionRequest)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Agent \(session.agentType) \(localizer.agentWantsToUseTool) **\(permission.toolName)**")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                if let diff = permission.diff, !diff.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(localizer.agentChanges + ":")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(diff)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.primary)
                            .padding(6)
                            .background(.black.opacity(0.06))
                            .cornerRadius(6)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
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

                Toggle(localizer.agentAlwaysAllowTool, isOn: $alwaysAllow)
                    .font(.system(size: 11))
                    .toggleStyle(.checkbox)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 8) {
                Button(action: { onDecision(.deny) }) {
                    Text(localizer.agentDeny)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.red.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)

                Button(action: {
                    let decision = alwaysAllow
                        ? PermissionDecision.allowAlways(reason: reason.isEmpty ? nil : reason)
                        : .allow
                    onDecision(decision)
                }) {
                    Text(localizer.agentAllow)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.green)
                        .cornerRadius(8)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}
