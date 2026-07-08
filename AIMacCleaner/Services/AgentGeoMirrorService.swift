import Foundation

struct AgentGeoMirrorProfile: Codable {
    var name: String
    var enabled: Bool
    var proxyURL: String
    var noProxy: String
    var countryCode: String
    var region: String
    var city: String
    var timezoneIdentifier: String
    var localeIdentifier: String
    var languages: [String]
    var acceptLanguage: String
    var latitude: Double
    var longitude: Double
    var accuracyMeters: Double
    var locationOverrideEnabled: Bool
    var timezoneOverrideEnabled: Bool
    var languageOverrideEnabled: Bool
    var acceptLanguageOverrideEnabled: Bool
    var browserExtensionEnabled: Bool
    var cliWrappersEnabled: Bool
    var desktopLaunchersEnabled: Bool
    var updatedAt: Date

    static let defaultProfile = AgentGeoMirrorProfile(
        name: "default",
        enabled: false,
        proxyURL: "http://127.0.0.1:7890",
        noProxy: "localhost,127.0.0.1,::1",
        countryCode: "US",
        region: "California",
        city: "San Francisco",
        timezoneIdentifier: "America/Los_Angeles",
        localeIdentifier: "en-US",
        languages: ["en-US", "en"],
        acceptLanguage: "en-US,en;q=0.9",
        latitude: 37.7749,
        longitude: -122.4194,
        accuracyMeters: 80,
        locationOverrideEnabled: true,
        timezoneOverrideEnabled: true,
        languageOverrideEnabled: true,
        acceptLanguageOverrideEnabled: true,
        browserExtensionEnabled: true,
        cliWrappersEnabled: true,
        desktopLaunchersEnabled: true,
        updatedAt: Date()
    )
}

struct AgentGeoMirrorDetectedProfile {
    let countryCode: String
    let region: String
    let city: String
    let timezoneIdentifier: String
    let localeIdentifier: String
    let languages: [String]
    let acceptLanguage: String
    let latitude: Double
    let longitude: Double
    let accuracyMeters: Double
}

struct AgentGeoMirrorGeneratedAssets {
    let rootURL: URL
    let envScriptURL: URL
    let binURL: URL
    let launchersURL: URL
    let browserExtensionURL: URL
    let readmeURL: URL
}

enum AgentGeoMirrorServiceError: LocalizedError {
    case directOnly
    case invalidProxyURL
    case refreshFailed

    var errorDescription: String? {
        switch self {
        case .directOnly:
            return "Agent Geo Mirror is only available in the direct TraceFence build."
        case .invalidProxyURL:
            return "Proxy URL must include a host and port, for example http://127.0.0.1:7890."
        case .refreshFailed:
            return "Unable to detect the proxy exit profile from the configured proxy."
        }
    }
}

final class AgentGeoMirrorService {
    static let shared = AgentGeoMirrorService()

    private let fileManager = FileManager.default
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private init() {}

    func profileFromDefaults(enabledOverride: Bool? = nil) -> AgentGeoMirrorProfile {
        let defaults = UserDefaults.standard
        let fallback = AgentGeoMirrorProfile.defaultProfile
        let languages = defaults.string(forKey: "agentGeoMirrorLanguages")?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty } ?? fallback.languages

