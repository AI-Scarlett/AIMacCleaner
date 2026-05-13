import SwiftUI

struct AIConfigView: View {
    @EnvironmentObject var service: ScannerService
    @Environment(\.dismiss) var dismiss

    @State private var apiBase = ""
    @State private var apiKey = ""
    @State private var model = ""

    let presets: [(name: String, base: String, model: String)] = [
        ("DeepSeek", "https://api.deepseek.com", "deepseek-chat"),
        ("OpenAI", "https://api.openai.com", "gpt-4o-mini"),
        ("智谱 GLM", "https://open.bigmodel.cn/api/paas", "glm-4-flash"),
        ("通义千问", "https://dashscope.aliyuncs.com/compatible-mode", "qwen-turbo"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("🤖 AI 扫描配置")
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
                Text("配置大模型 API，用于智能分析目录结构和识别可清理项")
                    .font(.callout).foregroundColor(.secondary)

                Group {
                    LabeledContent("API Base URL") {
                        TextField("https://api.deepseek.com", text: $apiBase)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                    }
                    LabeledContent("API Key") {
                        SecureField("sk-...", text: $apiKey)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                    }
                    LabeledContent("模型名称") {
                        TextField("deepseek-chat", text: $model)
                            .textFieldStyle(.roundedBorder).frame(width: 300)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("💡 推荐配置（点击自动填入）")
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
                Button("取消") { dismiss() }
                    .buttonStyle(.bordered)
                Button("保存配置") { saveConfig() }
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
