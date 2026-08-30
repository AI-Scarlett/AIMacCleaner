import XCTest
@testable import AgentProfilePlugin

final class AgentProfilePolicyTests: XCTestCase {
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
}
