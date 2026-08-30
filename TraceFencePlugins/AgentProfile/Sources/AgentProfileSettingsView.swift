import AppKit
import MacToolsPluginKit
import SwiftUI

struct AgentProfileSettingsView: View {
    @ObservedObject var controller: AgentProfileController
    let localization: PluginLocalization

    @Environment(\.pluginComponentTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            eligibilityNotice
            statusGrid
            profileControls
            identityControls
            launcherSection
        }
        .frame(maxWidth: 980, alignment: .topLeading)
    }

    private var eligibilityNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.status.warning)
                .frame(width: 36, height: 36)
                .background(theme.interaction.subtleTint(theme.status.warning))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(localization.string("eligibility.title", defaultValue: "Antigravity 账号资格由 Google 服务端决定"))
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                    .foregroundStyle(theme.text.primary)
                Text(localization.string(
                    "eligibility.body",
                    defaultValue: "Agent 画像只能校验本机进程的语言、时区和网络出口。即使代理 IP 已切换，也不能证明 Google 账号、年龄、方案或关联地区具备资格。"
                ))
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(theme.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(localization.string("eligibility.docs", defaultValue: "查看 Google 官方可用地区")) {
                        controller.openOfficialAvailability()
                    }
                    .buttonStyle(.link)
                    Button(localization.string("eligibility.apiKey", defaultValue: "CLI 使用 Gemini API Key")) {
                        controller.openOfficialCLIAuthentication()
                    }
                    .buttonStyle(.link)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(PluginSettingsTheme.Spacing.cardContent)
        .pluginSettingsCardBackground()
    }

    private var statusGrid: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(localization.string("status.title", defaultValue: "三层状态"), icon: "checklist")
            HStack(alignment: .top, spacing: 12) {
                statusCard(
                    title: localization.string("status.direct", defaultValue: "直连 Google 出口"),
                    value: controller.diagnostic.directGoogleIP ?? localization.string("status.unknown", defaultValue: "未检测"),
                    icon: "network",
                    color: theme.status.informational
                )
                statusCard(
                    title: localization.string("status.proxy", defaultValue: "画像代理出口"),
                    value: controller.diagnostic.proxyGoogleIP ?? proxyStatusText,
                    icon: "shield.lefthalf.filled",
                    color: proxyStatusColor
                )
                statusCard(
                    title: localization.string("status.account", defaultValue: "Provider 账号资格"),
                    value: localization.string("status.providerControlled", defaultValue: "由 Google 判定"),
                    icon: "person.badge.key",
                    color: theme.status.warning
                )
            }
            HStack(spacing: 10) {
                Button {
                    controller.runDiagnostics()
                } label: {
                    Label(
                        controller.isDiagnosing
                            ? localization.string("action.diagnosing", defaultValue: "检测中…")
                            : localization.string("action.diagnose", defaultValue: "检测网络画像"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isDiagnosing)

                Button(localization.string("action.copyReport", defaultValue: "复制诊断报告")) {
                    controller.copyDiagnosticReport()
                }
                .buttonStyle(.bordered)

                if controller.diagnostic.status == .routed,
                   controller.diagnostic.detectedCountryCode != nil {
                    Button(localization.string("action.applyDetected", defaultValue: "应用代理地区")) {
                        controller.applyDetectedLocation()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    private var profileControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(localization.string("profile.title", defaultValue: "独立画像"), icon: "globe.badge.chevron.backward")
            VStack(spacing: 0) {
                settingRow(
                    title: localization.string("profile.enabled", defaultValue: "启用 Agent 画像"),
                    description: localization.string("profile.enabled.detail", defaultValue: "只影响通过插件生成的启动器启动的新进程。")
                ) {
                    Toggle("", isOn: Binding(
                        get: { controller.configuration.enabled },
                        set: { controller.setEnabled($0) }
                    ))
                    .labelsHidden()
                }
                divider
                settingRow(
                    title: localization.string("profile.route", defaultValue: "通过代理路由 Agent 流量"),
                    description: localization.string("profile.route.detail", defaultValue: "同时为 Antigravity 禁用 QUIC 和非代理 WebRTC UDP。")
                ) {
                    Toggle("", isOn: binding(\.routeTrafficThroughProxy))
                        .labelsHidden()
                }
                divider
                fieldRow(
                    title: localization.string("profile.proxy", defaultValue: "代理地址"),
                    placeholder: "http://127.0.0.1:7890",
                    text: binding(\.proxyURL)
                )
                divider
                fieldRow(
                    title: localization.string("profile.noProxy", defaultValue: "不走代理"),
                    placeholder: "localhost,127.0.0.1,::1",
                    text: binding(\.noProxy)
                )
            }
            .pluginSettingsCardBackground()
        }
    }

    private var identityControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(localization.string("identity.title", defaultValue: "语言与地区画像"), icon: "character.bubble")
            VStack(spacing: 0) {
                fieldRow(title: localization.string("identity.country", defaultValue: "国家/地区代码"), placeholder: "US", text: binding(\.countryCode))
                divider
                fieldRow(title: localization.string("identity.region", defaultValue: "州/省"), placeholder: "California", text: binding(\.region))
                divider
                fieldRow(title: localization.string("identity.city", defaultValue: "城市"), placeholder: "San Francisco", text: binding(\.city))
                divider
                fieldRow(title: localization.string("identity.timezone", defaultValue: "时区"), placeholder: "America/Los_Angeles", text: binding(\.timezoneIdentifier))
                divider
                fieldRow(title: localization.string("identity.locale", defaultValue: "语言区域"), placeholder: "en-US", text: binding(\.localeIdentifier))
                divider
                fieldRow(title: localization.string("identity.languages", defaultValue: "语言列表"), placeholder: "en-US,en", text: binding(\.languages))
                divider
                fieldRow(title: "Accept-Language", placeholder: "en-US,en;q=0.9", text: binding(\.acceptLanguage))
            }
            .pluginSettingsCardBackground()
        }
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(localization.string("launcher.title", defaultValue: "生成与启动"), icon: "paperplane")
            HStack(spacing: 10) {
                Button {
                    controller.generateAssets()
                } label: {
                    Label(localization.string("action.generate", defaultValue: "生成独立画像"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isGenerating)

                Button(localization.string("action.launchApp", defaultValue: "启动 Antigravity")) {
                    controller.launchAntigravity()
                }
                .buttonStyle(.bordered)

                Button(localization.string("action.launchCLI", defaultValue: "启动 Antigravity CLI")) {
                    controller.launchAntigravityCLI()
                }
                .buttonStyle(.bordered)

                Button(localization.string("action.folder", defaultValue: "打开生成目录")) {
                    controller.openGeneratedFolder()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 8) {
                Image(systemName: "shippingbox")
                    .foregroundStyle(theme.text.tertiary)
                Text(installationSummary)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(theme.text.secondary)
                if let status = controller.statusMessage {
                    Text("· \(localizedStatus(status))")
                        .font(PluginSettingsTheme.Typography.rowDescription)
                        .foregroundStyle(status.hasPrefix("generation-failed") ? theme.status.critical : theme.status.success)
                }
            }
        }
    }

    private var installationSummary: String {
        switch controller.antigravityInstallationSummary {
        case "app+cli": localization.string("install.both", defaultValue: "已检测到 Antigravity App 与 CLI")
        case "app": localization.string("install.app", defaultValue: "已检测到 Antigravity App；未检测到 CLI")
        case "cli": localization.string("install.cli", defaultValue: "已检测到 Antigravity CLI；未检测到 App")
        default: localization.string("install.missing", defaultValue: "未检测到 Antigravity App 或 CLI")
        }
    }

    private var proxyStatusText: String {
        switch controller.diagnostic.status {
        case .notTested: localization.string("status.unknown", defaultValue: "未检测")
        case .proxyDisabled: localization.string("panel.proxyDisabled", defaultValue: "未启用代理路由")
        case .proxyInvalid: localization.string("panel.proxyInvalid", defaultValue: "代理地址无效")
        case .proxyUnavailable: localization.string("panel.proxyUnavailable", defaultValue: "代理出口不可用")
        case .sameAsDirect: localization.string("panel.sameEgress", defaultValue: "与直连相同")
        case .routed: localization.string("panel.routed.short", defaultValue: "出口已切换")
        }
    }

    private var proxyStatusColor: Color {
        switch controller.diagnostic.status {
        case .routed: theme.status.success
        case .sameAsDirect, .proxyInvalid, .proxyUnavailable: theme.status.critical
        case .notTested, .proxyDisabled: theme.status.warning
        }
    }

    private func statusCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundStyle(color)
            Text(title)
                .font(PluginSettingsTheme.Typography.secondaryLabel)
                .foregroundStyle(theme.text.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(theme.text.primary)
                .lineLimit(2)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(theme.surfaces.nested)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        Label(title, systemImage: icon)
            .font(PluginSettingsTheme.Typography.sectionTitle)
            .foregroundStyle(theme.text.primary)
    }

    private func settingRow<Control: View>(
        title: String,
        description: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(PluginSettingsTheme.Typography.rowTitle)
                    .foregroundStyle(theme.text.primary)
                Text(description)
                    .font(PluginSettingsTheme.Typography.rowDescription)
                    .foregroundStyle(theme.text.secondary)
            }
            Spacer(minLength: 12)
            control()
        }
        .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
        .padding(.vertical, PluginSettingsTheme.Spacing.interactiveRowVertical)
    }

    private func fieldRow(title: String, placeholder: String, text: Binding<String>) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(PluginSettingsTheme.Typography.rowTitle)
                .foregroundStyle(theme.text.primary)
                .frame(width: 150, alignment: .leading)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(PluginSettingsTheme.Typography.monospacedValue)
        }
        .padding(.horizontal, PluginSettingsTheme.Spacing.rowHorizontal)
        .padding(.vertical, PluginSettingsTheme.Spacing.rowVertical)
    }

    private var divider: some View {
        PluginSettingsListDivider()
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<AgentProfileConfiguration, Value>) -> Binding<Value> {
        Binding(
            get: { controller.configuration[keyPath: keyPath] },
            set: { controller.configuration[keyPath: keyPath] = $0 }
        )
    }

    private func localizedStatus(_ raw: String) -> String {
        if raw == "generated" { return localization.string("status.generated", defaultValue: "画像已生成") }
        if raw == "copied" { return localization.string("status.copied", defaultValue: "报告已复制") }
        if raw.hasPrefix("generation-failed") { return localization.string("status.generateFailed", defaultValue: "生成失败") }
        return raw
    }
}
