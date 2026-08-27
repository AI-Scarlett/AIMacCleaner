import Foundation

enum NetworkTrafficPacketDecoder {
    private enum LinkType {
        static let null: Int32 = 0
        static let ethernet: Int32 = 1
        static let rawBSD: Int32 = 12
        static let raw: Int32 = 101
        static let loop: Int32 = 108
        static let linuxCooked: Int32 = 113
    }

    static func decode(data: Data, linkType: Int32) -> NetworkTrafficDecodedPacket? {
        let bytes = [UInt8](data)
        guard let networkLayer = networkLayer(bytes: bytes, linkType: linkType) else { return nil }

        switch networkLayer.etherType {
        case 0x0800:
            return decodeIPv4(bytes: bytes, offset: networkLayer.offset)
        case 0x86DD:
            return decodeIPv6(bytes: bytes, offset: networkLayer.offset)
        case 0x0806:
            return NetworkTrafficDecodedPacket(
                protocolKind: .arp,
                source: NetworkTrafficEndpoint(host: "ARP", port: nil),
                destination: NetworkTrafficEndpoint(host: "ARP", port: nil),
                serviceName: "ARP",
                capturedLength: UInt32(clamping: bytes.count)
            )
        default:
            return nil
        }
    }

    private static func networkLayer(bytes: [UInt8], linkType: Int32) -> (offset: Int, etherType: UInt16)? {
        switch linkType {
        case LinkType.ethernet:
            guard bytes.count >= 14 else { return nil }
            var offset = 14
            var etherType = uint16(bytes, 12)
            while etherType == 0x8100 || etherType == 0x88A8 {
                guard bytes.count >= offset + 4 else { return nil }
                etherType = uint16(bytes, offset + 2)
                offset += 4
            }
            return (offset, etherType)
        case LinkType.null, LinkType.loop:
            guard bytes.count >= 5 else { return nil }
            let version = bytes[4] >> 4
            return (4, version == 6 ? 0x86DD : 0x0800)
        case LinkType.rawBSD, LinkType.raw:
            guard let first = bytes.first else { return nil }
            return (0, first >> 4 == 6 ? 0x86DD : 0x0800)
        case LinkType.linuxCooked:
            guard bytes.count >= 16 else { return nil }
            return (16, uint16(bytes, 14))
        default:
            return nil
        }
    }

    private static func decodeIPv4(bytes: [UInt8], offset: Int) -> NetworkTrafficDecodedPacket? {
        guard bytes.count >= offset + 20, bytes[offset] >> 4 == 4 else { return nil }
        let headerLength = Int(bytes[offset] & 0x0F) * 4
        guard headerLength >= 20, bytes.count >= offset + headerLength else { return nil }

        let sourceHost = ipv4(bytes[(offset + 12)..<(offset + 16)])
        let destinationHost = ipv4(bytes[(offset + 16)..<(offset + 20)])
        return decodeTransport(
            bytes: bytes,
            offset: offset + headerLength,
            protocolNumber: bytes[offset + 9],
            sourceHost: sourceHost,
            destinationHost: destinationHost
        )
    }

    private static func decodeIPv6(bytes: [UInt8], offset: Int) -> NetworkTrafficDecodedPacket? {
        guard bytes.count >= offset + 40, bytes[offset] >> 4 == 6 else { return nil }
        let sourceHost = ipv6(bytes[(offset + 8)..<(offset + 24)])
        let destinationHost = ipv6(bytes[(offset + 24)..<(offset + 40)])
        return decodeTransport(
            bytes: bytes,
            offset: offset + 40,
            protocolNumber: bytes[offset + 6],
            sourceHost: sourceHost,
            destinationHost: destinationHost
        )
    }

    private static func decodeTransport(
        bytes: [UInt8],
        offset: Int,
        protocolNumber: UInt8,
        sourceHost: String,
        destinationHost: String
    ) -> NetworkTrafficDecodedPacket? {
        let protocolKind: NetworkTrafficProtocol
        let sourcePort: UInt16?
        let destinationPort: UInt16?

        switch protocolNumber {
        case 6:
            guard bytes.count >= offset + 4 else { return nil }
            protocolKind = .tcp
            sourcePort = uint16(bytes, offset)
            destinationPort = uint16(bytes, offset + 2)
        case 17:
            guard bytes.count >= offset + 4 else { return nil }
            protocolKind = .udp
            sourcePort = uint16(bytes, offset)
            destinationPort = uint16(bytes, offset + 2)
        case 1, 58:
            protocolKind = .icmp
            sourcePort = nil
            destinationPort = nil
        default:
            protocolKind = .other
            sourcePort = nil
            destinationPort = nil
        }

        return NetworkTrafficDecodedPacket(
            protocolKind: protocolKind,
            source: NetworkTrafficEndpoint(host: sourceHost, port: sourcePort),
            destination: NetworkTrafficEndpoint(host: destinationHost, port: destinationPort),
            serviceName: NetworkTrafficServiceCatalog.name(
                sourcePort: sourcePort,
                destinationPort: destinationPort
            ),
            capturedLength: UInt32(clamping: bytes.count)
        )
    }

    private static func uint16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func ipv4(_ bytes: ArraySlice<UInt8>) -> String {
        bytes.map(String.init).joined(separator: ".")
    }

    private static func ipv6(_ bytes: ArraySlice<UInt8>) -> String {
        let values = Array(bytes)
        guard values.count == 16 else { return "::" }
        return stride(from: 0, to: 16, by: 2)
            .map { String(format: "%x", (UInt16(values[$0]) << 8) | UInt16(values[$0 + 1])) }
            .joined(separator: ":")
    }
}
