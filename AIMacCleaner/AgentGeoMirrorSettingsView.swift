import AppKit
import SwiftUI

private struct BrowserExtensionTarget: Identifiable {
    let id: String
    let displayName: String
    let appName: String
    let executableName: String
    let extensionPage: String
    let icon: String

    static let supported: [BrowserExtensionTarget] = [
        BrowserExtensionTarget(id: "chrome", displayName: "Google Chrome", appName: "Google Chrome", executableName: "Google Chrome", extensionPage: "chrome://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "edge", displayName: "Microsoft Edge", appName: "Microsoft Edge", executableName: "Microsoft Edge", extensionPage: "edge://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "brave", displayName: "Brave", appName: "Brave Browser", executableName: "Brave Browser", extensionPage: "brave://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "arc", displayName: "Arc", appName: "Arc", executableName: "Arc", extensionPage: "arc://extensions/", icon: "globe"),
        BrowserExtensionTarget(id: "vivaldi", displayName: "Vivaldi", appName: "Vivaldi", executableName: "Vivaldi", extensionPage: "vivaldi://extensions/", icon: "globe")
    ]
}

private struct DesktopAgentLaunchTarget: Identifiable {
    let id: String
    let displayName: String
    let appName: String
    let launcherFileName: String
    let icon: String

    static let codex = DesktopAgentLaunchTarget(
        id: "codex",
        displayName: "Codex",
        appName: "Codex",
        launcherFileName: "Launch Codex.command",
        icon: "terminal"
    )

    static let supported: [DesktopAgentLaunchTarget] = [
        codex,
        DesktopAgentLaunchTarget(id: "claude", displayName: "Claude", appName: "Claude", launcherFileName: "Launch Claude.command", icon: "bubble.left.and.text.bubble.right"),
        DesktopAgentLaunchTarget(id: "cursor", displayName: "Cursor", appName: "Cursor", launcherFileName: "Launch Cursor.command", icon: "cursorarrow"),
        DesktopAgentLaunchTarget(id: "windsurf", displayName: "Windsurf", appName: "Windsurf", launcherFileName: "Launch Windsurf.command", icon: "wind"),
        DesktopAgentLaunchTarget(id: "vscode", displayName: "Visual Studio Code", appName: "Visual Studio Code", launcherFileName: "Launch Visual Studio Code.command", icon: "chevron.left.forwardslash.chevron.right"),
        DesktopAgentLaunchTarget(id: "chatgpt", displayName: "ChatGPT", appName: "ChatGPT", launcherFileName: "Launch ChatGPT.command", icon: "sparkles"),
        DesktopAgentLaunchTarget(id: "trae", displayName: "Trae", appName: "Trae", launcherFileName: "Launch Trae.command", icon: "terminal")
    ]
}

private struct CLIAgentLaunchTarget: Identifiable {
    let id: String
    let displayName: String
    let launcherFileName: String
    let icon: String

    static let grok = CLIAgentLaunchTarget(
        id: "grok",
        displayName: "Grok CLI",
        launcherFileName: "Launch Grok CLI.command",
        icon: "terminal"
    )

    static let shell = CLIAgentLaunchTarget(
        id: "shell",
        displayName: "CLI Shell",
        launcherFileName: "Open TraceFence CLI Shell.command",
        icon: "chevron.left.forwardslash.chevron.right"
    )
}

struct AgentGeoMirrorSettingsView: View {
    @EnvironmentObject private var localizer: Localizer

