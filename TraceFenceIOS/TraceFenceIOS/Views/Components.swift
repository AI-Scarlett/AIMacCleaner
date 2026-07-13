import SwiftUI

enum TraceFenceDesign {
    static let background = Color(red: 0.96, green: 0.97, blue: 0.95)
    static let card = Color.white
    static let text = Color(red: 0.11, green: 0.13, blue: 0.16)
    static let secondary = Color(red: 0.38, green: 0.42, blue: 0.48)
    static let accent = Color(red: 0.13, green: 0.42, blue: 0.84)
    static let success = Color(red: 0.06, green: 0.55, blue: 0.35)
    static let warning = Color(red: 0.78, green: 0.44, blue: 0.08)
    static let danger = Color(red: 0.78, green: 0.18, blue: 0.2)
}

struct TFCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TraceFenceDesign.card)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }
}

struct StatusBadge: View {
    var text: String
    var color: Color
    var systemImage: String

    var body: some View {
        Label(text.tfLocalized, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var systemImage: String
    var color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(color)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(TraceFenceDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(title.tfLocalized)
                .font(.caption)
                .foregroundStyle(TraceFenceDesign.secondary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct EmptyConnectionView: View {
    @Environment(\.appLanguage) private var language
    var action: () -> Void
    var demoAction: (() -> Void)?

    var body: some View {
        TFCard {
            Image(systemName: "macbook.and.iphone")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(TraceFenceDesign.accent)
            Text("还没有连接 Mac")
                .font(.title3.weight(.bold))
                .foregroundStyle(TraceFenceDesign.text)
            Text("在 Mac 端打开设置里的 iOS 远程控制，复制配对信息到这里。TraceFence 不经过云端中继。")
                .font(.subheadline)
                .foregroundStyle(TraceFenceDesign.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: action) {
                Label("开始配对", systemImage: "qrcode.viewfinder")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            if let demoAction {
                Button(action: demoAction) {
                    Label(
                        language.text(zh: "查看只读演示", en: "View Read-only Demo", zhHant: "查看唯讀示範", ja: "読み取り専用デモを見る", ko: "읽기 전용 데모 보기", mt: "Ara Demo Read-only"),
                        systemImage: "play.rectangle"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
        }
    }
}

extension Double {
    var tfPercentText: String {
        "\(Int(self.rounded()))%"
    }

    var tfGigabyteText: String {
        String(format: "%.1f GB", self)
    }
}

extension Date {
    var tfShortTimeText: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: self)
    }
}
