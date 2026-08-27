import XCTest
import MacToolsPluginKit
@testable import NetworkTrafficPlugin

final class NetworkTrafficParserTests: XCTestCase {
    func testNettopParserAssociatesConnectionWithCurrentProcess() throws {
        var parser = NetworkTrafficNettopParser()
        XCTAssertNil(parser.parse(line: "time,,interface,state,bytes_in,bytes_out,"))
        XCTAssertNil(parser.parse(line: "12:00:00.000000,WeChat.1007,,,1530955,820961,"))

        let sample = try XCTUnwrap(parser.parse(
            line: "12:00:00.000001,tcp4 192.168.1.2:61507<->117.89.177.107:443,en0,Established,4096,1024,"
        ))

        XCTAssertEqual(sample.protocolKind, .tcp)
        XCTAssertEqual(sample.processName, "WeChat")
        XCTAssertEqual(sample.interfaceName, "en0")
        XCTAssertEqual(sample.local, NetworkTrafficEndpoint(host: "192.168.1.2", port: 61_507))
        XCTAssertEqual(sample.remote, NetworkTrafficEndpoint(host: "117.89.177.107", port: 443))
        XCTAssertEqual(sample.receivedBytes, 4_096)
        XCTAssertEqual(sample.sentBytes, 1_024)
    }

    func testNettopParserSupportsFixedColumnOutputWithoutTimeField() throws {
        var parser = NetworkTrafficNettopParser()
        XCTAssertNil(parser.parse(line: ",interface,state,bytes_in,bytes_out,"))
        XCTAssertNil(parser.parse(line: "WeChat.1007,,,1530955,820961,"))

        let sample = try XCTUnwrap(parser.parse(
            line: "tcp4 192.168.1.2:61507<->117.89.177.107:443,en0,Established,4096,1024,"
        ))

        XCTAssertEqual(sample.processName, "WeChat")
        XCTAssertEqual(sample.interfaceName, "en0")
        XCTAssertEqual(sample.receivedBytes, 4_096)
        XCTAssertEqual(sample.sentBytes, 1_024)
    }

    func testBlacklistParserTrimsCommentsDeduplicatesAndBoundsValues() {
        let result = NetworkTrafficNettopParser.parseBlacklist("""
        # comment
        203.0.113.7
        203.0.113.7 # duplicate
        2001:db8::7

        """)

        XCTAssertEqual(result, ["203.0.113.7", "2001:db8::7"])
    }

    func testEthernetIPv4TCPPacketDecodesEndpointsAndService() throws {
        var packet = [UInt8](repeating: 0, count: 14 + 20 + 20)
        packet[12] = 0x08
        packet[13] = 0x00
        packet[14] = 0x45
        packet[23] = 6
        packet.replaceSubrange(26...29, with: [192, 168, 1, 2])
        packet.replaceSubrange(30...33, with: [93, 184, 216, 34])
        packet[34] = 0xC0
        packet[35] = 0x00
        packet[36] = 0x01
        packet[37] = 0xBB

        let decoded = try XCTUnwrap(NetworkTrafficPacketDecoder.decode(data: Data(packet), linkType: 1))
        XCTAssertEqual(decoded.protocolKind, .tcp)
        XCTAssertEqual(decoded.source, NetworkTrafficEndpoint(host: "192.168.1.2", port: 49_152))
        XCTAssertEqual(decoded.destination, NetworkTrafficEndpoint(host: "93.184.216.34", port: 443))
        XCTAssertEqual(decoded.serviceName, "HTTPS")
    }

    func testPCAPWriterProducesLittleEndianClassicHeaderAndFrame() throws {
        let frames = [NetworkTrafficRawFrame(
            timestampSeconds: 10,
            timestampMicroseconds: 20,
            originalLength: 4,
            data: Data([1, 2, 3, 4]),
            linkType: 1
        )]

        let data = try NetworkTrafficPCAPWriter.data(frames: frames)
        XCTAssertEqual(Array(data.prefix(4)), [0xD4, 0xC3, 0xB2, 0xA1])
        XCTAssertEqual(data.count, 24 + 16 + 4)
        XCTAssertEqual(Array(data.suffix(4)), [1, 2, 3, 4])
    }

    func testHostClassifierRecognizesLocalRanges() {
        XCTAssertTrue(NetworkTrafficHostClassifier.isLocal("192.168.1.2"))
        XCTAssertTrue(NetworkTrafficHostClassifier.isLocal("172.31.9.1"))
        XCTAssertTrue(NetworkTrafficHostClassifier.isLocal("fd00::1"))
        XCTAssertFalse(NetworkTrafficHostClassifier.isLocal("8.8.8.8"))
    }

    func testSystemLibpcapDiscoversAtLeastOneInterface() throws {
        let interfaces = try NetworkTrafficPcapWorker.interfaces()
        XCTAssertFalse(interfaces.isEmpty)
        XCTAssertTrue(interfaces.allSatisfy { !$0.name.isEmpty })
    }

    func testPCAPWriterRoundTripsThroughSystemLibpcap() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("network-traffic-\(UUID().uuidString).pcap")
        defer { try? FileManager.default.removeItem(at: url) }
        let frame = NetworkTrafficRawFrame(
            timestampSeconds: 10,
            timestampMicroseconds: 20,
            originalLength: 4,
            data: Data([1, 2, 3, 4]),
            linkType: 1
        )
        try NetworkTrafficPCAPWriter.data(frames: [frame]).write(to: url, options: .atomic)

        let worker = NetworkTrafficPcapWorker()
        let importedCount = try await withCheckedThrowingContinuation { continuation in
            worker.importFile(
                url: url,
                frameHandler: { _ in },
                completion: { continuation.resume(with: $0) }
            )
        }

        XCTAssertEqual(importedCount, 1)
    }
}

@MainActor
final class NetworkTrafficPluginContractTests: XCTestCase {
    func testPluginExposesPrimaryPanelAndWorkspace() {
        let plugin = NetworkTrafficPlugin()

        XCTAssertEqual(plugin.metadata.id, "network-traffic")
        XCTAssertNotNil(plugin.primaryPanel)
        XCTAssertNotNil(plugin.settingsPage)
        XCTAssertEqual(plugin.primaryPanelDescriptor.controlStyle, .button)
        XCTAssertTrue(plugin.permissionRequirements.isEmpty)
    }
}
