import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
import Foundation

private let quietZoneModules = 4
private let pixelsPerModule = 8
private let correctionLevel = "L"

private func base32Token(fromHex value: String) -> String? {
    guard value.count == 64 else { return nil }
    var bytes = [UInt8]()
    bytes.reserveCapacity(32)
    var index = value.startIndex
    while index < value.endIndex {
        let next = value.index(index, offsetBy: 2)
        guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
        bytes.append(byte)
        index = next
    }
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
    var output = [UInt8]()
    output.reserveCapacity(52)
    var buffer: UInt16 = 0
    var bitCount = 0
    for byte in bytes {
        buffer = (buffer << 8) | UInt16(byte)
        bitCount += 8
        while bitCount >= 5 {
            bitCount -= 5
            output.append(alphabet[Int((buffer >> bitCount) & 0x1f)])
        }
        buffer = bitCount == 0 ? 0 : buffer & UInt16((1 << bitCount) - 1)
    }
    if bitCount > 0 {
        output.append(alphabet[Int((buffer << (5 - bitCount)) & 0x1f)])
    }
    return String(decoding: output, as: UTF8.self)
}

private func hexToken(fromBase32 value: String) -> String? {
    guard value.count == 52 else { return nil }
    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567".utf8)
    let lookup = Dictionary(uniqueKeysWithValues: alphabet.enumerated().map { ($0.element, UInt16($0.offset)) })
    var output = [UInt8]()
    output.reserveCapacity(32)
    var buffer: UInt16 = 0
    var bitCount = 0
    for character in value.uppercased().utf8 {
        guard let bits = lookup[character] else { return nil }
        buffer = (buffer << 5) | bits
        bitCount += 5
        if bitCount >= 8 {
            bitCount -= 8
            output.append(UInt8((buffer >> bitCount) & 0xff))
        }
        buffer = bitCount == 0 ? 0 : buffer & UInt16((1 << bitCount) - 1)
    }
    guard output.count == 32, buffer == 0 else { return nil }
    return output.map { String(format: "%02x", $0) }.joined()
}

private func compactPairingURL(host: String, port: Int, token: String) -> String {
    guard let compactToken = base32Token(fromHex: token) else {
        fatalError("Test token is not a 256-bit hex token")
    }
    var components = URLComponents()
    components.scheme = "TF"
    components.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    if port != 17_895 {
        components.port = port
    }
    components.path = "/\(compactToken)"
    guard let value = components.string else { fatalError("Compact URL generation failed") }
    return value
}

private func decodeCompactPairingURL(_ text: String) -> (endpoint: String, token: String, port: Int)? {
    guard let components = URLComponents(string: text),
          components.scheme?.lowercased() == "tf",
          let host = components.host,
          !host.isEmpty else { return nil }
    let encodedToken = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    guard let token = hexToken(fromBase32: encodedToken) else { return nil }
    let port = components.port ?? 17_895
    var endpoint = URLComponents()
    endpoint.scheme = "http"
    endpoint.host = host.contains(":") && !host.hasPrefix("[") ? "[\(host)]" : host
    endpoint.port = port
    guard let endpointText = endpoint.string else { return nil }
    return (endpointText, token, port)
}

private func qrSource(for text: String) -> CGImage {
    let filter = CIFilter.qrCodeGenerator()
    filter.message = Data(text.utf8)
    filter.correctionLevel = correctionLevel
    guard let output = filter.outputImage else { fatalError("QR generation failed") }
    let extent = output.extent.integral
    let context = CIContext(options: [.useSoftwareRenderer: true])
    guard let image = context.createCGImage(output, from: extent) else {
        fatalError("QR source render failed")
    }
    return image
}

private func qrImage(for text: String) -> CGImage {
    let source = qrSource(for: text)
    let width = (source.width + quietZoneModules * 2) * pixelsPerModule
    let height = (source.height + quietZoneModules * 2) * pixelsPerModule
    guard let bitmap = CGContext(
        data: nil,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("QR bitmap allocation failed") }
    bitmap.setFillColor(NSColor.white.cgColor)
    bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
    bitmap.interpolationQuality = .none
    let inset = quietZoneModules * pixelsPerModule
    bitmap.draw(
        source,
        in: CGRect(
            x: inset,
            y: inset,
            width: source.width * pixelsPerModule,
            height: source.height * pixelsPerModule
        )
    )
    guard let image = bitmap.makeImage() else { fatalError("QR final render failed") }
    return image
}

