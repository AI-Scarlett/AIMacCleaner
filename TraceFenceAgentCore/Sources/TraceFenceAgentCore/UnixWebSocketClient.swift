import Foundation
import CryptoKit
import Darwin

final class UnixWebSocketClient {
    enum ClientError: LocalizedError {
        case socket(String)
        case invalidHandshake(String)
        case invalidFrame(String)
        case closed

        var errorDescription: String? {
            switch self {
            case .socket(let detail): return detail
            case .invalidHandshake(let detail): return "Invalid WebSocket handshake: \(detail)"
            case .invalidFrame(let detail): return "Invalid WebSocket frame: \(detail)"
            case .closed: return "WebSocket connection closed."
            }
        }
    }

    private let path: String
    private let stateLock = NSLock()
    private let writeLock = NSLock()
    private var descriptor: Int32 = -1
    private var readBuffer = Data()
    private let maximumMessageBytes = 8 * 1024 * 1024

    init(path: String) {
        self.path = path
    }

    var isConnected: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return descriptor >= 0
    }

    func connect() throws {
        close()
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw ClientError.socket(Self.lastPOSIXError("socket")) }

        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = path.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: address.sun_path) else {
            Darwin.close(fd)
            throw ClientError.socket("Codex daemon socket path is too long.")
        }
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: pathBytes.count) { destination in
                _ = pathBytes.withUnsafeBufferPointer { source in
                    memcpy(destination, source.baseAddress, pathBytes.count)
                }
            }
        }
        let connected = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connected == 0 else {
            let detail = Self.lastPOSIXError("connect")
            Darwin.close(fd)
            throw ClientError.socket(detail)
        }

        var timeout = timeval(tv_sec: 6, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        stateLock.lock()
        descriptor = fd
        readBuffer.removeAll(keepingCapacity: true)
        stateLock.unlock()

        do {
            try performHandshake(fd: fd)
            timeout = timeval(tv_sec: 0, tv_usec: 0)
            setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
            setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        } catch {
            close()
            throw error
        }
    }

    func sendText(_ text: String) throws {
        try sendFrame(opcode: 0x1, payload: Data(text.utf8))
    }

    func receiveText() throws -> String {
        var fragmentedOpcode: UInt8?
        var fragmentedPayload = Data()

        while true {
            let header = try readExact(2)
            let first = header[header.startIndex]
            let second = header[header.index(after: header.startIndex)]
            let finished = first & 0x80 != 0
            let opcode = first & 0x0F
            let masked = second & 0x80 != 0
            var length = UInt64(second & 0x7F)
            if length == 126 {
                let bytes = try readExact(2)
                length = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
            } else if length == 127 {
                let bytes = try readExact(8)
                length = bytes.reduce(0) { ($0 << 8) | UInt64($1) }
            }
            guard length <= maximumMessageBytes else {
                throw ClientError.invalidFrame("Message exceeds \(maximumMessageBytes) bytes.")
            }
            let mask = masked ? try readExact(4) : Data()
            var payload = try readExact(Int(length))
            if masked {
                let key = Array(mask)
                payload = Data(payload.enumerated().map { index, byte in byte ^ key[index % 4] })
            }

            switch opcode {
            case 0x0:
                guard fragmentedOpcode != nil else {
                    throw ClientError.invalidFrame("Unexpected continuation frame.")
                }
                fragmentedPayload.append(payload)
                guard fragmentedPayload.count <= maximumMessageBytes else {
                    throw ClientError.invalidFrame("Fragmented message is too large.")
                }
                if finished {
                    guard let text = String(data: fragmentedPayload, encoding: .utf8) else {
                        throw ClientError.invalidFrame("Text payload is not UTF-8.")
                    }
                    return text
                }
            case 0x1:
                if finished {
                    guard let text = String(data: payload, encoding: .utf8) else {
                        throw ClientError.invalidFrame("Text payload is not UTF-8.")
                    }
                    return text
                }
                fragmentedOpcode = opcode
                fragmentedPayload = payload
            case 0x2:
                if finished {
                    guard let text = String(data: payload, encoding: .utf8) else {
                        throw ClientError.invalidFrame("Binary JSON payload is not UTF-8.")
                    }
                    return text
                }
                fragmentedOpcode = opcode
                fragmentedPayload = payload
            case 0x8:
                throw ClientError.closed
            case 0x9:
                try sendFrame(opcode: 0xA, payload: payload)
            case 0xA:
                continue
            default:
                throw ClientError.invalidFrame("Unsupported opcode \(opcode).")
            }
        }
    }

    func close() {
        stateLock.lock()
        let fd = descriptor
        descriptor = -1
        readBuffer.removeAll(keepingCapacity: false)
        stateLock.unlock()
        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func performHandshake(fd: Int32) throws {
        var nonce = [UInt8](repeating: 0, count: 16)
        var generator = SystemRandomNumberGenerator()
        for index in nonce.indices { nonce[index] = UInt8.random(in: .min ... .max, using: &generator) }
        let key = Data(nonce).base64EncodedString()
        let request = [
            "GET / HTTP/1.1",
            "Host: localhost",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Key: \(key)",
            "Sec-WebSocket-Version: 13",
            "\r\n"
        ].joined(separator: "\r\n")
        try writeAll(Data(request.utf8), fd: fd)

        let delimiter = Data("\r\n\r\n".utf8)
        while readBuffer.range(of: delimiter) == nil {
            guard readBuffer.count < 32 * 1024 else {
                throw ClientError.invalidHandshake("Response headers are too large.")
            }
            var bytes = [UInt8](repeating: 0, count: 4_096)
            let count = Darwin.read(fd, &bytes, bytes.count)
            guard count > 0 else { throw ClientError.invalidHandshake(Self.lastPOSIXError("read")) }
            readBuffer.append(contentsOf: bytes.prefix(count))
        }
        guard let range = readBuffer.range(of: delimiter) else {
            throw ClientError.invalidHandshake("Missing response terminator.")
        }
        let headerData = Data(readBuffer[..<range.lowerBound])
        readBuffer = range.upperBound < readBuffer.endIndex ? Data(readBuffer[range.upperBound...]) : Data()
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            throw ClientError.invalidHandshake("Response headers are not UTF-8.")
        }
        let lines = headerText.components(separatedBy: "\r\n")
        guard lines.first?.contains(" 101 ") == true else {
            throw ClientError.invalidHandshake(lines.first ?? "Missing HTTP status.")
        }
        let accept = lines.dropFirst().compactMap { line -> String? in
            guard let separator = line.firstIndex(of: ":") else { return nil }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.caseInsensitiveCompare("Sec-WebSocket-Accept") == .orderedSame else { return nil }
            return line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }.first
        let source = Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)
        let expected = Data(Insecure.SHA1.hash(data: source)).base64EncodedString()
        guard accept == expected else {
            throw ClientError.invalidHandshake("Sec-WebSocket-Accept did not match.")
        }
    }

    private func sendFrame(opcode: UInt8, payload: Data) throws {
        guard payload.count <= maximumMessageBytes else {
            throw ClientError.invalidFrame("Outgoing message is too large.")
        }
        var frame = Data([0x80 | opcode])
        let count = payload.count
        if count < 126 {
            frame.append(UInt8(0x80 | count))
        } else if count <= Int(UInt16.max) {
            frame.append(0x80 | 126)
            var value = UInt16(count).bigEndian
            frame.append(Data(bytes: &value, count: MemoryLayout<UInt16>.size))
        } else {
            frame.append(0x80 | 127)
            var value = UInt64(count).bigEndian
            frame.append(Data(bytes: &value, count: MemoryLayout<UInt64>.size))
        }
        var generator = SystemRandomNumberGenerator()
        let mask = (0..<4).map { _ in UInt8.random(in: .min ... .max, using: &generator) }
        frame.append(contentsOf: mask)
        frame.append(contentsOf: payload.enumerated().map { index, byte in byte ^ mask[index % 4] })

        stateLock.lock()
        let fd = descriptor
        stateLock.unlock()
        guard fd >= 0 else { throw ClientError.closed }
        writeLock.lock()
        defer { writeLock.unlock() }
        try writeAll(frame, fd: fd)
    }

    private func readExact(_ count: Int) throws -> Data {
        guard count > 0 else { return Data() }
        while readBuffer.count < count {
            stateLock.lock()
            let fd = descriptor
            stateLock.unlock()
            guard fd >= 0 else { throw ClientError.closed }
            var bytes = [UInt8](repeating: 0, count: max(4_096, count - readBuffer.count))
            let received = Darwin.read(fd, &bytes, bytes.count)
            if received < 0, errno == EINTR { continue }
            guard received > 0 else { throw ClientError.socket(Self.lastPOSIXError("read")) }
            readBuffer.append(contentsOf: bytes.prefix(received))
        }
        let result = Data(readBuffer.prefix(count))
        readBuffer.removeFirst(count)
        return result
    }

    private func writeAll(_ data: Data, fd: Int32) throws {
        let success = data.withUnsafeBytes { rawBuffer -> Bool in
            guard var pointer = rawBuffer.baseAddress else { return false }
            var remaining = rawBuffer.count
            while remaining > 0 {
                let count = Darwin.write(fd, pointer, remaining)
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { return false }
                pointer = pointer.advanced(by: count)
                remaining -= count
            }
            return true
        }
        guard success else { throw ClientError.socket(Self.lastPOSIXError("write")) }
    }

    private static func lastPOSIXError(_ operation: String) -> String {
        "\(operation) failed (errno \(errno): \(String(cString: strerror(errno))))"
    }
}
