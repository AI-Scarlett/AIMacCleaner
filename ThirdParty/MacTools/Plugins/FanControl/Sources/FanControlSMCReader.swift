import Foundation
import IOKit

// MARK: - SMC Types

private typealias SMCBytes = (
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8,
    UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8
)

private struct SMCKeyInfo {
    var dataSize: UInt32 = 0
    var dataType: UInt32 = 0
    var dataAttributes: UInt8 = 0
}

private struct SMCVers {
    var major: UInt8 = 0; var minor: UInt8 = 0; var build: UInt8 = 0
    var reserved: UInt8 = 0; var release: UInt16 = 0
}

private struct SMCPLimit {
    var version: UInt16 = 0; var length: UInt16 = 0
    var cpuPLimit: UInt32 = 0; var gpuPLimit: UInt32 = 0; var memPLimit: UInt32 = 0
}

private struct SMCParam {
    var key: UInt32 = 0
    var vers = SMCVers()
    var pLimit = SMCPLimit()
    var keyInfo = SMCKeyInfo()
    var padding: UInt16 = 0
    var result: UInt8 = 0
    var status: UInt8 = 0
    var data8: UInt8 = 0
    var data32: UInt32 = 0
    var bytes: SMCBytes = (0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
}

private let kernelIndexSMC: UInt32 = 2
private let smcCmdReadBytes: UInt8 = 5
private let smcCmdReadKeyInfo: UInt8 = 9

// MARK: - FanControlSMCReader

@MainActor
final class FanControlSMCReader: FanControlSMCReading {
    // nonisolated(unsafe) so deinit (which is nonisolated) can close the connection
    // without crossing actor boundaries.
    nonisolated(unsafe) private var connection: io_connect_t = 0
    private var keyInfoCache: [UInt32: SMCKeyInfo] = [:]

    // Temperature keys by priority (Intel + Apple Silicon)
    private static let cpuTempKeys = [
        "TC0P", "TCXC", "TC0E", "TC0F", "TC0D",
        "Tp09", "Tp0T", "Tp01", "Tp05"
    ]

    var isConnected: Bool { connection != 0 }

    init() {
        _ = openConnection()
    }