    @AppStorage("agentGeoMirrorEnabled") private var enabled = false
    @AppStorage("agentGeoMirrorProfileName") private var profileName = "default"
    @AppStorage("agentGeoMirrorProxyURL") private var proxyURL = "http://127.0.0.1:7890"
    @AppStorage("agentGeoMirrorNoProxy") private var noProxy = "localhost,127.0.0.1,::1"
    @AppStorage("agentGeoMirrorCountryCode") private var countryCode = "US"
    @AppStorage("agentGeoMirrorRegion") private var region = "California"
    @AppStorage("agentGeoMirrorCity") private var city = "San Francisco"
    @AppStorage("agentGeoMirrorTimezone") private var timezoneIdentifier = "America/Los_Angeles"
    @AppStorage("agentGeoMirrorLocale") private var localeIdentifier = "en-US"
    @AppStorage("agentGeoMirrorLanguages") private var languages = "en-US,en"
    @AppStorage("agentGeoMirrorAcceptLanguage") private var acceptLanguage = "en-US,en;q=0.9"
    @AppStorage("agentGeoMirrorLatitude") private var latitude = 37.7749
    @AppStorage("agentGeoMirrorLongitude") private var longitude = -122.4194
    @AppStorage("agentGeoMirrorAccuracy") private var accuracyMeters = 80.0
    @AppStorage("agentGeoMirrorLocationOverride") private var locationOverrideEnabled = true
    @AppStorage("agentGeoMirrorTimezoneOverride") private var timezoneOverrideEnabled = true
    @AppStorage("agentGeoMirrorLanguageOverride") private var languageOverrideEnabled = true
    @AppStorage("agentGeoMirrorAcceptLanguageOverride") private var acceptLanguageOverrideEnabled = true
    @AppStorage("agentGeoMirrorCoreOverridesMigrated20260708") private var coreOverridesMigrated = false
    @AppStorage("agentGeoMirrorBrowserExtension") private var browserExtensionEnabled = true
    @AppStorage("agentGeoMirrorCLIWrappers") private var cliWrappersEnabled = true
    @AppStorage("agentGeoMirrorDesktopLaunchers") private var desktopLaunchersEnabled = true

    @State private var isGenerating = false
    @State private var isRefreshing = false
    @State private var lastGeneratedAssets: AgentGeoMirrorGeneratedAssets?
    @State private var statusMessage: String?
    @State private var statusIsError = false

    private var profile: AgentGeoMirrorProfile {
        AgentGeoMirrorProfile(
            name: trimmed(profileName, fallback: "default"),
            enabled: enabled,
            proxyURL: trimmed(proxyURL, fallback: "http://127.0.0.1:7890"),
            noProxy: noProxy,
            countryCode: trimmed(countryCode, fallback: "US").uppercased(),
            region: region.trimmingCharacters(in: .whitespacesAndNewlines),
            city: city.trimmingCharacters(in: .whitespacesAndNewlines),
            timezoneIdentifier: trimmed(timezoneIdentifier, fallback: "America/Los_Angeles"),
            localeIdentifier: trimmed(localeIdentifier, fallback: "en-US"),
            languages: languageList,
            acceptLanguage: trimmed(acceptLanguage, fallback: "en-US,en;q=0.9"),
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: max(1, accuracyMeters),
            locationOverrideEnabled: locationOverrideEnabled,
            timezoneOverrideEnabled: timezoneOverrideEnabled,
            languageOverrideEnabled: languageOverrideEnabled,
            acceptLanguageOverrideEnabled: acceptLanguageOverrideEnabled,
            browserExtensionEnabled: browserExtensionEnabled,
            cliWrappersEnabled: cliWrappersEnabled,
            desktopLaunchersEnabled: desktopLaunchersEnabled,
            updatedAt: Date()
        )
    }

    private var languageList: [String] {
        let parsed = languages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return parsed.isEmpty ? ["en-US", "en"] : parsed
    }

    private var universalProfileURL: String {
        AgentGeoMirrorProfileAccess.profileURL(profileName: trimmed(profileName, fallback: "default"))
    }

