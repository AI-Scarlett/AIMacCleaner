import AppKit
import MacToolsPluginKit
import SwiftUI

struct AgentProfileSettingsView: View {
    @ObservedObject var controller: AgentProfileController
    let localization: PluginLocalization

    @Environment(\.pluginComponentTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: PluginSettingsTheme.Spacing.section) {
            statusGrid
            profileControls
            identityControls
            coverageControls
            launcherSection
            providerDiagnosticsNotice
        }
        .frame(maxWidth: 980, alignment: .topLeading)
    }

    private var providerDiagnosticsNotice: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.title2.weight(.semibold))
                .foregroundStyle(theme.status.warning)
                .frame(width: 36, height: 36)
                .background(theme.interaction.subtleTint(theme.status.warning))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 5) {
                Text(localization.string("providerDiagnostics.title", defaultValue: "Provider 专项诊断"))
                    .font(PluginSettingsTheme.Typography.emphasizedRowTitle)
                    .foregroundStyle(theme.text.primary)
                Text(localization.string(
                    "providerDiagnostics.body",
                    defaultValue: "通用 Agent 画像负责进程环境和网络出口；Codex、Claude、Google Antigravity 等账号资格由各 Provider 服务端决定。网络出口变化不能替代账号资格判断。"
                ))
                .font(PluginSettingsTheme.Typography.rowDescription)
                .foregroundStyle(theme.text.secondary)
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 12) {
                    Button(localization.string("providerDiagnostics.googleDocs", defaultValue: "Antigravity 官方可用地区")) {
                        controller.openOfficialAvailability()
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
            sectionTitle(localization.string("status.title", defaultValue: "网络画像状态"), icon: "checklist")
            HStack(alignment: .top, spacing: 12) {
                statusCard(
                    title: localization.string("status.direct", defaultValue: "默认路径公网出口"),
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
                    value: localization.string("status.providerControlled", defaultValue: "不从本机出口推断"),
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
                    description: localization.string("profile.route.detail", defaultValue: "向所有通用 Agent 启动器注入代理；对 Chromium/Antigravity 额外禁用 QUIC 和非代理 WebRTC UDP。")
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
                divider
                numberFieldRow(title: localization.string("identity.latitude", defaultValue: "纬度"), value: binding(\.latitude), format: "%.4f")
                divider
                numberFieldRow(title: localization.string("identity.longitude", defaultValue: "经度"), value: binding(\.longitude), format: "%.4f")
                divider
                numberFieldRow(title: localization.string("identity.accuracy", defaultValue: "定位精度（米）"), value: binding(\.accuracyMeters), format: "%.0f")
            }
            .pluginSettingsCardBackground()
        }
    }

    private var coverageControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(localization.string("coverage.title", defaultValue: "覆盖范围与通用接入"), icon: "square.stack.3d.up")
            VStack(spacing: 0) {
                settingRow(
                    title: localization.string("coverage.cli", defaultValue: "CLI wrappers"),
                    description: localization.string("coverage.cli.detail", defaultValue: "为 Codex、Claude、Grok、Gemini、DSH 等命令生成通用启动包装。")
                ) {
                    Toggle("", isOn: binding(\.cliWrappersEnabled)).labelsHidden()
                }
                divider
                settingRow(
                    title: localization.string("coverage.desktop", defaultValue: "桌面 Agent 启动器"),
                    description: localization.string("coverage.desktop.detail", defaultValue: "为已安装的 Codex、Claude、Cursor、Antigravity 等桌面应用生成启动器。")
                ) {
                    Toggle("", isOn: binding(\.desktopLaunchersEnabled)).labelsHidden()
                }
                divider
                settingRow(
                    title: localization.string("coverage.browser", defaultValue: "浏览器画像扩展"),
                    description: localization.string("coverage.browser.detail", defaultValue: "生成 Chromium 扩展，覆盖页面可见的语言、时区、粗略位置与 Accept-Language。")
                ) {
                    Toggle("", isOn: binding(\.browserExtensionEnabled)).labelsHidden()
                }
                divider
                settingRow(
                    title: localization.string("coverage.location", defaultValue: "粗略位置"),
                    description: localization.string("coverage.location.detail", defaultValue: "向支持该画像的浏览器页面和 Agent 提供配置中的坐标。")
                ) {
                    Toggle("", isOn: binding(\.locationOverrideEnabled)).labelsHidden()
                }
                divider
                settingRow(
                    title: localization.string("coverage.timezone", defaultValue: "时区"),
                    description: localization.string("coverage.timezone.detail", defaultValue: "为新进程注入 TZ，并在浏览器画像中覆盖 Intl 时区。")
                ) {
                    Toggle("", isOn: binding(\.timezoneOverrideEnabled)).labelsHidden()
                }
                divider
                settingRow(
                    title: localization.string("coverage.language", defaultValue: "语言与 Locale"),
                    description: localization.string("coverage.language.detail", defaultValue: "为新进程和浏览器页面提供 Locale 与语言列表。")
                ) {
                    Toggle("", isOn: binding(\.languageOverrideEnabled)).labelsHidden()
                }
                divider
                settingRow(
                    title: "Accept-Language",
                    description: localization.string("coverage.acceptLanguage.detail", defaultValue: "为受控浏览器请求设置 Accept-Language。")
                ) {
                    Toggle("", isOn: binding(\.acceptLanguageOverrideEnabled)).labelsHidden()
                }
            }
            .pluginSettingsCardBackground()
        }
    }

    private var launcherSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(localization.string("launcher.title", defaultValue: "通用 Agent 接入"), icon: "paperplane")
            HStack(spacing: 10) {
                Button {
                    controller.generateAssets()
                } label: {
                    Label(localization.string("action.generate", defaultValue: "生成全部画像组件"), systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .disabled(controller.isGenerating)

                Button(localization.string("action.shell", defaultValue: "打开画像 CLI Shell")) {
                    controller.launchProfileShell()
                }
                .buttonStyle(.bordered)

                Menu(localization.string("action.agents", defaultValue: "启动 Agent")) {
                    if !controller.installedDesktopIntegrations.isEmpty {
                        Section(localization.string("integrations.desktop", defaultValue: "桌面端")) {
                            ForEach(controller.installedDesktopIntegrations) { integration in
                                Button(integration.displayName) { controller.launchDesktop(integration) }
                            }
                        }
                    }
                    if !controller.installedCLIIntegrations.isEmpty {
                        Section("CLI") {
                            ForEach(controller.installedCLIIntegrations) { integration in
                                Button(integration.displayName) { controller.launchCLI(integration) }
                            }
                        }
                    }
                }
                .buttonStyle(.bordered)

                Button(localization.string("action.folder", defaultValue: "打开生成目录")) {
                    controller.openGeneratedFolder()
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 10) {
                Button(localization.string("action.context", defaultValue: "打开通用画像说明")) {
                    controller.openProfileContext()
                }
                .buttonStyle(.bordered)

                Button(localization.string("action.copyProfilePath", defaultValue: "复制画像文件路径")) {
                    controller.copyProfilePath()
                }
                .buttonStyle(.bordered)

                Button(localization.string("action.browserExtension", defaultValue: "显示浏览器扩展")) {
                    controller.openBrowserExtensionFolder()
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
        String(
            format: localization.string("install.summary", defaultValue: "已检测到 %d 个桌面 Agent、%d 个 CLI Agent"),
            controller.installedDesktopIntegrations.count,
            controller.installedCLIIntegrations.count
        )
    }

    private var proxyStatusText: String {
        switch controller.diagnostic.status {
        case .notTested: localization.string("status.unknown", defaultValue: "未检测")
        case .proxyDisabled: localization.string("panel.proxyDisabled", defaultValue: "未启用代理路由")
        case .proxyInvalid: localization.string("panel.proxyInvalid", defaultValue: "代理地址无效")
        case .proxyUnavailable: localization.string("panel.proxyUnavailable", defaultValue: "代理出口不可用")
        case .sameAsDirect: localization.string("panel.sameEgress", defaultValue: "与显式代理出口相同；未检测到 TUN")
        case .routed: localization.string("panel.routed.short", defaultValue: "出口已切换")
        }
    }

    private var proxyStatusColor: Color {
        switch controller.diagnostic.status {
        case .routed: theme.status.success
        case .proxyInvalid, .proxyUnavailable: theme.status.critical
        case .sameAsDirect: theme.status.warning
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

    private func numberFieldRow(title: String, value: Binding<Double>, format: String) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(PluginSettingsTheme.Typography.rowTitle)
                .foregroundStyle(theme.text.primary)
                .frame(width: 150, alignment: .leading)
            TextField(title, value: value, format: .number)
                .textFieldStyle(.roundedBorder)
                .font(PluginSettingsTheme.Typography.monospacedValue)
            Text(String(format: format, value.wrappedValue))
                .font(PluginSettingsTheme.Typography.monospacedValue)
                .foregroundStyle(theme.text.tertiary)
                .frame(width: 78, alignment: .trailing)
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
        if raw == "profile-path-copied" { return localization.string("status.profilePathCopied", defaultValue: "画像路径已复制") }
        if raw.hasPrefix("generation-failed") { return localization.string("status.generateFailed", defaultValue: "生成失败") }
        return raw
    }
}
