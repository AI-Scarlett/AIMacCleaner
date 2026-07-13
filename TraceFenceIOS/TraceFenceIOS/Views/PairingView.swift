import SwiftUI
import UIKit

struct PairingView: View {
    @EnvironmentObject private var store: ConnectionStore
    @Environment(\.appLanguage) private var language
    @Binding var selectedTab: AppTab

    @State private var pairingText = ""
    @State private var endpoint = ""
    @State private var token = ""
    @State private var scannerSheet: ScannerSheet?
    @State private var authError: String?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("从 Mac 导入")
                        .font(.headline)
                    Text("Mac 端进入设置，打开 iOS 远程控制，点击“复制 iOS 配对信息”，再粘贴到这里。")
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    TextEditor(text: $pairingText)
                        .font(.footnote.monospaced())
                        .frame(minHeight: 150)
                        .padding(8)
                        .background(Color.secondary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    HStack {
                        Button {
                            scannerSheet = ScannerSheet()
                        } label: {
                            Label("扫码", systemImage: "qrcode.viewfinder")
                        }

                        Button {
                            pairingText = UIPasteboard.general.string ?? ""
                        } label: {
                            Label("粘贴", systemImage: "doc.on.clipboard")
                        }

                        Spacer()

                        Button {
                            Task {
                                await authenticatedConnect {
                                    await store.connectWithPairingText(pairingText)
                                }
                            }
                        } label: {
                            Label("导入并测试", systemImage: "checkmark.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(pairingText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("手动连接") {
                TextField("http://192.168.1.20:17896", text: $endpoint)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("配对密钥", text: $token)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                Button {
                    Task {
                        await authenticatedConnect {
                            await store.connectManually(endpoint: endpoint, token: token)
                        }
                    }
                } label: {
                    Label("保存并测试连接", systemImage: "network")
                }
                .disabled(endpoint.isEmpty || token.isEmpty)
            }

            Section("当前连接") {
                if let connection = store.connection {
                    LabeledContent("Mac 地址", value: connection.endpoint)
                    if let lastResolved = connection.lastResolvedEndpoint, lastResolved != connection.endpoint {
                        LabeledContent("上次成功", value: lastResolved)
                    }
                    LabeledContent("密钥", value: connection.maskedToken)
                    if let channel = connection.channelHint {
                        LabeledContent("渠道", value: (channel == "appStore" ? "上架版" : "官网版").tfLocalized)
                    }
                    if !connection.prioritizedAccessEndpoints.isEmpty {
                        DisclosureGroup("自动试连地址 \(connection.prioritizedAccessEndpoints.count)") {
                            ForEach(connection.prioritizedAccessEndpoints.prefix(8)) { endpoint in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(endpoint.label.tfLocalized)
                                        .font(.subheadline.weight(.semibold))
                                    Text(endpoint.url)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(TraceFenceDesign.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                    if let lastSucceededAt = endpoint.lastSucceededAt {
                                        Text(language.text(
                                            zh: "成功连接 \(lastSucceededAt.tfShortTimeText)",
                                            en: "Connected successfully at \(lastSucceededAt.tfShortTimeText)",
                                            zhHant: "成功連線於 \(lastSucceededAt.tfShortTimeText)",
                                            ja: "\(lastSucceededAt.tfShortTimeText) に接続成功",
                                            ko: "\(lastSucceededAt.tfShortTimeText)에 연결 성공",
                                            mt: "Konness b'suċċess fi \(lastSucceededAt.tfShortTimeText)"
                                        ))
                                            .font(.caption2)
                                            .foregroundStyle(TraceFenceDesign.success)
                                    }
                                }
                                .padding(.vertical, 3)
                            }
                        }
                    }
                    Button(role: .destructive) {
                        store.clearConnection()
                    } label: {
                        Label("移除这台 Mac", systemImage: "trash")
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("还没有保存 Mac。")
                            .foregroundStyle(TraceFenceDesign.secondary)
                        Button {
                            store.enableReviewDemo()
                            selectedTab = .overview
                        } label: {
                            Label(
                                language.text(zh: "查看只读演示", en: "View Read-only Demo", zhHant: "查看唯讀示範", ja: "読み取り専用デモを見る", ko: "읽기 전용 데모 보기", mt: "Ara Demo Read-only"),
                                systemImage: "play.rectangle"
                            )
                        }
                    }
                }
            }

            if case .failed(let message) = store.state {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(TraceFenceDesign.danger)
                }
            }

            if let authError {
                Section {
                    Label(authError, systemImage: "lock.trianglebadge.exclamationmark")
                        .foregroundStyle(TraceFenceDesign.danger)
                }
            }
        }
        .navigationTitle("配对 Mac")
        .scrollContentBackground(.hidden)
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .sheet(item: $scannerSheet) { _ in
            PairingScannerSheet { code in
                pairingText = code
                Task {
                    await authenticatedConnect {
                        await store.connectWithPairingText(code)
                    }
                }
            }
        }
        .task {
            if let connection = store.connection {
                endpoint = connection.endpoint
                token = connection.token
            }
        }
    }

    private func authenticatedConnect(_ action: @escaping () async -> Void) async {
        do {
            try await DeviceAuthentication.authorize(
                reason: language.text(
                    zh: "验证身份后连接 TraceFence Mac 控制端。",
                    en: "Authenticate to connect to the TraceFence control service on your Mac.",
                    zhHant: "驗證身分後連接 Mac 上的 TraceFence 控制服務。",
                    ja: "認証して Mac 上の TraceFence 制御サービスに接続します。",
                    ko: "인증 후 Mac의 TraceFence 제어 서비스에 연결합니다.",
                    mt: "Awtentika biex tikkonnettja mas-servizz ta' kontroll TraceFence fuq il-Mac."
                )
            )
            authError = nil
            await action()
            if store.status != nil {
                selectedTab = .overview
            }
        } catch {
            authError = error.localizedDescription
        }
    }
}

private struct ScannerSheet: Identifiable {
    let id = UUID()
}

private struct PairingScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onCode: (String) -> Void

    var body: some View {
        NavigationStack {
            QRCodeScannerView { code in
                onCode(code)
                dismiss()
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("扫描配对码")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("关闭") { dismiss() }
                }
            }
        }
    }
}
