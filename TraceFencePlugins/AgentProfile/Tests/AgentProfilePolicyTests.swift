import XCTest
import MacToolsPluginKit
@testable import AgentProfilePlugin

final class AgentProfilePolicyTests: XCTestCase {
    func testLegacyConfigurationDecodesWithUniversalIntegrationsEnabled() throws {
        let data = try XCTUnwrap(
            """
            {
              "enabled": true,
              "name": "legacy",
              "proxyURL": "http://127.0.0.1:7897",
              "noProxy": "localhost,127.0.0.1,::1",
              "routeTrafficThroughProxy": true,
              "countryCode": "US",
              "region": "California",
              "city": "San Francisco",
              "timezoneIdentifier": "America/Los_Angeles",
              "localeIdentifier": "en-US",
              "languages": "en-US,en",
              "acceptLanguage": "en-US,en;q=0.9",
              "latitude": 37.7749,
              "longitude": -122.4194
            }
            """.data(using: .utf8)
        )
        let value = try JSONDecoder().decode(AgentProfileConfiguration.self, from: data)
        XCTAssertTrue(value.cliWrappersEnabled)
        XCTAssertTrue(value.desktopLaunchersEnabled)
        XCTAssertTrue(value.browserExtensionEnabled)
        XCTAssertTrue(value.locationOverrideEnabled)
        XCTAssertEqual(value.accuracyMeters, 80)
    }

    func testUniversalIntegrationCatalogIncludesMajorAgentsAndDSH() {
        let CLIIDs = Set(AgentProfileCLIIntegration.supported.map(\.id))
        XCTAssertTrue(["codex", "claude", "grok", "gemini", "antigravity", "opencode", "dsh"].allSatisfy(CLIIDs.contains))
        let desktopIDs = Set(AgentProfileDesktopIntegration.supported.map(\.id))
        XCTAssertTrue(["codex", "claude", "cursor", "antigravity"].allSatisfy(desktopIDs.contains))
    }

    @MainActor
    func testGeneratedProfileContainsUniversalWrappersLaunchersAndBrowserExtension() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentProfilePluginTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let suiteName = "AgentProfilePluginTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let context = PluginRuntimeContext(
            pluginID: "tracefence.tools.agent-profile.tests",
            storage: UserDefaultsPluginStorage(pluginID: "tracefence.tools.agent-profile.tests", userDefaults: defaults),
            supportDirectory: root
        )
        let controller = AgentProfileController(context: context)
        controller.configuration.enabled = true
        controller.configuration.cliWrappersEnabled = true
        controller.configuration.desktopLaunchersEnabled = true
        controller.configuration.browserExtensionEnabled = true
        controller.generateAssets()

        let assets = try XCTUnwrap(controller.lastGeneratedAssets)
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: assets.binURL.appendingPathComponent("tf-codex").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: assets.binURL.appendingPathComponent("tf-claude").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: assets.binURL.appendingPathComponent("tf-dsh").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: assets.launchersURL.appendingPathComponent("Launch Codex.command").path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: assets.shellLauncherURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.browserExtensionURL.appendingPathComponent("manifest.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: assets.contextURL.path))
        let readme = try String(contentsOf: assets.readmeURL, encoding: .utf8)
        XCTAssertTrue(readme.contains("DeepSeek Harness"))
        XCTAssertTrue(readme.contains("provider-neutral Agent profile"))
    }

    func testRoutedRequiresDifferentCompleteEgressPair() {
        XCTAssertEqual(
            AgentProfilePolicy.classifyEgress(
                routeTrafficThroughProxy: true,
                proxyURLIsValid: true,
                directIP: "203.0.113.1",
                proxyIP: "198.51.100.2"
            ),
            .routed
        )
        XCTAssertEqual(
            AgentProfilePolicy.classifyEgress(
                routeTrafficThroughProxy: true,
                proxyURLIsValid: true,
                directIP: "203.0.113.1",
                proxyIP: "203.0.113.1"
            ),
            .sameAsDirect
        )
    }

    func testEqualEgressWithLocalTunnelIsRoutedInsteadOfReportedAsLeak() {
        XCTAssertEqual(
            AgentProfilePolicy.classifyEgress(
                routeTrafficThroughProxy: true,
                proxyURLIsValid: true,
                directIP: "203.0.113.1",
                proxyIP: "203.0.113.1",
                localTunnelDetected: true
            ),
            .routed
        )
    }

    func testMissingOrInvalidProxyNeverReportsRouted() {
        XCTAssertEqual(
            AgentProfilePolicy.classifyEgress(
                routeTrafficThroughProxy: false,
                proxyURLIsValid: true,
                directIP: "203.0.113.1",
                proxyIP: "198.51.100.2"
            ),
            .proxyDisabled
        )
        XCTAssertEqual(
            AgentProfilePolicy.classifyEgress(
                routeTrafficThroughProxy: true,
                proxyURLIsValid: false,
                directIP: "203.0.113.1",
                proxyIP: nil
            ),
            .proxyInvalid
        )
        XCTAssertEqual(
            AgentProfilePolicy.classifyEgress(
                routeTrafficThroughProxy: true,
                proxyURLIsValid: true,
                directIP: "203.0.113.1",
                proxyIP: nil
            ),
            .proxyUnavailable
        )
    }

    func testProviderEligibilityIsNeverInferredFromLocalEgress() {
        for status in [
            AgentProfileEgressStatus.notTested,
            .proxyDisabled,
            .proxyInvalid,
            .proxyUnavailable,
            .sameAsDirect,
            .routed
        ] {
            XCTAssertFalse(AgentProfilePolicy.mayClaimProviderEligibility(from: status))
        }
    }

    func testAntigravityRouteInspectorDetectsEndpointOverrideAndProxySuppression() {
        let value = AgentProfileAntigravityRouteInspector.classify(
            commandPath: "/tmp/agy",
            launcherText: """
            #!/bin/bash
            export CLOUD_CODE_URL=\"http://127.0.0.1:25819\"
            unset HTTP_PROXY HTTPS_PROXY ALL_PROXY
            exec agy.real \"$@\"
            """
        )
        XCTAssertEqual(value.status, .endpointOverridden)
        XCTAssertTrue(value.details.contains("clears proxy"))
    }

    func testAntigravityRouteInspectorAcceptsStandardEntrypoint() {
        let value = AgentProfileAntigravityRouteInspector.classify(
            commandPath: "/tmp/agy",
            launcherText: "#!/bin/bash\nexec /usr/local/bin/agy.real \"$@\"\n"
        )
        XCTAssertEqual(value.status, .officialPath)
    }

}