        return AgentGeoMirrorProfile(
            name: defaults.string(forKey: "agentGeoMirrorProfileName") ?? fallback.name,
            enabled: enabledOverride ?? defaultsBool("agentGeoMirrorEnabled", fallback: fallback.enabled),
            proxyURL: defaults.string(forKey: "agentGeoMirrorProxyURL") ?? fallback.proxyURL,
            noProxy: defaults.string(forKey: "agentGeoMirrorNoProxy") ?? fallback.noProxy,
            countryCode: defaults.string(forKey: "agentGeoMirrorCountryCode") ?? fallback.countryCode,
            region: defaults.string(forKey: "agentGeoMirrorRegion") ?? fallback.region,
            city: defaults.string(forKey: "agentGeoMirrorCity") ?? fallback.city,
            timezoneIdentifier: defaults.string(forKey: "agentGeoMirrorTimezone") ?? fallback.timezoneIdentifier,
            localeIdentifier: defaults.string(forKey: "agentGeoMirrorLocale") ?? fallback.localeIdentifier,
            languages: languages.isEmpty ? fallback.languages : languages,
            acceptLanguage: defaults.string(forKey: "agentGeoMirrorAcceptLanguage") ?? fallback.acceptLanguage,
            latitude: defaultsDouble("agentGeoMirrorLatitude", fallback: fallback.latitude),
            longitude: defaultsDouble("agentGeoMirrorLongitude", fallback: fallback.longitude),
            accuracyMeters: defaultsDouble("agentGeoMirrorAccuracy", fallback: fallback.accuracyMeters),
            locationOverrideEnabled: defaultsBool("agentGeoMirrorLocationOverride", fallback: fallback.locationOverrideEnabled),
            timezoneOverrideEnabled: defaultsBool("agentGeoMirrorTimezoneOverride", fallback: fallback.timezoneOverrideEnabled),
            languageOverrideEnabled: defaultsBool("agentGeoMirrorLanguageOverride", fallback: fallback.languageOverrideEnabled),
            acceptLanguageOverrideEnabled: defaultsBool("agentGeoMirrorAcceptLanguageOverride", fallback: fallback.acceptLanguageOverrideEnabled),
            browserExtensionEnabled: defaultsBool("agentGeoMirrorBrowserExtension", fallback: fallback.browserExtensionEnabled),
            cliWrappersEnabled: defaultsBool("agentGeoMirrorCLIWrappers", fallback: fallback.cliWrappersEnabled),
            desktopLaunchersEnabled: defaultsBool("agentGeoMirrorDesktopLaunchers", fallback: fallback.desktopLaunchersEnabled),
            updatedAt: Date()
        )
    }

    func setEnabledFromDefaults(_ isEnabled: Bool) throws -> AgentGeoMirrorGeneratedAssets {
        UserDefaults.standard.set(isEnabled, forKey: "agentGeoMirrorEnabled")
        return try generateAssets(for: profileFromDefaults(enabledOverride: isEnabled))
    }

    func generatedAssets(forProfileName profileName: String) -> AgentGeoMirrorGeneratedAssets {
        let rootURL = URL(fileURLWithPath: SandboxPaths.shared.dataDirectory)
            .appendingPathComponent("AgentGeoMirror", isDirectory: true)
            .appendingPathComponent(safeFileName(profileName), isDirectory: true)
        return AgentGeoMirrorGeneratedAssets(
            rootURL: rootURL,
            envScriptURL: rootURL.appendingPathComponent("agent-env.sh"),
            binURL: rootURL.appendingPathComponent("bin", isDirectory: true),
            launchersURL: rootURL.appendingPathComponent("Launchers", isDirectory: true),
            browserExtensionURL: rootURL.appendingPathComponent("BrowserExtension", isDirectory: true),
            readmeURL: rootURL.appendingPathComponent("README.md")
        )
    }

    func generateAssets(for profile: AgentGeoMirrorProfile) throws -> AgentGeoMirrorGeneratedAssets {
        guard SandboxPaths.isDirectDistribution else {
            throw AgentGeoMirrorServiceError.directOnly
        }

        let assets = generatedAssets(forProfileName: profile.name)
        let rootURL = assets.rootURL
        let binURL = assets.binURL
        let launchersURL = assets.launchersURL
        let extensionURL = assets.browserExtensionURL

        try createDirectory(rootURL)
        try createDirectory(binURL)
        try createDirectory(launchersURL)
        try createDirectory(extensionURL)

        let refreshedProfile = profile.withUpdatedTimestamp()
        try writeProfileJSON(refreshedProfile, to: rootURL.appendingPathComponent("profile.json"))

        try writeExecutable(envScript(for: refreshedProfile), to: assets.envScriptURL)

        if refreshedProfile.cliWrappersEnabled {
            try writeCLIWrappers(for: refreshedProfile, rootURL: rootURL, binURL: binURL)
        }
        if refreshedProfile.desktopLaunchersEnabled {
            try writeDesktopLaunchers(for: refreshedProfile, rootURL: rootURL, launchersURL: launchersURL)
        }
        if refreshedProfile.browserExtensionEnabled {
            try writeBrowserExtension(for: refreshedProfile, extensionURL: extensionURL)
        }

        try readme(for: refreshedProfile).write(to: assets.readmeURL, atomically: true, encoding: .utf8)

        return AgentGeoMirrorGeneratedAssets(
            rootURL: rootURL,
            envScriptURL: assets.envScriptURL,
            binURL: binURL,
            launchersURL: launchersURL,
            browserExtensionURL: extensionURL,
            readmeURL: assets.readmeURL
        )
    }

    func refreshProfileThroughProxy(_ profile: AgentGeoMirrorProfile) async throws -> AgentGeoMirrorDetectedProfile {
        guard SandboxPaths.isDirectDistribution else {
            throw AgentGeoMirrorServiceError.directOnly
        }
        guard let session = makeSession(proxyURLString: profile.proxyURL) else {
            throw AgentGeoMirrorServiceError.invalidProxyURL
        }

        let endpoints = [
            URL(string: "https://ipapi.co/json/")!,
            URL(string: "https://ipwho.is/")!
        ]

        for endpoint in endpoints {
            do {
                let (data, response) = try await session.data(from: endpoint)
                guard let httpResponse = response as? HTTPURLResponse,
                      (200..<300).contains(httpResponse.statusCode) else {
                    continue
                }
                if endpoint.host?.contains("ipapi.co") == true,
                   let detected = try decodeIPAPI(data) {
                    return detected
                }
                if endpoint.host?.contains("ipwho.is") == true,
                   let detected = try decodeIPWhoIs(data) {
                    return detected
                }
            } catch {
                continue
            }
        }

        throw AgentGeoMirrorServiceError.refreshFailed
    }

    private func makeSession(proxyURLString: String) -> URLSession? {
        guard let proxyURL = URL(string: proxyURLString),
              let host = proxyURL.host,
              let port = proxyURL.port else {
            return nil
        }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15

        switch proxyURL.scheme?.lowercased() {
        case "http", "https":
            configuration.connectionProxyDictionary = [
                "HTTPEnable": 1,
                "HTTPProxy": host,
                "HTTPPort": port,
                "HTTPSEnable": 1,
                "HTTPSProxy": host,
                "HTTPSPort": port
            ]
        default:
            return nil
        }

        return URLSession(configuration: configuration)
    }

    private func decodeIPAPI(_ data: Data) throws -> AgentGeoMirrorDetectedProfile? {
        let response = try JSONDecoder().decode(IPAPIResponse.self, from: data)
        guard let countryCode = response.countryCode,
              let timezone = response.timezone,
              let latitude = response.latitude,
              let longitude = response.longitude else {
            return nil
        }
        let locale = localeBundle(countryCode: countryCode, timezone: timezone)
        return AgentGeoMirrorDetectedProfile(
            countryCode: countryCode.uppercased(),
            region: response.region ?? "",
            city: response.city ?? "",
            timezoneIdentifier: timezone,
            localeIdentifier: locale.localeIdentifier,
            languages: locale.languages,
            acceptLanguage: locale.acceptLanguage,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: 80
        )
    }

    private func decodeIPWhoIs(_ data: Data) throws -> AgentGeoMirrorDetectedProfile? {
        let response = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)
        guard response.success != false,
              let countryCode = response.countryCode,
              let timezone = response.timezone?.id,
              let latitude = response.latitude,
              let longitude = response.longitude else {
            return nil
        }
        let locale = localeBundle(countryCode: countryCode, timezone: timezone)
        return AgentGeoMirrorDetectedProfile(
            countryCode: countryCode.uppercased(),
            region: response.region ?? "",
            city: response.city ?? "",
            timezoneIdentifier: timezone,
            localeIdentifier: locale.localeIdentifier,
            languages: locale.languages,
            acceptLanguage: locale.acceptLanguage,
            latitude: latitude,
            longitude: longitude,
            accuracyMeters: 80
        )
    }

    private func writeProfileJSON(_ profile: AgentGeoMirrorProfile, to url: URL) throws {
        let data = try encoder.encode(profile)
        try data.write(to: url, options: .atomic)
    }

    private func defaultsBool(_ key: String, fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }

    private func defaultsDouble(_ key: String, fallback: Double) -> Double {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.double(forKey: key)
    }

    private func writeCLIWrappers(for profile: AgentGeoMirrorProfile, rootURL: URL, binURL: URL) throws {
        let tools: [(wrapper: String, command: String)] = [
            ("tf-claude", "claude"),
            ("tf-codex", "codex"),
            ("tf-gemini", "gemini"),
            ("tf-cursor-agent", "cursor-agent"),
            ("tf-opencode", "opencode"),
            ("tf-aider", "aider"),
            ("tf-qwen", "qwen"),
            ("tf-goose", "goose")
        ]

        for tool in tools {
            let script = """
            #!/bin/zsh
            set -e
            PROFILE_DIR=\(shellQuote(rootURL.path))
            source "$PROFILE_DIR/agent-env.sh"
            if ! command -v \(tool.command) >/dev/null 2>&1; then
              echo "TraceFence: command '\(tool.command)' was not found in PATH." >&2
              exit 127
            fi
            exec \(tool.command) "$@"
            """
            try writeExecutable(script, to: binURL.appendingPathComponent(tool.wrapper))
        }

        let genericScript = """
        #!/bin/zsh
        set -e
        if [[ $# -lt 1 ]]; then
          echo "Usage: tf-agent <command> [args...]" >&2
          exit 64
        fi
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        exec "$@"
        """
        try writeExecutable(genericScript, to: binURL.appendingPathComponent("tf-agent"))
    }

    private func writeDesktopLaunchers(for profile: AgentGeoMirrorProfile, rootURL: URL, launchersURL: URL) throws {
        let apps: [(file: String, appName: String, executable: String)] = [
            ("Claude", "Claude", "Claude"),
            ("Cursor", "Cursor", "Cursor"),
            ("Windsurf", "Windsurf", "Windsurf"),
            ("Trae", "Trae", "Trae"),
            ("Visual Studio Code", "Visual Studio Code", "Electron"),
            ("ChatGPT", "ChatGPT", "ChatGPT")
        ]

        for app in apps {
            let script = desktopLauncherScript(
                rootURL: rootURL,
                appName: app.appName,
                executable: app.executable
            )
            try writeExecutable(script, to: launchersURL.appendingPathComponent("Launch \(app.file).command"))
        }

        let browserScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Google Chrome",
            executable: "Google Chrome"
        )
        try writeExecutable(browserScript, to: launchersURL.appendingPathComponent("Launch Chrome with TraceFence Profile.command"))

        let edgeScript = browserLauncherScript(
            rootURL: rootURL,
            browserAppName: "Microsoft Edge",
            executable: "Microsoft Edge"
        )
        try writeExecutable(edgeScript, to: launchersURL.appendingPathComponent("Launch Edge with TraceFence Profile.command"))
    }

    private func writeBrowserExtension(for profile: AgentGeoMirrorProfile, extensionURL: URL) throws {
        try manifestJSON().write(to: extensionURL.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try profileJS(profile).write(to: extensionURL.appendingPathComponent("profile.js"), atomically: true, encoding: .utf8)
        try backgroundJS(profile).write(to: extensionURL.appendingPathComponent("background.js"), atomically: true, encoding: .utf8)
        try contentBridgeJS().write(to: extensionURL.appendingPathComponent("content_bridge.js"), atomically: true, encoding: .utf8)
        try mainInjectorJS().write(to: extensionURL.appendingPathComponent("main_injector.js"), atomically: true, encoding: .utf8)
        try popupHTML().write(to: extensionURL.appendingPathComponent("popup.html"), atomically: true, encoding: .utf8)
        try popupJS().write(to: extensionURL.appendingPathComponent("popup.js"), atomically: true, encoding: .utf8)
    }

    private func createDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    private func writeExecutable(_ content: String, to url: URL) throws {
        try content.write(to: url, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func envScript(for profile: AgentGeoMirrorProfile) -> String {
        var lines = [
            "#!/bin/zsh",
            "# Generated by TraceFence Agent Geo Mirror. Edit from TraceFence settings instead of hand editing this file.",
            "export TRACEFENCE_GEO_PROFILE_ENABLED=\(shellQuote(profile.enabled ? "1" : "0"))",
            "export TRACEFENCE_GEO_PROFILE_NAME=\(shellQuote(profile.name))",
            "export TRACEFENCE_COUNTRY=\(shellQuote(profile.countryCode.uppercased()))",
            "export TRACEFENCE_REGION=\(shellQuote(profile.region))",
            "export TRACEFENCE_CITY=\(shellQuote(profile.city))"
        ]

        if profile.enabled {
            if !profile.proxyURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("export HTTP_PROXY=\(shellQuote(profile.proxyURL))")
                lines.append("export HTTPS_PROXY=\(shellQuote(profile.proxyURL))")
                lines.append("export ALL_PROXY=\(shellQuote(profile.proxyURL))")
                lines.append("export http_proxy=\"$HTTP_PROXY\"")
                lines.append("export https_proxy=\"$HTTPS_PROXY\"")
                lines.append("export all_proxy=\"$ALL_PROXY\"")
            }
            if !profile.noProxy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                lines.append("export NO_PROXY=\(shellQuote(profile.noProxy))")
                lines.append("export no_proxy=\"$NO_PROXY\"")
            }
            if profile.timezoneOverrideEnabled {
                lines.append("export TZ=\(shellQuote(profile.timezoneIdentifier))")
            }
            if profile.languageOverrideEnabled {
                let posixLocale = profile.localeIdentifier.replacingOccurrences(of: "-", with: "_") + ".UTF-8"
                lines.append("export LANG=\(shellQuote(posixLocale))")
                lines.append("export LC_ALL=\(shellQuote(posixLocale))")
                lines.append("export LANGUAGE=\(shellQuote(profile.languages.joined(separator: ":")))")
                lines.append("export TRACEFENCE_LOCALE=\(shellQuote(profile.localeIdentifier))")
                lines.append("export TRACEFENCE_LANGUAGES=\(shellQuote(profile.languages.joined(separator: ",")))")
            }
            if profile.acceptLanguageOverrideEnabled {
                lines.append("export ACCEPT_LANGUAGE=\(shellQuote(profile.acceptLanguage))")
                lines.append("export TRACEFENCE_ACCEPT_LANGUAGE=\"$ACCEPT_LANGUAGE\"")
            }
            if profile.locationOverrideEnabled {
                lines.append("export TRACEFENCE_LATITUDE=\(shellQuote(String(profile.latitude)))")
                lines.append("export TRACEFENCE_LONGITUDE=\(shellQuote(String(profile.longitude)))")
                lines.append("export TRACEFENCE_ACCURACY_METERS=\(shellQuote(String(profile.accuracyMeters)))")
            }
        }

        return lines.joined(separator: "\n") + "\n"
    }

    private func desktopLauncherScript(rootURL: URL, appName: String, executable: String) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        CANDIDATES=(
          "/Applications/\(appName).app/Contents/MacOS/\(executable)"
          "$HOME/Applications/\(appName).app/Contents/MacOS/\(executable)"
        )
        for candidate in "${CANDIDATES[@]}"; do
          if [[ -x "$candidate" ]]; then
            exec "$candidate" "$@"
          fi
        done
        echo "TraceFence: \(appName).app was not found in /Applications or ~/Applications." >&2
        echo "TraceFence: falling back to macOS open; some environment variables may not be inherited by the app." >&2
        exec open -na \(shellQuote(appName)) --args "$@"
        """
    }

    private func browserLauncherScript(rootURL: URL, browserAppName: String, executable: String) -> String {
        """
        #!/bin/zsh
        set -e
        PROFILE_DIR=\(shellQuote(rootURL.path))
        source "$PROFILE_DIR/agent-env.sh"
        EXTENSION_DIR="$PROFILE_DIR/BrowserExtension"
        USER_DATA_DIR="$PROFILE_DIR/\(safeFileName(browserAppName))-Profile"
        mkdir -p "$USER_DATA_DIR"
        CANDIDATES=(
          "/Applications/\(browserAppName).app/Contents/MacOS/\(executable)"
          "$HOME/Applications/\(browserAppName).app/Contents/MacOS/\(executable)"
        )
        for candidate in "${CANDIDATES[@]}"; do
          if [[ -x "$candidate" ]]; then
            exec "$candidate" --user-data-dir="$USER_DATA_DIR" --load-extension="$EXTENSION_DIR" "$@"
          fi
        done
        echo "TraceFence: \(browserAppName).app was not found in /Applications or ~/Applications." >&2
        exit 66
        """
    }

    private func manifestJSON() -> String {
        """
        {
          "manifest_version": 3,
          "name": "TraceFence Agent Geo Mirror",
          "description": "Local browser environment profile generated by TraceFence.",
          "version": "1.0.0",
          "permissions": ["declarativeNetRequest", "storage"],
          "host_permissions": ["<all_urls>"],
          "background": {
            "service_worker": "background.js"
          },
          "content_scripts": [
            {
              "matches": ["<all_urls>"],
              "js": ["profile.js", "content_bridge.js"],
              "run_at": "document_start",
              "all_frames": true
            }
          ],
          "web_accessible_resources": [
            {
              "resources": ["main_injector.js"],
              "matches": ["<all_urls>"]
            }
          ],
          "action": {
            "default_title": "TraceFence Agent Geo Mirror",
            "default_popup": "popup.html"
          }
        }
        """
    }

    private func profileJS(_ profile: AgentGeoMirrorProfile) throws -> String {
        let json = try browserProfileJSON(profile)
        return "globalThis.TRACEFENCE_GEO_PROFILE = \(json);\n"
    }

    private func backgroundJS(_ profile: AgentGeoMirrorProfile) throws -> String {
        let acceptLanguage = javascriptString(profile.acceptLanguage)
        return """
        importScripts("profile.js");

        const APPLY_ACCEPT_LANGUAGE = \(profile.enabled && profile.acceptLanguageOverrideEnabled ? "true" : "false");
        const ACCEPT_LANGUAGE = \(acceptLanguage);
        const RULE_ID = 270801;

        async function syncHeaderRule() {
          if (!chrome.declarativeNetRequest) return;
          const addRules = APPLY_ACCEPT_LANGUAGE ? [{
            id: RULE_ID,
            priority: 1,
            action: {
              type: "modifyHeaders",
              requestHeaders: [
                { header: "Accept-Language", operation: "set", value: ACCEPT_LANGUAGE }
              ]
            },
            condition: {
              urlFilter: "|http",
              resourceTypes: [
                "main_frame", "sub_frame", "stylesheet", "script", "image", "font",
                "object", "xmlhttprequest", "ping", "csp_report", "media",
                "websocket", "other"
              ]
            }
          }] : [];
          await chrome.declarativeNetRequest.updateDynamicRules({
            removeRuleIds: [RULE_ID],
            addRules
          });
        }

        chrome.runtime.onInstalled.addListener(syncHeaderRule);
        chrome.runtime.onStartup.addListener(syncHeaderRule);
        syncHeaderRule();
        """
    }

    private func contentBridgeJS() -> String {
        """
        (() => {
          const profile = globalThis.TRACEFENCE_GEO_PROFILE;
          if (!profile || !profile.enabled) return;
          const script = document.createElement("script");
          script.src = chrome.runtime.getURL("main_injector.js");
          script.dataset.traceFenceProfile = JSON.stringify(profile);
          script.onload = () => script.remove();
          script.onerror = () => script.remove();
          (document.documentElement || document.head || document).prepend(script);
        })();
        """
    }

    private func mainInjectorJS() -> String {
        """
        (() => {
          const currentScript = document.currentScript;
          const rawProfile = currentScript?.dataset?.traceFenceProfile;
          if (!rawProfile) return;

          let profile;
          try {
            profile = JSON.parse(rawProfile);
          } catch (_) {
            return;
          }
          if (!profile.enabled) return;

          const NativeDateTimeFormat = Intl.DateTimeFormat;
          const NativeNumberFormat = Intl.NumberFormat;
          const NativeCollator = Intl.Collator;
          const nativeGetTimezoneOffset = Date.prototype.getTimezoneOffset;

          const defineGetter = (target, key, getter) => {
            try {
              Object.defineProperty(target, key, {
                configurable: true,
                enumerable: true,
                get: getter
              });
            } catch (_) {}
          };

          const timezoneOffsetFor = (date, timezone) => {
            try {
              const parts = new NativeDateTimeFormat("en-US", {
                timeZone: timezone,
                hourCycle: "h23",
                year: "numeric",
                month: "2-digit",
                day: "2-digit",
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit"
              }).formatToParts(date).reduce((acc, part) => {
                acc[part.type] = part.value;
                return acc;
              }, {});
              const asUTC = Date.UTC(
                Number(parts.year),
                Number(parts.month) - 1,
                Number(parts.day),
                Number(parts.hour),
                Number(parts.minute),
                Number(parts.second)
              );
              return Math.round((date.getTime() - asUTC) / 60000);
            } catch (_) {
              return nativeGetTimezoneOffset.call(date);
            }
          };

          if (profile.languageOverrideEnabled) {
            defineGetter(Navigator.prototype, "language", () => profile.localeIdentifier);
            defineGetter(Navigator.prototype, "languages", () => profile.languages.slice());
          }

          if (profile.locationOverrideEnabled && navigator.geolocation) {
            let nextWatchId = 7000;
            const watches = new Map();
            const makePosition = () => ({
              coords: {
                latitude: Number(profile.latitude),
                longitude: Number(profile.longitude),
                accuracy: Number(profile.accuracyMeters),
                altitude: null,
                altitudeAccuracy: null,
                heading: null,
                speed: null
              },
              timestamp: Date.now()
            });
            navigator.geolocation.getCurrentPosition = (success, error, options) => {
              if (typeof success === "function") {
                setTimeout(() => success(makePosition()), 0);
              }
            };
            navigator.geolocation.watchPosition = (success, error, options) => {
              const watchId = nextWatchId++;
              if (typeof success === "function") {
                const tick = () => success(makePosition());
                tick();
                watches.set(watchId, setInterval(tick, Math.max(1000, Number(options?.maximumAge || 10000))));
              }
              return watchId;
            };
            navigator.geolocation.clearWatch = (watchId) => {
              const timer = watches.get(watchId);
              if (timer) clearInterval(timer);
              watches.delete(watchId);
            };
          }

          if (profile.locationOverrideEnabled && navigator.permissions?.query) {
            const nativeQuery = navigator.permissions.query.bind(navigator.permissions);
            navigator.permissions.query = (descriptor) => {
              if (descriptor && descriptor.name === "geolocation") {
                return Promise.resolve({ state: "granted", onchange: null });
              }
              return nativeQuery(descriptor);
            };
          }

          if (profile.timezoneOverrideEnabled) {
            Date.prototype.getTimezoneOffset = function() {
              return timezoneOffsetFor(this, profile.timezoneIdentifier);
            };
          }

          if (profile.languageOverrideEnabled || profile.timezoneOverrideEnabled) {
            Intl.DateTimeFormat = function(locales, options) {
              const nextLocales = profile.languageOverrideEnabled && (locales === undefined || locales === null)
                ? profile.localeIdentifier
                : locales;
              const nextOptions = Object.assign({}, options || {});
              if (profile.timezoneOverrideEnabled && nextOptions.timeZone === undefined) {
                nextOptions.timeZone = profile.timezoneIdentifier;
              }
              return new NativeDateTimeFormat(nextLocales, nextOptions);
            };
            Intl.DateTimeFormat.prototype = NativeDateTimeFormat.prototype;
            Object.setPrototypeOf(Intl.DateTimeFormat, NativeDateTimeFormat);

            Intl.NumberFormat = function(locales, options) {
              const nextLocales = profile.languageOverrideEnabled && (locales === undefined || locales === null)
                ? profile.localeIdentifier
                : locales;
              return new NativeNumberFormat(nextLocales, options);
            };
            Intl.NumberFormat.prototype = NativeNumberFormat.prototype;
            Object.setPrototypeOf(Intl.NumberFormat, NativeNumberFormat);

            Intl.Collator = function(locales, options) {
              const nextLocales = profile.languageOverrideEnabled && (locales === undefined || locales === null)
                ? profile.localeIdentifier
                : locales;
              return new NativeCollator(nextLocales, options);
            };
            Intl.Collator.prototype = NativeCollator.prototype;
            Object.setPrototypeOf(Intl.Collator, NativeCollator);
          }
        })();
        """
    }

    private func popupHTML() -> String {
        """
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <style>
              body { width: 300px; margin: 0; padding: 14px; font: 13px -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; color: #0f172a; }
              h1 { font-size: 15px; margin: 0 0 10px; }
              .row { display: flex; justify-content: space-between; gap: 12px; padding: 6px 0; border-top: 1px solid #e5e7eb; }
              .key { color: #64748b; }
              .value { text-align: right; font-weight: 600; }
              .ok { color: #2563eb; }
            </style>
          </head>
          <body>
            <h1>TraceFence Agent Geo Mirror</h1>
            <div id="status"></div>
            <script src="profile.js"></script>
            <script src="popup.js"></script>
          </body>
        </html>
        """
    }

    private func popupJS() -> String {
        """
        const profile = globalThis.TRACEFENCE_GEO_PROFILE || {};
        const status = document.getElementById("status");
        const rows = [
          ["Enabled", profile.enabled ? "On" : "Off"],
          ["Country", profile.countryCode || "-"],
          ["City", profile.city || "-"],
          ["Timezone", profile.timezoneIdentifier || "-"],
          ["Locale", profile.localeIdentifier || "-"],
          ["Accept-Language", profile.acceptLanguage || "-"],
          ["Location", `${profile.latitude}, ${profile.longitude}`]
        ];
        status.innerHTML = rows.map(([key, value]) =>
          `<div class="row"><span class="key">${key}</span><span class="value">${value}</span></div>`
        ).join("");
        """
    }

    private func readme(for profile: AgentGeoMirrorProfile) -> String {
        """
        # TraceFence Agent Geo Mirror

        This profile is generated locally by TraceFence direct build. It does not modify macOS global language or timezone settings.

        ## What is generated

        - `agent-env.sh`: sourceable environment profile for proxy, timezone, locale, and coarse location metadata.
        - `bin/tf-*`: CLI wrappers such as `tf-claude`, `tf-codex`, and `tf-agent`.
        - `Launchers/*.command`: desktop launchers for Claude, Cursor, Windsurf, Trae, VS Code, ChatGPT, Chrome, and Edge.
        - `BrowserExtension`: unpacked Chromium extension that mirrors geolocation, timezone, locale, and Accept-Language in browser-visible APIs.

        ## Usage

        Add this to your shell when you want the profile for arbitrary commands:

        ```sh
        source \(shellQuote("agent-env.sh"))
        ```

        Or prepend the generated `bin` directory to your PATH:

        ```sh
        export PATH=\(shellQuote("bin")):$PATH
        tf-claude
        tf-codex
        tf-agent your-command --with --args
        ```

        For desktop apps, launch them through the generated `.command` files so the app process inherits the profile environment. Apps already running from Finder or Dock will not inherit this profile.

        For browsers, use the generated Chrome or Edge launcher, or load the `BrowserExtension` folder from `chrome://extensions` with Developer Mode enabled.

        ## Limits

        - CLI coverage depends on each tool respecting `HTTP_PROXY`, `HTTPS_PROXY`, `ALL_PROXY`, `TZ`, `LANG`, and `LC_ALL`.
        - Electron/AppKit desktop coverage is strongest when the generated launcher starts the real app binary. The fallback `open` path may not propagate all environment variables.
        - Browser API coverage applies to pages where the unpacked extension is enabled. Native apps do not use the browser extension.

        ## Current profile

        - Name: \(profile.name)
        - Proxy: \(profile.proxyURL)
        - Country: \(profile.countryCode.uppercased())
        - City: \(profile.city)
        - Timezone: \(profile.timezoneIdentifier)
        - Locale: \(profile.localeIdentifier)
        - Accept-Language: \(profile.acceptLanguage)
        """
    }

    private func browserProfileJSON(_ profile: AgentGeoMirrorProfile) throws -> String {
        let dictionary: [String: Any] = [
            "enabled": profile.enabled,
            "countryCode": profile.countryCode.uppercased(),
            "region": profile.region,
            "city": profile.city,
            "timezoneIdentifier": profile.timezoneIdentifier,
            "localeIdentifier": profile.localeIdentifier,
            "languages": profile.languages,
            "acceptLanguage": profile.acceptLanguage,
            "latitude": profile.latitude,
            "longitude": profile.longitude,
            "accuracyMeters": profile.accuracyMeters,
            "locationOverrideEnabled": profile.locationOverrideEnabled,
            "timezoneOverrideEnabled": profile.timezoneOverrideEnabled,
            "languageOverrideEnabled": profile.languageOverrideEnabled,
            "acceptLanguageOverrideEnabled": profile.acceptLanguageOverrideEnabled
        ]
        let data = try JSONSerialization.data(withJSONObject: dictionary, options: [.prettyPrinted, .sortedKeys])
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private func javascriptString(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2 else {
            return "\"\""
        }
        return String(json.dropFirst().dropLast())
    }

    private func safeFileName(_ rawName: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = rawName.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let name = String(scalars).trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return name.isEmpty ? "default" : name
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func localeBundle(countryCode: String, timezone: String) -> (localeIdentifier: String, languages: [String], acceptLanguage: String) {
        let country = countryCode.uppercased()
        let locale: String
        switch country {
        case "US": locale = "en-US"
        case "GB": locale = "en-GB"
        case "CA": locale = timezone.hasPrefix("America/") ? "en-CA" : "fr-CA"
        case "AU": locale = "en-AU"
        case "NZ": locale = "en-NZ"
        case "SG": locale = "en-SG"
        case "JP": locale = "ja-JP"
        case "KR": locale = "ko-KR"
        case "TW": locale = "zh-TW"
        case "HK": locale = "zh-HK"
        case "CN": locale = "zh-CN"
        case "DE": locale = "de-DE"
        case "FR": locale = "fr-FR"
        case "NL": locale = "nl-NL"
        case "ES": locale = "es-ES"
        case "IT": locale = "it-IT"
        case "BR": locale = "pt-BR"
        case "IN": locale = "en-IN"
        default: locale = "en-US"
        }
        let language = locale.split(separator: "-").first.map(String.init) ?? locale
        let languages = language == locale ? [locale] : [locale, language]
        let acceptLanguage = languages.enumerated().map { index, item -> String in
            index == 0 ? item : "\(item);q=\(String(format: "%.1f", max(0.1, 1.0 - Double(index) * 0.1)))"
        }.joined(separator: ",")
        return (locale, languages, acceptLanguage)
    }
}

private extension AgentGeoMirrorProfile {
    func withUpdatedTimestamp() -> AgentGeoMirrorProfile {
        var copy = self
        copy.updatedAt = Date()
        return copy
    }
}

private struct IPAPIResponse: Decodable {
    let city: String?
    let region: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: String?

    enum CodingKeys: String, CodingKey {
        case city
        case region
        case countryCode = "country_code"
        case latitude
        case longitude
        case timezone
    }
}

private struct IPWhoIsResponse: Decodable {
    let success: Bool?
    let city: String?
    let region: String?
    let countryCode: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: Timezone?

    struct Timezone: Decodable {
        let id: String?
    }

    enum CodingKeys: String, CodingKey {
        case success
        case city
        case region
        case countryCode = "country_code"
        case latitude
        case longitude
        case timezone
    }
}
