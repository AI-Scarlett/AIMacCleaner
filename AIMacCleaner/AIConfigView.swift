import SwiftUI

struct AIConfigView: View {
    @EnvironmentObject var service: ScannerService
    @EnvironmentObject var localizer: Localizer
    @Environment(\.dismiss) var dismiss

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
    }

    private func saveConfig() {
        service.saveLocalAIConfig()
        dismiss()
    }
}
