import Foundation

final class NetworkTrafficNettopMonitor: @unchecked Sendable {
    typealias SampleHandler = @Sendable (NetworkTrafficSocketSample) -> Void
    typealias FailureHandler = @Sendable (String) -> Void

    private let lock = NSLock()
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var parser = NetworkTrafficNettopParser()
    private var pendingOutput = ""
    private var observedHeaderCount = 0

    func start(
        sampleHandler: @escaping SampleHandler,
        failureHandler: @escaping FailureHandler
    ) throws {
        stop()

        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        process.arguments = [
            "-L", "0",
            "-d",
            "-n",
            "-x",
            "-s", "1",
            "-J", "time,interface,state,bytes_in,bytes_out"
        ]
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.consume(text, sampleHandler: sampleHandler)
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            let bounded = String(text.prefix(1_000)).trimmingCharacters(in: .whitespacesAndNewlines)
            if !bounded.isEmpty { failureHandler(bounded) }
        }
        process.terminationHandler = { process in
            guard process.terminationStatus != 0, process.terminationReason != .uncaughtSignal else { return }
            failureHandler("nettop exited with status \(process.terminationStatus)")
        }

        lock.lock()
        self.process = process
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe
        parser = NetworkTrafficNettopParser()
        pendingOutput = ""
        observedHeaderCount = 0
        lock.unlock()

        do {
            try process.run()
        } catch {
            stop()
            throw error
        }
    }

    func stop() {
        lock.lock()
        let currentProcess = process
        process = nil
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        outputPipe = nil
        errorPipe = nil
        pendingOutput = ""
        observedHeaderCount = 0
        lock.unlock()

        guard let currentProcess, currentProcess.isRunning else { return }
        currentProcess.terminate()
    }

    private func consume(_ text: String, sampleHandler: @escaping SampleHandler) {
        lock.lock()
        pendingOutput.append(text)
        var lines = pendingOutput.components(separatedBy: .newlines)
        pendingOutput = lines.popLast() ?? ""
        var parsed: [NetworkTrafficSocketSample] = []
        for line in lines {
            if line.hasPrefix("time,") || line.hasPrefix(",interface,") {
                observedHeaderCount += 1
            }
            if let sample = parser.parse(line: line) {
                // In delta mode nettop's first sample still contains the existing cumulative
                // socket counters. Ignore that baseline so the dashboard measures traffic
                // observed after the user pressed Start.
                if observedHeaderCount >= 2 {
                    parsed.append(sample)
                }
            }
        }
        lock.unlock()

        for sample in parsed {
            sampleHandler(sample)
        }
    }
}

final class NetworkTrafficPcapWorker: @unchecked Sendable {
    typealias FrameHandler = @Sendable (NetworkTrafficRawFrame) -> Void
    typealias StartedHandler = @Sendable (Int32) -> Void
    typealias CompletionHandler = @Sendable (Result<Int, Error>) -> Void

    enum WorkerError: LocalizedError {
        case openFailed(String)
        case captureFailed(String)
        case invalidFile(String)

        var errorDescription: String? {
            switch self {
            case let .openFailed(message), let .captureFailed(message), let .invalidFile(message):
                message
            }
        }
    }

    private let queue = DispatchQueue(label: "com.tracefence.network-traffic.pcap", qos: .userInitiated)
    private let lock = NSLock()
    private var handle: TFPcapHandle?
    private var sessionGeneration = 0

