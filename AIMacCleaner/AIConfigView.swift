import SwiftUI

struct AIConfigView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = ""

    let presets: [(name: String, base: String, model: String)] = [
        ("DeepSeek", "https://api.deepseek.com", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com", "gpt-4o-mini"),
        ("Zhipu GLM", "https://open.bigmodel.cn/api/paas", "glm-4-flash"),
        ("Qwen (Tongyi)", "https://dashscope.aliyuncs.com/compatible-mode", "qwen-turbo"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("🤖 " + localizer.aiScan + " " + localizer.settings.lowercased())
                    .font(.title2).fontWeight(.bold)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text(localizer.aiSettingsDesc)
                    .font(.callout).foregroundColor(.secondary)

                Group {
                    LabeledContent(localizer.apiBase) {
                        TextField("https://api.deepseek.com", text: $apiBase)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                    }
                    LabeledContent(localizer.apiKey) {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                    }
                    LabeledContent(localizer.modelName) {
                        TextField("deepseek-chat", text: $model)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 " + localizer.recommendedConfig)
                        .font(.caption).fontWeight(.semibold).foregroundColor(.purple)

                    ForEach(presets, id: \.name) { preset in
                        Button {
                            apiBase = preset.base
                            model = preset.model
                        } label: {
                            HStack {
                                Text("• \(preset.name)")
                                Spacer()
                                Text(preset.model).font(.caption).foregroundColor(.secondary)
                            }
                            .font(.caption).foregroundColor(.primary)
                            .padding(.vertical, 2)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(12)
                .background(Color.purple.opacity(0.05))
                .cornerRadius(8)
            }
            .padding(20)

            Divider()

            HStack {
                Spacer()
                Button(localizer.cancelBtn) { dismiss() }
                    .buttonStyle(.bordered)
                Button(localizer.save) { saveConfig() }
                    .buttonStyle(.borderedProminent)
                    .tint(.purple)
            }
            .padding(16)
        }
        .frame(width: 520)
        .onAppear { loadConfig() }
    }

    private func loadConfig() {
        if let config = service.aiConfig {
            apiBase = config.apiBase ?? "https://api.deepseek.com"
            apiKey = config.apiKey ?? ""
            model = config.model ?? "deepseek-chat"
        }
    }

    private func saveConfig() {
        service.saveAIConfig(apiBase: apiBase, apiKey: apiKey, model: model)
        dismiss()
    }
}