    deinit {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    // MARK: - Connection

    @discardableResult
    func openConnection() -> Bool {
        guard connection == 0 else { return true }
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else {
            FanControlLog.smc.error("AppleSMC service not found")
            return false
        }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result == kIOReturnSuccess {
            FanControlLog.smc.debug("SMC connection opened")
            return true
        }
        FanControlLog.smc.error("IOServiceOpen failed: \(result)")
        return false
    }

    private func closeConnection() {
        if connection != 0 {
            IOServiceClose(connection)
            connection = 0
        }
    }

    func readSnapshot() -> FanSnapshot {
        guard connection != 0 else { return .empty }

        let count = readFanCount()
        guard count > 0 else { return .empty }

        var speeds: [Int] = []
        var minSpeeds: [Int] = []
        var maxSpeeds: [Int] = []

        for i in 0..<count {
            speeds.append(readFanRPM(key: String(format: "F%dAc", i)) ?? 0)
            minSpeeds.append(readFanRPM(key: String(format: "F%dMn", i)) ?? FanRPMLimits.fallbackMin)
            maxSpeeds.append(readFanRPM(key: String(format: "F%dMx", i)) ?? -1)
        }

        // Fill in missing max speeds using the highest successfully read max
        let bestMax = maxSpeeds.filter { $0 > 0 }.max()
        for i in maxSpeeds.indices where maxSpeeds[i] <= 0 {
            maxSpeeds[i] = bestMax ?? FanRPMLimits.fallbackMax
        }

        var cpuTemp: Double?
        for key in Self.cpuTempKeys {
            if let t = readSMCDouble(key: key), t > 0 && t < 150 {
                cpuTemp = t
                break
            }
        }

        return FanSnapshot(
            fanCount: count,
            fanSpeeds: speeds,
            fanMinSpeeds: minSpeeds,
            fanMaxSpeeds: maxSpeeds,
            cpuTemperature: cpuTemp
        )
    }

    // MARK: - Helpers

    private func readFanCount() -> Int {
        guard let raw = readSMCDouble(key: "FNum"), raw > 0 else { return 0 }
        return Int(raw)
    }

    private func readFanRPM(key: String) -> Int? {
        guard let val = readSMCDouble(key: key), val >= 0 else { return nil }
        return Int(val)
    }

    // MARK: - SMC Low-Level

    private func fourCC(_ s: String) -> UInt32 {
        var r: UInt32 = 0
        for (i, c) in s.utf8.prefix(4).enumerated() {
            r |= UInt32(c) << (8 * (3 - i))
        }
        return r
    }

    private func readSMCDouble(key: String) -> Double? {
        guard connection != 0 else { return nil }
        let keyCode = fourCC(key)

        // 1. Get key info (use cache)
        let info: SMCKeyInfo
        if let cached = keyInfoCache[keyCode] {
            info = cached
        } else {
            var inp = SMCParam(); inp.key = keyCode; inp.data8 = smcCmdReadKeyInfo
            var out = SMCParam(); var outSize = MemoryLayout<SMCParam>.size
            let r = IOConnectCallStructMethod(connection, kernelIndexSMC, &inp, MemoryLayout<SMCParam>.size, &out, &outSize)
            guard r == kIOReturnSuccess, out.result == 0,
                  out.keyInfo.dataSize > 0, out.keyInfo.dataSize <= 32 else { return nil }
            keyInfoCache[keyCode] = out.keyInfo
            info = out.keyInfo
        }

        // 2. Read bytes
        var inp = SMCParam()
        inp.key = keyCode
        inp.keyInfo.dataSize = info.dataSize
        inp.data8 = smcCmdReadBytes
        var out = SMCParam(); var outSize = MemoryLayout<SMCParam>.size
        let r = IOConnectCallStructMethod(connection, kernelIndexSMC, &inp, MemoryLayout<SMCParam>.size, &out, &outSize)
        guard r == kIOReturnSuccess, out.result == 0 else { return nil }

        return parseBytes(out.bytes, dataType: info.dataType, dataSize: info.dataSize)
    }

    private func parseBytes(_ bytes: SMCBytes, dataType: UInt32, dataSize: UInt32) -> Double? {
        let arr = [
            bytes.0,  bytes.1,  bytes.2,  bytes.3,
            bytes.4,  bytes.5,  bytes.6,  bytes.7,
            bytes.8,  bytes.9,  bytes.10, bytes.11,
            bytes.12, bytes.13, bytes.14, bytes.15,
            bytes.16, bytes.17, bytes.18, bytes.19,
            bytes.20, bytes.21, bytes.22, bytes.23,
            bytes.24, bytes.25, bytes.26, bytes.27,
            bytes.28, bytes.29, bytes.30, bytes.31
        ]

        let typeFLT  = fourCC("flt ")
        let typeSP78 = fourCC("sp78")
        let typeFPE2 = fourCC("fpe2")
        let typeUI8  = fourCC("ui8 ")
        let typeUI16 = fourCC("ui16")
        let typeUI32 = fourCC("ui32")

        switch dataType {
        case typeFLT:
            guard dataSize == 4 else { return nil }
            let val = arr.withUnsafeBufferPointer {
                $0.baseAddress!.withMemoryRebound(to: Float32.self, capacity: 1) { $0.pointee }
            }
            return Double(val)
        case typeSP78:
            guard dataSize == 2 else { return nil }
            let raw = (Int(arr[0]) << 8) | Int(arr[1])
            return Double(Int16(bitPattern: UInt16(raw))) / 256.0
        case typeFPE2:
            guard dataSize == 2 else { return nil }
            return Double((Int(arr[0]) << 6) + (Int(arr[1]) >> 2))
        case typeUI8:
            guard dataSize == 1 else { return nil }
            return Double(arr[0])
        case typeUI16:
            guard dataSize == 2 else { return nil }
            return Double((Int(arr[0]) << 8) | Int(arr[1]))
        case typeUI32:
            guard dataSize == 4 else { return nil }
            let val = (UInt32(arr[0]) << 24) | (UInt32(arr[1]) << 16) | (UInt32(arr[2]) << 8) | UInt32(arr[3])
            return Double(val)
        default:
            // Unknown type — try 2-byte big-endian as last resort
            if dataSize == 2 { return Double((Int(arr[0]) << 8) | Int(arr[1])) }
            return nil
        }
    }
}