    private var universalProfileContextURL: String {
        AgentGeoMirrorProfileAccess.contextURL(profileName: trimmed(profileName, fallback: "default"))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            header
            verticalDivider
            proxySection
            verticalDivider
            identitySection
            verticalDivider
            overrideSection
            verticalDivider
            universalProfileSection
            verticalDivider
            actionSection
        }
        .cardStyle()
        .onAppear {
            restoreGeneratedState()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(alignment: .center, spacing: Theme.Spacing.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.Radius.md)
                        .fill(Theme.Colors.info.opacity(0.14))
                    Image(systemName: "globe.badge.chevron.backward")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(Theme.Colors.info)
                }
                .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t("Agent 环境画像", en: "Agent Environment Profile"))
                        .font(Theme.Font.bodyMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(localizer.t(
                        "官网版专属。根据代理出口生成浏览器、Claude/Cursor 等桌面端和 CLI Agent 可使用的语言、时区、定位与代理环境。",
                        en: "Direct build only. Generate proxy-aligned language, timezone, location, and proxy profiles for browsers, Claude/Cursor-style desktop apps, and CLI agents."
                    ))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                HStack(spacing: Theme.Spacing.sm) {
                    Text(enabled ? localizer.t("已启动", en: "Running") : localizer.t("未启动", en: "Off"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(enabled ? Theme.Colors.success : Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, 5)
                        .background((enabled ? Theme.Colors.success : Theme.Colors.textTertiary).opacity(0.12))
                        .clipShape(Capsule())

                    Toggle("", isOn: Binding(
                        get: { enabled },
                        set: { setProfileEnabled($0) }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .disabled(isGenerating || !SandboxPaths.isDirectDistribution)
                }
                .help(localizer.t("打开就是启动：TraceFence 会自动生成本地 Profile。", en: "Turn it on to start: TraceFence generates the local profile automatically."))
            }

            if !SandboxPaths.isDirectDistribution {
                infoBanner(
                    icon: "lock.fill",
                    text: localizer.t(
                        "当前不是官网版 Bundle，Agent 环境画像不会启用。",
                        en: "This is not the direct build bundle, so Agent Environment Profile is disabled."
                    ),
                    color: Theme.Colors.warning
                )
            } else {
                infoBanner(
                    icon: "info.circle.fill",
                    text: localizer.t(
                        "浏览器网页安装扩展；桌面 Agent 用启动器；CLI 可点“打开 Grok CLI/CLI Shell”，或用 tf-grok、tf-codex 等 wrapper。",
                        en: "Browser pages use the extension. Desktop agents use launchers. CLIs can use Open Grok CLI/CLI Shell, or wrappers such as tf-grok and tf-codex."
                    ),
                    color: Theme.Colors.info
                )
            }
        }
    }

    private var proxySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            miniHeader(
                icon: "network",
                title: localizer.t("代理出口", en: "Proxy Egress"),
                subtitle: localizer.t("用于自动检测出口国家、城市、时区和默认语言。", en: "Used to detect exit country, city, timezone, and default locale.")
            )
            stackedField(title: localizer.t("Profile 名称", en: "Profile Name"), text: $profileName, placeholder: "default")
            stackedField(title: localizer.t("代理 URL", en: "Proxy URL"), text: $proxyURL, placeholder: "http://127.0.0.1:7890")
            stackedField(title: "NO_PROXY", text: $noProxy, placeholder: "localhost,127.0.0.1,::1")

            Button {
                refreshFromProxy()
            } label: {
                Label(
                    isRefreshing ? localizer.t("检测中...", en: "Detecting...") : localizer.t("从当前代理刷新画像", en: "Refresh from Current Proxy"),
                    systemImage: "arrow.clockwise"
                )
            }
            .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 32))
            .disabled(isRefreshing || !SandboxPaths.isDirectDistribution)
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            miniHeader(
                icon: "mappin.and.ellipse",
                title: localizer.t("语言、时区与定位", en: "Language, Timezone, and Location"),
                subtitle: localizer.t("可手动修正检测结果，适配你的代理线路。", en: "Manually tune the detected profile for your proxy route.")
            )
            stackedField(title: localizer.t("国家代码", en: "Country Code"), text: $countryCode, placeholder: "US")
            stackedField(title: localizer.t("地区", en: "Region"), text: $region, placeholder: "California")
            stackedField(title: localizer.t("城市", en: "City"), text: $city, placeholder: "San Francisco")
            stackedField(title: localizer.t("IANA 时区", en: "IANA Timezone"), text: $timezoneIdentifier, placeholder: "America/Los_Angeles")
            stackedField(title: localizer.t("Locale", en: "Locale"), text: $localeIdentifier, placeholder: "en-US")
            stackedField(title: localizer.t("语言列表", en: "Languages"), text: $languages, placeholder: "en-US,en")
            stackedField(title: "Accept-Language", text: $acceptLanguage, placeholder: "en-US,en;q=0.9")

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                coordinateRow(title: localizer.t("纬度", en: "Latitude"), value: $latitude, range: -90...90)
                coordinateRow(title: localizer.t("经度", en: "Longitude"), value: $longitude, range: -180...180)
                coordinateRow(title: localizer.t("精度米", en: "Accuracy Meters"), value: $accuracyMeters, range: 1...5000)
            }
        }
    }

    private var overrideSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            miniHeader(
                icon: "slider.horizontal.3",
                title: localizer.t("覆盖范围", en: "Coverage"),
                subtitle: localizer.t("桌面 Agent 避免注入代理变量，防止 Codex 这类 Electron App 重连。", en: "Desktop agents avoid proxy-variable injection to prevent reconnect loops in Electron apps such as Codex.")
            )

            compactToggle(title: localizer.t("浏览器扩展", en: "Browser extension"), icon: "safari", isOn: $browserExtensionEnabled)
            compactToggle(title: localizer.t("CLI wrapper", en: "CLI wrappers"), icon: "terminal", isOn: $cliWrappersEnabled)
            compactToggle(title: localizer.t("桌面端启动器", en: "Desktop launchers"), icon: "macwindow", isOn: $desktopLaunchersEnabled)
            compactToggle(title: localizer.t("定位 API", en: "Location APIs"), icon: "location.fill", isOn: $locationOverrideEnabled)
            compactToggle(title: localizer.t("时区", en: "Timezone"), icon: "clock.fill", isOn: $timezoneOverrideEnabled)
            compactToggle(title: localizer.t("语言/Locale", en: "Language/Locale"), icon: "textformat", isOn: $languageOverrideEnabled)
            compactToggle(title: "Accept-Language", icon: "character.bubble.fill", isOn: $acceptLanguageOverrideEnabled)
        }
    }

    private var universalProfileSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            miniHeader(
                icon: "link.badge.plus",
                title: localizer.t("通用画像入口", en: "Universal Profile Endpoint"),
                subtitle: localizer.t(
                    "开关打开后，TraceFence 会自动启动本机只读 Profile 服务；新 CLI/Agent 可直接读取这份画像。",
                    en: "When enabled, TraceFence starts a local read-only Profile service that new CLIs and agents can read directly."
                )
            )

            HStack(alignment: .center, spacing: Theme.Spacing.sm) {
                Image(systemName: enabled ? "checkmark.seal.fill" : "pause.circle.fill")
                    .font(Theme.Font.bodyMedium)
                    .foregroundStyle(enabled ? Theme.Colors.success : Theme.Colors.textTertiary)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 4) {
                    Text(enabled
                        ? localizer.t("已启动，本地画像服务正在提供 Profile。", en: "Running. The local Profile service is serving this profile.")
                        : localizer.t("未启动。打开顶部开关后自动启动，不需要运行命令。", en: "Off. Turn on the switch above to start automatically; no command is required."))
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)

                    Text(universalProfileURL)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer()
            }
            .padding(Theme.Spacing.sm)
            .background((enabled ? Theme.Colors.success : Theme.Colors.textTertiary).opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    openUniversalProfile()
                } label: {
                    Label(localizer.t("打开画像", en: "Open Profile"), systemImage: "safari")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))
                .disabled(!enabled || isGenerating || !SandboxPaths.isDirectDistribution)

                Button {
                    copyUniversalProfileURL()
                } label: {
                    Label(localizer.t("复制链接", en: "Copy Link"), systemImage: "doc.on.doc")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                .disabled(!SandboxPaths.isDirectDistribution)

                Button {
                    openProfileContext()
                } label: {
                    Label(localizer.t("打开说明", en: "Open Context"), systemImage: "doc.text")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                .disabled(!enabled || isGenerating || !SandboxPaths.isDirectDistribution)
            }

            Text(localizer.t(
                "常规情况下，新 Agent 会从 TraceFence 启动器或 CLI Shell 继承 TRACEFENCE_PROFILE_URL；只有排查问题时才需要复制链接或查看生成目录。",
                en: "Normally, new agents inherit TRACEFENCE_PROFILE_URL from TraceFence launchers or the CLI Shell. Copy the link or inspect the generated folder only for troubleshooting."
            ))
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    generateAssets()
                } label: {
                    Label(
                        isGenerating ? localizer.t("处理中...", en: "Working...") : localizer.t("重新生成配置", en: "Regenerate Profile"),
                        systemImage: "wand.and.stars"
                    )
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.accent, variant: .primary, minHeight: 34))
                .disabled(isGenerating || !SandboxPaths.isDirectDistribution)

                Button {
                    openGeneratedFolder()
                } label: {
                    Label(localizer.t("打开目录", en: "Open Folder"), systemImage: "folder")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .secondary, minHeight: 34))
                .disabled(lastGeneratedAssets == nil)

                Menu {
                    ForEach(BrowserExtensionTarget.supported) { target in
                        Button {
                            openExtensionPage(for: target)
                        } label: {
                            Label(
                                localizer.t("打开 \(target.displayName) 扩展页", en: "Open \(target.displayName) Extensions"),
                                systemImage: target.icon
                            )
                        }
                        .disabled(browserApplicationURL(for: target) == nil)
                    }

                    Divider()

                    Button {
                        openBrowserExtensionFolder()
                    } label: {
                        Label(localizer.t("显示扩展目录", en: "Show Extension Folder"), systemImage: "folder")
                    }
                } label: {
                    Label(localizer.t("安装浏览器扩展", en: "Install Browser Extension"), systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .ghost, minHeight: 34))
                .disabled(lastGeneratedAssets == nil)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    launchDesktopAgent(.codex, terminateExisting: false)
                } label: {
                    Label(localizer.t("打开 Codex", en: "Open Codex"), systemImage: "play.fill")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.success, variant: .secondary, minHeight: 34))
                .disabled(!canLaunchDesktopAgent(.codex))

                Button {
                    launchDesktopAgent(.codex, terminateExisting: true)
                } label: {
                    Label(localizer.t("重启 Codex", en: "Restart Codex"), systemImage: "arrow.clockwise")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.warning, variant: .secondary, minHeight: 34))
                .disabled(!canLaunchDesktopAgent(.codex))

                Menu {
                    Section(localizer.t("启动", en: "Launch")) {
                        ForEach(DesktopAgentLaunchTarget.supported) { target in
                            Button {
                                launchDesktopAgent(target, terminateExisting: false)
                            } label: {
                                Label(
                                    localizer.t("打开 \(target.displayName)", en: "Open \(target.displayName)"),
                                    systemImage: target.icon
                                )
                            }
                            .disabled(!canLaunchDesktopAgent(target))
                        }
                    }

                    Section(localizer.t("重启", en: "Restart")) {
                        ForEach(DesktopAgentLaunchTarget.supported) { target in
                            Button {
                                launchDesktopAgent(target, terminateExisting: true)
                            } label: {
                                Label(
                                    localizer.t("重启 \(target.displayName)", en: "Restart \(target.displayName)"),
                                    systemImage: "arrow.clockwise"
                                )
                            }
                            .disabled(!canLaunchDesktopAgent(target))
                        }
                    }
                } label: {
                    Label(localizer.t("更多 Agent", en: "More Agents"), systemImage: "macwindow")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                .disabled(lastGeneratedAssets == nil)
            }

            HStack(spacing: Theme.Spacing.sm) {
                Button {
                    launchCLIAgent(.grok)
                } label: {
                    Label(localizer.t("打开 Grok CLI", en: "Open Grok CLI"), systemImage: "terminal")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .secondary, minHeight: 34))
                .disabled(!canLaunchCLIAgent(.grok))

                Button {
                    launchCLIAgent(.shell)
                } label: {
                    Label(localizer.t("打开 CLI Shell", en: "Open CLI Shell"), systemImage: "chevron.left.forwardslash.chevron.right")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.textSecondary, variant: .ghost, minHeight: 34))
                .disabled(!canLaunchCLIAgent(.shell))
            }

            if let statusMessage {
                infoBanner(icon: statusIsError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill", text: statusMessage, color: statusIsError ? Theme.Colors.warning : Theme.Colors.success)
            }

            if let assets = lastGeneratedAssets {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.t("已生成", en: "Generated"))
                        .font(Theme.Font.captionMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                    Text(assets.rootURL.path)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var verticalDivider: some View {
        Rectangle()
            .fill(Theme.Colors.separator.opacity(0.62))
            .frame(height: 1)
    }

    private func miniHeader(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(width: 18, height: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Text(subtitle)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
    }

    private func stackedField(title: String, text: Binding<String>, placeholder: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.roundedBorder)
                .font(Theme.Font.caption)
        }
    }

    private func coordinateRow(title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.Colors.textSecondary)
                Spacer()
                Text(String(format: "%.4f", value.wrappedValue))
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(Theme.Colors.textTertiary)
            }
            Slider(value: value, in: range)
        }
    }

    private func compactToggle(title: String, icon: String, isOn: Binding<Bool>) -> some View {
        Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                isOn.wrappedValue.toggle()
            }
        } label: {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: icon)
                    .font(Theme.Font.caption)
                    .foregroundStyle(isOn.wrappedValue ? Theme.Colors.info : Theme.Colors.textTertiary)
                    .frame(width: 22)
                Text(title)
                    .font(Theme.Font.captionMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: isOn.wrappedValue ? "checkmark.circle.fill" : "circle")
                    .font(Theme.Font.caption)
                    .foregroundStyle(isOn.wrappedValue ? Theme.Colors.info : Theme.Colors.textTertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func infoBanner(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            Image(systemName: icon)
                .font(Theme.Font.caption)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(text)
                .font(Theme.Font.caption)
                .foregroundStyle(color == Theme.Colors.warning ? Theme.Colors.warning : Theme.Colors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(Theme.Spacing.sm)
        .background(color.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private func generateAssets(successMessage: String? = nil) {
        guard SandboxPaths.isDirectDistribution else { return }
        isGenerating = true
        statusMessage = nil
        statusIsError = false
        let currentProfile = profile

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let assets = try AgentGeoMirrorService.shared.generateAssets(for: currentProfile)
                DispatchQueue.main.async {
                    lastGeneratedAssets = assets
                    statusMessage = successMessage ?? (currentProfile.enabled
                        ? localizer.t("Agent 环境画像已启动。新打开的桌面 Agent 和 CLI 会使用这套 Profile。", en: "Agent Environment Profile is running. Newly launched desktop agents and CLIs will use this profile.")
                        : localizer.t("Agent 环境画像已停止。后续从启动器或 wrapper 打开的 Agent 不再注入画像。", en: "Agent Environment Profile is off. Future launches from launchers or wrappers will not inject the profile."))
                    statusIsError = false
                    isGenerating = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = error.localizedDescription
                    statusIsError = true
                    isGenerating = false
                }
            }
        }
    }

    private func refreshFromProxy() {
        guard SandboxPaths.isDirectDistribution else { return }
        isRefreshing = true
        statusMessage = nil
        statusIsError = false
        let currentProfile = profile

        Task {
            do {
                let detected = try await AgentGeoMirrorService.shared.refreshProfileThroughProxy(currentProfile)
                await MainActor.run {
                    apply(detected)
                    statusMessage = localizer.t("已按代理出口刷新画像。", en: "Profile refreshed from proxy egress.")
                    statusIsError = false
                    isRefreshing = false
                    if enabled {
                        generateAssets(successMessage: localizer.t("已按代理出口刷新并重新启动 Profile。", en: "Profile refreshed from proxy egress and restarted."))
                    }
                }
            } catch {
                await MainActor.run {
                    statusMessage = error.localizedDescription
                    statusIsError = true
                    isRefreshing = false
                }
            }
        }
    }

    private func apply(_ detected: AgentGeoMirrorDetectedProfile) {
        countryCode = detected.countryCode
        region = detected.region
        city = detected.city
        timezoneIdentifier = detected.timezoneIdentifier
        localeIdentifier = detected.localeIdentifier
        languages = detected.languages.joined(separator: ",")
        acceptLanguage = detected.acceptLanguage
        latitude = detected.latitude
        longitude = detected.longitude
        accuracyMeters = detected.accuracyMeters
    }

    private func openGeneratedFolder() {
        guard let assets = lastGeneratedAssets else { return }
        NSWorkspace.shared.activateFileViewerSelecting([assets.rootURL])
    }

    private func openBrowserExtensionFolder() {
        guard let assets = lastGeneratedAssets else { return }
        NSWorkspace.shared.activateFileViewerSelecting([assets.browserExtensionURL])
        statusMessage = localizer.t(
            "已显示 BrowserExtension 文件夹。打开浏览器扩展页后，开启开发者模式并加载这个文件夹。",
            en: "Showing the BrowserExtension folder. Open the browser extensions page, enable Developer Mode, and load this folder."
        )
        statusIsError = false
    }

    private func openUniversalProfile() {
        ensureProfileServerSynced()
        guard let url = URL(string: universalProfileURL) else { return }
        NSWorkspace.shared.open(url)
        statusMessage = localizer.t(
            "已打开本地画像 JSON。这个链接只在本机可访问。",
            en: "Opened the local profile JSON. This link is available only on this Mac."
        )
        statusIsError = false
    }

    private func openProfileContext() {
        ensureProfileServerSynced()
        guard let url = URL(string: universalProfileContextURL) else { return }
        NSWorkspace.shared.open(url)
        statusMessage = localizer.t(
            "已打开本地画像说明。新 Agent 可读取这份上下文。",
            en: "Opened the local profile context. New agents can read this context."
        )
        statusIsError = false
    }

    private func copyUniversalProfileURL() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(universalProfileURL, forType: .string)
        statusMessage = localizer.t(
            "已复制画像链接。一般用户无需使用；排查新 Agent 接入时再粘贴给对应工具。",
            en: "Copied the profile link. Most users do not need it; use it only when troubleshooting a new agent integration."
        )
        statusIsError = false
    }

    private func ensureProfileServerSynced() {
        guard enabled else { return }
        AgentGeoMirrorProfileServer.shared.syncWithDefaults()
    }

    private func openExtensionPage(for target: BrowserExtensionTarget) {
        guard lastGeneratedAssets != nil else { return }
        guard let appURL = browserApplicationURL(for: target) else {
            statusMessage = localizer.t(
                "没有找到 \(target.displayName)。请先安装浏览器，或手动打开扩展目录。",
                en: "\(target.displayName) was not found. Install the browser first, or open the extension folder manually."
            )
            statusIsError = true
            return
        }

        let executableURL = appURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("MacOS", isDirectory: true)
            .appendingPathComponent(target.executableName)

        do {
            let process = Process()
            process.executableURL = executableURL
            process.arguments = [target.extensionPage]
            try process.run()
            openBrowserExtensionFolder()
            statusMessage = localizer.t(
                "已打开 \(target.displayName) 扩展页，并显示扩展目录。开启开发者模式后加载 BrowserExtension 文件夹。",
                en: "Opened \(target.displayName) Extensions and showed the extension folder. Enable Developer Mode, then load the BrowserExtension folder."
            )
            statusIsError = false
        } catch {
            NSWorkspace.shared.open(appURL)
            openBrowserExtensionFolder()
            statusMessage = localizer.t(
                "已打开 \(target.displayName)。如果扩展页没有自动出现，请在浏览器地址栏输入 \(target.extensionPage)，然后加载 BrowserExtension 文件夹。",
                en: "Opened \(target.displayName). If the extensions page did not appear, enter \(target.extensionPage) in the browser address bar, then load the BrowserExtension folder."
            )
            statusIsError = false
        }
    }

    private func canLaunchDesktopAgent(_ target: DesktopAgentLaunchTarget) -> Bool {
        launcherURL(for: target) != nil && !isGenerating
    }

    private func canLaunchCLIAgent(_ target: CLIAgentLaunchTarget) -> Bool {
        cliLauncherURL(for: target) != nil && !isGenerating
    }

    private func launcherURL(for target: DesktopAgentLaunchTarget) -> URL? {
        guard let assets = lastGeneratedAssets else { return nil }
        let url = assets.rootURL
            .appendingPathComponent("Launchers", isDirectory: true)
            .appendingPathComponent(target.launcherFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func cliLauncherURL(for target: CLIAgentLaunchTarget) -> URL? {
        guard let assets = lastGeneratedAssets else { return nil }
        let url = assets.rootURL
            .appendingPathComponent("Launchers", isDirectory: true)
            .appendingPathComponent(target.launcherFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    private func launchCLIAgent(_ target: CLIAgentLaunchTarget) {
        guard let launcherURL = cliLauncherURL(for: target) else {
            statusMessage = localizer.t(
                "没有找到 \(target.displayName) 启动器。请先打开开关或重新生成配置。",
                en: "\(target.displayName) launcher was not found. Turn on the switch or regenerate the profile first."
            )
            statusIsError = true
            return
        }

        NSWorkspace.shared.open(launcherURL)
        statusMessage = localizer.t(
            "已打开 \(target.displayName)。这个终端会自动注入 TraceFence 语言、时区和本地探测覆盖。",
            en: "Opened \(target.displayName). This terminal injects TraceFence language, timezone, and local-probe overrides automatically."
        )
        statusIsError = false
    }

    private func launchDesktopAgent(_ target: DesktopAgentLaunchTarget, terminateExisting: Bool) {
        guard let launcherURL = launcherURL(for: target) else {
            statusMessage = localizer.t(
                "没有找到 \(target.displayName) 启动器。请先打开开关或重新生成配置。",
                en: "\(target.displayName) launcher was not found. Turn on the switch or regenerate the profile first."
            )
            statusIsError = true
            return
        }

        statusMessage = terminateExisting
            ? localizer.t("正在重启 \(target.displayName)...", en: "Restarting \(target.displayName)...")
            : localizer.t("正在打开 \(target.displayName)...", en: "Opening \(target.displayName)...")
        statusIsError = false

        DispatchQueue.global(qos: .userInitiated).async {
            var terminatedCount = 0
            var forceTerminatedCount = 0
            if terminateExisting {
                let runningApps = runningApplications(for: target)
                terminatedCount = runningApps.count
                runningApps.forEach { app in
                    _ = app.terminate()
                }

                if !waitUntilApplicationsExit(for: target, timeout: 2.5) {
                    let remainingApps = runningApplications(for: target)
                    forceTerminatedCount = remainingApps.count
                    remainingApps.forEach { app in
                        _ = app.forceTerminate()
                    }
                    _ = waitUntilApplicationsExit(for: target, timeout: 2.5)
                }
            }

            do {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/bin/zsh")
                process.arguments = [launcherURL.path]
                process.currentDirectoryURL = launcherURL.deletingLastPathComponent()
                try process.run()

                DispatchQueue.main.async {
                    statusMessage = terminateExisting
                        ? localizer.t("已关闭 \(terminatedCount) 个 \(target.displayName) 进程并重新打开。强制关闭 \(forceTerminatedCount) 个。", en: "Closed \(terminatedCount) \(target.displayName) processes and reopened it. Force-closed \(forceTerminatedCount).")
                        : localizer.t("已通过 TraceFence 打开 \(target.displayName)。", en: "Opened \(target.displayName) through TraceFence.")
                    statusIsError = false
                }
            } catch {
                DispatchQueue.main.async {
                    statusMessage = error.localizedDescription
                    statusIsError = true
                }
            }
        }
    }

    private func runningApplications(for target: DesktopAgentLaunchTarget) -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            let localizedName = app.localizedName ?? ""
            let bundleName = app.bundleURL?.lastPathComponent ?? ""
            return localizedName == target.appName
                || localizedName == target.displayName
                || localizedName.hasPrefix("\(target.appName) ")
                || localizedName.hasPrefix("\(target.appName)(")
                || bundleName == "\(target.appName).app"
                || bundleName.hasPrefix("\(target.appName) ")
        }
    }

    private func waitUntilApplicationsExit(for target: DesktopAgentLaunchTarget, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if runningApplications(for: target).isEmpty {
                return true
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        return runningApplications(for: target).isEmpty
    }

    private func browserApplicationURL(for target: BrowserExtensionTarget) -> URL? {
        let fileManager = FileManager.default
        let candidates = [
            URL(fileURLWithPath: "/Applications").appendingPathComponent("\(target.appName).app"),
            URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Applications/\(target.appName).app")
        ]
        for candidate in candidates where fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        return nil
    }

    private func setProfileEnabled(_ newValue: Bool) {
        guard SandboxPaths.isDirectDistribution else { return }
        enabled = newValue
        if newValue {
            enableCoreOverrides()
            coreOverridesMigrated = true
        }
        generateAssets(successMessage: newValue
            ? localizer.t("已启动。TraceFence 已自动生成本地 Profile。", en: "Started. TraceFence generated the local profile automatically.")
            : localizer.t("已停止。TraceFence 已写入停用状态。", en: "Stopped. TraceFence wrote the disabled profile state."))
    }

    private func restoreGeneratedState() {
        let assets = AgentGeoMirrorService.shared.generatedAssets(forProfileName: trimmed(profileName, fallback: "default"))
        if FileManager.default.fileExists(atPath: assets.rootURL.path) {
            lastGeneratedAssets = assets
        }
        guard SandboxPaths.isDirectDistribution else { return }
        if !enabled, lastGeneratedAssets != nil {
            generateAssets(successMessage: localizer.t("已刷新启动器。Agent 环境画像当前关闭，按钮会按普通方式启动 App。", en: "Launchers refreshed. Agent Environment Profile is off, so buttons launch apps normally."))
            return
        }
        if enabled {
            if !coreOverridesMigrated {
                enableCoreOverrides()
                coreOverridesMigrated = true
            }
            generateAssets(successMessage: lastGeneratedAssets == nil
                ? localizer.t("已启动。TraceFence 已自动生成本地 Profile。", en: "Started. TraceFence generated the local profile automatically.")
                : localizer.t("已启动。TraceFence 已刷新本地 Profile。", en: "Running. TraceFence refreshed the local profile."))
        }
    }

    private func enableCoreOverrides() {
        locationOverrideEnabled = true
        timezoneOverrideEnabled = true
        languageOverrideEnabled = true
        acceptLanguageOverrideEnabled = true
    }

    private func trimmed(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