private func presentedImage(_ image: CGImage, framePoints: Int, paddingPoints: Int, scale: Int) -> CGImage {
    let side = framePoints * scale
    let padding = paddingPoints * scale
    guard let bitmap = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("Presented QR bitmap allocation failed") }
    bitmap.setFillColor(NSColor.white.cgColor)
    bitmap.fill(CGRect(x: 0, y: 0, width: side, height: side))
    bitmap.interpolationQuality = .none
    bitmap.draw(
        image,
        in: CGRect(x: padding, y: padding, width: side - padding * 2, height: side - padding * 2)
    )
    guard let rendered = bitmap.makeImage() else { fatalError("Presented QR render failed") }
    return rendered
}

private func coreImageDecodedText(_ image: CGImage) -> String? {
    let detector = CIDetector(
        ofType: CIDetectorTypeQRCode,
        context: CIContext(options: [.useSoftwareRenderer: true]),
        options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]
    )
    return detector?.features(in: CIImage(cgImage: image))
        .compactMap { ($0 as? CIQRCodeFeature)?.messageString }
        .first
}

private struct LegacyPairingPayload: Decodable {
    let endpoint: String
    let token: String
    let port: Int?
    let service: String?
    let bonjourHostName: String?
}

let token = (0..<32).map { String(format: "%02x", $0) }.joined()
let compact = compactPairingURL(host: "192.168.3.5", port: 17_895, token: token)
let compactData = Data(compact.utf8)
guard let decodedCompact = decodeCompactPairingURL(compact),
      decodedCompact.endpoint == "http://192.168.3.5:17895",
      decodedCompact.token == token,
      decodedCompact.port == 17_895 else {
    fatalError("Compact production payload round-trip failed")
}
guard compactData.count <= 72 else {
    fatalError("Compact pairing payload regressed to \(compactData.count) bytes")
}

let ipv6Compact = compactPairingURL(host: "fd00:1234:5678::99", port: 19_001, token: token)
guard let decodedIPv6 = decodeCompactPairingURL(ipv6Compact),
      decodedIPv6.endpoint == "http://[fd00:1234:5678::99]:19001",
      decodedIPv6.token == token,
      decodedIPv6.port == 19_001 else {
    fatalError("IPv6 compact payload round-trip failed: \(ipv6Compact)")
}

let legacyJSON = """
{"version":1,"service":"TraceFence iOS Remote Control","endpoint":"http://192.168.3.5:17895","token":"\(token)","port":17895,"channel":"appStore","bonjourHostName":"TraceFence-Review-Mac.local"}
"""
guard let legacy = try? JSONDecoder().decode(LegacyPairingPayload.self, from: Data(legacyJSON.utf8)),
      legacy.endpoint == "http://192.168.3.5:17895",
      legacy.token == token,
      legacy.port == 17_895,
      legacy.service == "TraceFence iOS Remote Control",
      legacy.bonjourHostName == "TraceFence-Review-Mac.local" else {
    fatalError("Legacy JSON pairing payload compatibility failed")
}

let source = qrSource(for: compact)
guard source.width <= 31, source.height == source.width else {
    fatalError("QR density regressed to \(source.width)x\(source.height) modules")
}
let master = qrImage(for: compact)
let productionSizes = [168, 196]
var verifiedPresentations = [String]()
for framePoints in productionSizes {
    for scale in [1, 2] {
        let presented = presentedImage(master, framePoints: framePoints, paddingPoints: 4, scale: scale)
        guard coreImageDecodedText(presented) == compact else {
            fatalError("Core Image failed at \(framePoints)pt @\(scale)x")
        }
        verifiedPresentations.append("\(framePoints)pt@\(scale)x")
    }
}

print(
    "QR_DECODE_OK format=tf:// bytes=\(compactData.count) ipv6Bytes=\(Data(ipv6Compact.utf8).count) "
        + "modules=\(source.width)x\(source.height) correction=\(correctionLevel) "
        + "ui=\(verifiedPresentations.joined(separator: ",")) legacyJSON=ok"
)
