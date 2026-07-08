import SwiftUI

struct AIConfigView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = AIConfig.appleIntelligenceModel
    @State private var providerMode: AIProviderMode = .automatic

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

                formRow(localizer.t("模型策略", en: "Model Mode")) {
                    Picker("", selection: $providerMode) {
                        Text(localizer.t("自动", en: "Auto")).tag(AIProviderMode.automatic)
                        Text("Apple").tag(AIProviderMode.apple)
                        Text(localizer.t("第三方", en: "External")).tag(AIProviderMode.external)
                    }
                    .pickerStyle(.segmented)
                }

                Text(modeDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.leading, 132)

                formRow(localizer.t("API 地址", en: "API Base URL")) {
                    TextField("https://api.example.com, .../v1, or .../v1/chat/completions", text: $apiBase)
                        .textFieldStyle(.roundedBorder)
                        .disabled(providerMode == .apple)
                }
                formRow(localizer.t("API Key", en: "API Key")) {
                    SecureField("Optional", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .disabled(providerMode == .apple)
                }
                formRow(localizer.t("模型", en: "Model")) {
                    TextField(AIConfig.appleIntelligenceModel, text: $model)
                        .textFieldStyle(.roundedBorder)
                        .disabled(providerMode == .apple)
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
                                providerMode = .apple
                            } else {
                                providerMode = .external
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

    private var modeDescription: String {
        switch providerMode {
        case .automatic:
            return localizer.t("默认先使用 Apple Intelligence；不可用时才尝试你填写的第三方模型。", en: "Uses Apple Intelligence first, then falls back to your external provider if Apple is unavailable.")
        case .apple:
            return localizer.t("只使用 Apple Intelligence，不会调用第三方模型。", en: "Only uses Apple Intelligence. External providers are not called.")
        case .external:
            return localizer.t("直接使用第三方模型；请填写 API 地址、API Key 和模型名。", en: "Uses the external provider directly. Enter API base URL, API key, and model name.")
        }
    }

    private func loadConfig() {
        if let config = service.aiConfig {
            apiBase = config.apiBase ?? ""
            apiKey = config.apiKey ?? ""
            model = config.model ?? AIConfig.appleIntelligenceModel
            providerMode = config.providerMode
        }
    }

    private func saveConfig() {
        let savedModel = providerMode == .apple ? AIConfig.appleIntelligenceModel : model
        service.saveAIConfig(apiBase: apiBase, apiKey: apiKey, model: savedModel, mode: providerMode)
        dismiss()
    }
}
