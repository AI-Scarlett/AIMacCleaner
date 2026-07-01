import SwiftUI

struct AIConfigView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = AIConfig.appleIntelligenceModel

    let presets: [(name: String, base: String, model: String)] = [
        ("Apple Intelligence", "", AIConfig.appleIntelligenceModel),
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

                VStack(alignment: .leading, spacing: 8) {
                    Text("Apple Intelligence")
                        .font(.caption).fontWeight(.semibold)
                    Text(AppleIntelligenceService.availabilitySummary())
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)

                formRow(localizer.t("API 地址", en: "API Base URL")) {
                    TextField("Optional for external providers", text: $apiBase)
                        .textFieldStyle(.roundedBorder)
                }
                formRow(localizer.t("API Key", en: "API Key")) {
                    SecureField("Optional", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                }
                formRow(localizer.t("模型", en: "Model")) {
                    TextField(AIConfig.appleIntelligenceModel, text: $model)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 " + localizer.t("推荐配置", en: "Recommended configuration"))
                        .font(.caption).fontWeight(.semibold).foregroundColor(.purple)

                    ForEach(presets, id: \.name) { preset in
                        Button {
                            apiBase = preset.base
                            model = preset.model
                            if preset.model == AIConfig.appleIntelligenceModel {
                                apiKey = ""
                            }
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

    private func formRow<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(.callout)
                .foregroundColor(.secondary)
                .frame(width: 120, alignment: .trailing)
            content()
                .frame(width: 300)
        }
    }

    private func loadConfig() {
        if let config = service.aiConfig {
            apiBase = config.apiBase ?? ""
            apiKey = config.apiKey ?? ""
            model = config.model ?? AIConfig.appleIntelligenceModel
        }
    }

    private func saveConfig() {
        service.saveAIConfig(apiBase: apiBase, apiKey: apiKey, model: model)
        dismiss()
    }
}
