import SwiftUI

struct AIConfigView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss
    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = AIConfig.appleIntelligenceModel

    private var isAppleIntelligenceSelected: Bool {
        model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model == AIConfig.appleIntelligenceModel
    }

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
                    Text(localizer.t("默认模型", en: "Default Model"))
                        .font(.caption).fontWeight(.semibold)
                    Text("Apple Intelligence")
                        .font(.headline)
                    Text(AppleIntelligenceService.availabilitySummary())
                        .font(.caption).foregroundColor(.secondary)
                }
                .padding(12)
                .background(Color.accentColor.opacity(0.06))
                .cornerRadius(8)

                Picker(localizer.t("模型来源", en: "Model Provider"), selection: $model) {
                    Text("Apple Intelligence").tag(AIConfig.appleIntelligenceModel)
                    Text("DeepSeek").tag("deepseek-chat")
                    Text("OpenAI").tag("gpt-4o-mini")
                    Text(localizer.t("自定义兼容模型", en: "Custom compatible model")).tag("custom")
                }
                .pickerStyle(.segmented)

                if !isAppleIntelligenceSelected {
                    VStack(alignment: .leading, spacing: 12) {
                        formRow(localizer.t("API 地址", en: "API Base URL")) {
                            TextField("https://api.openai.com/v1", text: $apiBase)
                                .textFieldStyle(.roundedBorder)
                        }
                        formRow("API Key") {
                            SecureField("sk-...", text: $apiKey)
                                .textFieldStyle(.roundedBorder)
                        }
                        formRow(localizer.t("模型", en: "Model")) {
                            TextField("gpt-4o-mini", text: $model)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(8)
                }
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
        .onAppear(perform: loadConfig)
    }

    private func saveConfig() {
        if isAppleIntelligenceSelected {
            service.saveLocalAIConfig()
        } else {
            service.saveAIConfig(apiBase: apiBase, apiKey: apiKey, model: model)
        }
        dismiss()
    }

    private func loadConfig() {
        let config = service.aiConfig
        apiBase = config?.apiBase ?? ""
        apiKey = config?.apiKey ?? ""
        model = config?.model ?? AIConfig.appleIntelligenceModel
    }

    @ViewBuilder
    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            content()
        }
    }
}
