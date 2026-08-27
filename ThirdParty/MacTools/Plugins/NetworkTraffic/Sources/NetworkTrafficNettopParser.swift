import Foundation

struct NetworkTrafficNettopParser: Sendable {
    private(set) var columnIndexes: [String: Int] = [:]
    private(set) var currentProcessName: String?
    private(set) var descriptorIndex = 1

    mutating func parse(line: String) -> NetworkTrafficSocketSample? {
        let fields = Self.csvFields(line)
        guard fields.count >= 2 else { return nil }

        if fields.contains("interface") && fields.contains("bytes_in") && fields.contains("bytes_out") {
            columnIndexes.removeAll(keepingCapacity: true)
            for (index, name) in fields.enumerated() where !name.isEmpty && columnIndexes[name] == nil {
                columnIndexes[name] = index
            }
            descriptorIndex = fields.first == "time" ? 1 : 0
            return nil
        }

        guard fields.indices.contains(descriptorIndex) else { return nil }
        let descriptor = fields[descriptorIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !descriptor.isEmpty else { return nil }

        if !Self.isConnectionDescriptor(descriptor) {
            currentProcessName = Self.processName(from: descriptor)
            return nil
        }

        guard let endpoints = Self.endpoints(from: descriptor) else { return nil }
        let protocolKind: NetworkTrafficProtocol = descriptor.lowercased().hasPrefix("tcp") ? .tcp : .udp

        return NetworkTrafficSocketSample(
            protocolKind: protocolKind,
            local: endpoints.local,
            remote: endpoints.remote,
            interfaceName: value(named: "interface", fields: fields),
            processName: currentProcessName,
            state: value(named: "state", fields: fields),
            receivedBytes: unsignedValue(named: "bytes_in", fields: fields),
            sentBytes: unsignedValue(named: "bytes_out", fields: fields)
        )
    }

    private func value(named name: String, fields: [String]) -> String? {
        guard let index = columnIndexes[name], fields.indices.contains(index) else { return nil }
        let value = fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private func unsignedValue(named name: String, fields: [String]) -> UInt64 {
        guard let value = value(named: name, fields: fields) else { return 0 }
        return UInt64(value.filter(\.isNumber)) ?? 0
    }

    static func csvFields(_ line: String) -> [String] {
        var fields: [String] = []
        var field = ""
        var isQuoted = false
        var iterator = line.makeIterator()

        while let character = iterator.next() {
            if character == "\"" {
                isQuoted.toggle()
            } else if character == "," && !isQuoted {
                fields.append(field)
                field = ""
            } else {
                field.append(character)
            }
        }
        fields.append(field)
        return fields
    }

    static func parseBlacklist(_ text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let value = rawLine
                .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !value.isEmpty, value.count <= 255, seen.insert(value.lowercased()).inserted else { continue }
            result.append(value)
            if result.count == NetworkTrafficLimits.maximumBlacklistEntries { break }
        }
        return result
    }

    private static func isConnectionDescriptor(_ value: String) -> Bool {
        let lowercased = value.lowercased()
        return (lowercased.hasPrefix("tcp4 ") || lowercased.hasPrefix("tcp6 ")
            || lowercased.hasPrefix("udp4 ") || lowercased.hasPrefix("udp6 "))
            && value.contains("<->")
    }

    private static func processName(from descriptor: String) -> String {
        guard let separator = descriptor.lastIndex(of: "."),
              descriptor[descriptor.index(after: separator)...].allSatisfy(\.isNumber)
        else {
            return descriptor
        }
        return String(descriptor[..<separator])
    }

    private static func endpoints(from descriptor: String) -> (local: NetworkTrafficEndpoint, remote: NetworkTrafficEndpoint)? {
        guard let space = descriptor.firstIndex(of: " ") else { return nil }
        let pair = String(descriptor[descriptor.index(after: space)...]).components(separatedBy: "<->")
        guard pair.count == 2 else { return nil }
        return (endpoint(from: pair[0]), endpoint(from: pair[1]))
    }

    private static func endpoint(from rawValue: String) -> NetworkTrafficEndpoint {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let colon = value.lastIndex(of: ":"),
           let port = UInt16(value[value.index(after: colon)...]) {
            return NetworkTrafficEndpoint(host: String(value[..<colon]), port: port)
        }
        if let dot = value.lastIndex(of: "."),
           let port = UInt16(value[value.index(after: dot)...]) {
            return NetworkTrafficEndpoint(host: String(value[..<dot]), port: port)
        }
        return NetworkTrafficEndpoint(host: value, port: nil)
    }
}