    func startLive(
        interfaceName: String,
        filter: String,
        started: @escaping StartedHandler,
        frameHandler: @escaping FrameHandler,
        completion: @escaping CompletionHandler
    ) {
        stop()
        let session = beginSession()
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let handle = try self.openLive(interfaceName: interfaceName, filter: filter)
                self.setHandle(handle)
                let linkType = tf_pcap_datalink(handle)
                started(linkType)
                let count = try self.readLoop(
                    handle: handle,
                    linkType: linkType,
                    maximumPackets: nil,
                    session: session,
                    frameHandler: frameHandler
                )
                self.close(handle)
                completion(.success(count))
            } catch {
                self.closeCurrentHandle()
                completion(.failure(error))
            }
        }
    }

    func importFile(
        url: URL,
        frameHandler: @escaping FrameHandler,
        completion: @escaping CompletionHandler
    ) {
        stop()
        let session = beginSession()
        queue.async { [weak self] in
            guard let self else { return }
            do {
                let handle = try self.openOffline(url: url)
                self.setHandle(handle)
                let linkType = tf_pcap_datalink(handle)
                guard linkType >= 0 else {
                    throw WorkerError.invalidFile("The capture file has no supported link-layer type.")
                }
                let count = try self.readLoop(
                    handle: handle,
                    linkType: linkType,
                    maximumPackets: NetworkTrafficLimits.maximumRawFrames + 1,
                    session: session,
                    frameHandler: frameHandler
                )
                self.close(handle)
                completion(.success(count))
            } catch {
                self.closeCurrentHandle()
                completion(.failure(error))
            }
        }
    }

    func stop() {
        lock.lock()
        sessionGeneration &+= 1
        let currentHandle = handle
        lock.unlock()
        if let currentHandle {
            tf_pcap_break_loop(currentHandle)
        }
    }

    static func interfaces() throws -> [NetworkTrafficInterface] {
        var output = [CChar](repeating: 0, count: 64 * 1_024)
        var error = [CChar](repeating: 0, count: 1_024)
        let status = tf_pcap_list_devices(&output, output.count, &error, error.count)
        guard status >= 0 else {
            throw WorkerError.captureFailed(string(from: error))
        }

        return string(from: output)
            .split(whereSeparator: \.isNewline)
            .compactMap { line in
                let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
                guard let name = parts.first, !name.isEmpty else { return nil }
                let flags = parts.count > 1 ? UInt32(parts[1]) ?? 0 : 0
                let description = parts.count > 2 && !parts[2].isEmpty ? String(parts[2]) : nil
                return NetworkTrafficInterface(
                    id: String(name),
                    name: String(name),
                    description: description,
                    isLoopback: (flags & 0x1) != 0,
                    isUp: (flags & 0x2) != 0
                )
            }
            .sorted {
                if $0.isUp != $1.isUp { return $0.isUp && !$1.isUp }
                if $0.isLoopback != $1.isLoopback { return !$0.isLoopback && $1.isLoopback }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    private func openLive(interfaceName: String, filter: String) throws -> TFPcapHandle {
        var error = [CChar](repeating: 0, count: 1_024)
        let handle = interfaceName.withCString { interfacePointer in
            filter.withCString { filterPointer in
                tf_pcap_open_live(
                    interfacePointer,
                    filterPointer,
                    65_535,
                    250,
                    &error,
                    error.count
                )
            }
        }
        guard let handle else { throw WorkerError.openFailed(Self.string(from: error)) }
        return handle
    }

    private func openOffline(url: URL) throws -> TFPcapHandle {
        var error = [CChar](repeating: 0, count: 1_024)
        let handle = url.path.withCString { pathPointer in
            tf_pcap_open_offline(pathPointer, &error, error.count)
        }
        guard let handle else { throw WorkerError.openFailed(Self.string(from: error)) }
        return handle
    }

    private func readLoop(
        handle: TFPcapHandle,
        linkType: Int32,
        maximumPackets: Int?,
        session: Int,
        frameHandler: @escaping FrameHandler
    ) throws -> Int {
        var packetBuffer = [UInt8](repeating: 0, count: 65_535)
        var count = 0

        while !isCancelled(session: session) {
            if let maximumPackets, count >= maximumPackets { break }
            var capturedLength: UInt32 = 0
            var originalLength: UInt32 = 0
            var timestampSeconds: Int64 = 0
            var timestampMicroseconds: Int32 = 0
            var error = [CChar](repeating: 0, count: 1_024)

            let status = tf_pcap_next_packet(
                handle,
                &packetBuffer,
                UInt32(packetBuffer.count),
                &capturedLength,
                &originalLength,
                &timestampSeconds,
                &timestampMicroseconds,
                &error,
                error.count
            )
            switch status {
            case 1:
                let data = Data(packetBuffer.prefix(Int(capturedLength)))
                frameHandler(NetworkTrafficRawFrame(
                    timestampSeconds: timestampSeconds,
                    timestampMicroseconds: timestampMicroseconds,
                    originalLength: originalLength,
                    data: data,
                    linkType: linkType
                ))
                count += 1
            case 0:
                continue
            case -2:
                return count
            default:
                throw WorkerError.captureFailed(Self.string(from: error))
            }
        }
        return count
    }

    private func beginSession() -> Int {
        lock.lock()
        defer { lock.unlock() }
        sessionGeneration &+= 1
        return sessionGeneration
    }

    private func isCancelled(session: Int) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return session != sessionGeneration
    }

    private func setHandle(_ value: TFPcapHandle?) {
        lock.lock()
        handle = value
        lock.unlock()
    }

    private func close(_ value: TFPcapHandle) {
        lock.lock()
        if handle == value { handle = nil }
        lock.unlock()
        tf_pcap_close(value)
    }

    private func closeCurrentHandle() {
        lock.lock()
        let value = handle
        handle = nil
        lock.unlock()
        if let value { tf_pcap_close(value) }
    }

    private static func string(from buffer: [CChar]) -> String {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(decoding: bytes, as: UTF8.self)
    }
}

enum NetworkTrafficPCAPWriter {
    enum WriterError: LocalizedError {
        case noFrames
        case mixedLinkTypes

        var errorDescription: String? {
            switch self {
            case .noFrames:
                "No raw packets are available to export."
            case .mixedLinkTypes:
                "Captured packets use more than one link-layer type."
            }
        }
    }

    static func data(frames: [NetworkTrafficRawFrame]) throws -> Data {
        guard let first = frames.first else { throw WriterError.noFrames }
        guard frames.allSatisfy({ $0.linkType == first.linkType }) else { throw WriterError.mixedLinkTypes }

        var result = Data()
        append(UInt32(0xA1B2C3D4), to: &result)
        append(UInt16(2), to: &result)
        append(UInt16(4), to: &result)
        append(Int32(0), to: &result)
        append(UInt32(0), to: &result)
        append(UInt32(65_535), to: &result)
        append(UInt32(bitPattern: first.linkType), to: &result)

        for frame in frames {
            append(UInt32(clamping: frame.timestampSeconds), to: &result)
            append(UInt32(clamping: frame.timestampMicroseconds), to: &result)
            append(UInt32(clamping: frame.data.count), to: &result)
            append(frame.originalLength, to: &result)
            result.append(frame.data)
        }
        return result
    }

    private static func append<T: FixedWidthInteger>(_ value: T, to data: inout Data) {
        var littleEndian = value.littleEndian
        withUnsafeBytes(of: &littleEndian) { data.append(contentsOf: $0) }
    }
}
