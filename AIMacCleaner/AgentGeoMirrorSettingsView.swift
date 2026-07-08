import AppKit
import SwiftUI

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
                        "打开开关后会自动生成并启用 Profile。已运行的 App 需要重新从启动器打开；CLI 使用 tf-* wrapper。",
                        en: "Turning this on automatically generates and enables the profile. Already-running apps need to be relaunched from launchers; CLIs use tf-* wrappers."
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
                subtitle: localizer.t("浏览器、桌面端和 CLI 分开生成，可按需要关闭。", en: "Browser, desktop, and CLI assets are generated separately.")
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

                Button {
                    openChromeExtensions()
                } label: {
                    Label(localizer.t("扩展页", en: "Extensions"), systemImage: "puzzlepiece.extension")
                }
                .buttonStyle(BrandButtonStyle(color: Theme.Colors.info, variant: .ghost, minHeight: 34))
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

    private func openChromeExtensions() {
        if let url = URL(string: "chrome://extensions/") {
            NSWorkspace.shared.open(url)
        }
    }

    private func setProfileEnabled(_ newValue: Bool) {
        guard SandboxPaths.isDirectDistribution else { return }
        enabled = newValue
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
        if enabled {
            if lastGeneratedAssets == nil {
                generateAssets(successMessage: localizer.t("已启动。TraceFence 已自动生成本地 Profile。", en: "Started. TraceFence generated the local profile automatically."))
            } else {
                statusMessage = localizer.t("已启动。新打开的 Agent 会使用这套 Profile。", en: "Running. Newly launched agents will use this profile.")
                statusIsError = false
            }
        }
    }

    private func trimmed(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}
