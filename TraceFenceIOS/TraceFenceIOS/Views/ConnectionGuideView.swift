import SwiftUI

struct ConnectionGuideView: View {
    private let modes: [(String, String, String, String, Color)] = [
        ("同一 Wi-Fi / 局域网", "Mac 和 iPhone 在同一个网络中。", "最简单，适合家里或办公室；离开网络后不可用。", "wifi", TraceFenceDesign.success),
        ("私有 VPN / Tailnet", "Mac 和 iPhone 必须安装并登录同一个 Tailscale、ZeroTier、WireGuard 或公司 VPN。", "推荐的互联网远程方案，不需要 TraceFence 后端；只连接 Mac 一端无法远程访问。", "lock.icloud.fill", TraceFenceDesign.accent),
        ("端口转发 + DDNS", "路由器端口转发、防火墙规则、动态域名或固定公网 IP。", "只适合高级用户；公网场景应使用 HTTPS 或安全隧道。", "network", TraceFenceDesign.warning),
        ("用户自有反向隧道", "Cloudflare Tunnel、frp、SSH reverse tunnel 或自己的 VPS。", "TraceFence 不运营中继，隧道服务由用户自己负责。", "arrow.triangle.turn.up.right.diamond.fill", Color.indigo)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TFCard {
                    Text("无后端远程控制")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(TraceFenceDesign.text)
                    Text("iOS 客户端不会登录 TraceFence 云服务，也不会把 Agent 数据传给 TraceFence。它只是用配对密钥直连你的 Mac。")
                        .font(.subheadline)
                        .foregroundStyle(TraceFenceDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                TFCard {
                    Text("Mac 端准备")
                        .font(.headline)
                    guideRow("1", "打开 Mac 版 TraceFence 设置。")
                    guideRow("2", "点击 Mac 客户端左下角的 iOS 远程配对图标。")
                    guideRow("3", "确认 Agent Core 在线，然后复制或显示 iOS 配对信息。")
                    guideRow("4", "在本 iOS app 的配对页粘贴并测试。")
                }

                ForEach(modes, id: \.0) { mode in
                    TFCard {
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: mode.3)
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(mode.4)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(mode.0.tfLocalized)
                                    .font(.headline)
                                    .foregroundStyle(TraceFenceDesign.text)
                                Text(mode.1.tfLocalized)
                                    .font(.subheadline)
                                    .foregroundStyle(TraceFenceDesign.secondary)
                                Text(mode.2.tfLocalized)
                                    .font(.caption)
                                    .foregroundStyle(TraceFenceDesign.secondary)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(TraceFenceDesign.background.ignoresSafeArea())
        .navigationTitle("连接说明")
    }

    private func guideRow(_ number: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(TraceFenceDesign.accent)
                .clipShape(Circle())
            Text(text.tfLocalized)
                .font(.subheadline)
                .foregroundStyle(TraceFenceDesign.text)
            Spacer()
        }
    }
}
