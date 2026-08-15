import CryptoKit
import Foundation

struct CodexDataImage: Equatable, Sendable {
    let mimeType: String
    let subtype: String
    let fileExtension: String
    let bytes: Data
    let sha256: String
    let originalCharacterCount: Int

    var dataURL: String {
        "data:\(mimeType);base64,\(bytes.base64EncodedString())"
    }

    static func parse(_ value: String) throws -> CodexDataImage? {
        guard value.hasPrefix("data:image/") else { return nil }
        guard let marker = value.range(of: ";base64,") else {
            throw CodexMediaCleanupError.invalidDataImage
        }

        let mimeType = String(value[value.index(value.startIndex, offsetBy: 5)..<marker.lowerBound]).lowercased()
        let subtype = String(mimeType.dropFirst("image/".count))
        guard !subtype.isEmpty,
              subtype.range(of: #"^[a-z0-9.+-]+$"#, options: .regularExpression) != nil else {
            throw CodexMediaCleanupError.invalidDataImage
        }

        let payload = value[marker.upperBound...]
        var containsWhitespace = false
        var encodedByteCount = 0
        var paddingCount = 0
        var sawPadding = false
        for byte in payload.utf8 {
            if byte == 9 || byte == 10 || byte == 13 || byte == 32 {
                containsWhitespace = true
                continue
            }
            let isBase64 = (byte >= 65 && byte <= 90)
                || (byte >= 97 && byte <= 122)
                || (byte >= 48 && byte <= 57)
                || byte == 43
                || byte == 47
            if byte == 61 {
                sawPadding = true
                paddingCount += 1
                guard paddingCount <= 2 else { throw CodexMediaCleanupError.invalidDataImage }
            } else {
                guard isBase64, !sawPadding else { throw CodexMediaCleanupError.invalidDataImage }
            }
            encodedByteCount += 1
        }
        guard encodedByteCount > 0 else { throw CodexMediaCleanupError.invalidDataImage }
        let encoded: String
        if containsWhitespace {
            encoded = String(payload.unicodeScalars.filter { !$0.properties.isWhitespace })
        } else {
            encoded = String(payload)
        }
        guard let bytes = Data(base64Encoded: encoded),
              !bytes.isEmpty else {
            throw CodexMediaCleanupError.invalidDataImage
        }

        let ext: String
        switch subtype {
        case "jpeg", "jpg": ext = "jpg"
        case "tif", "tiff": ext = "tiff"
        case "svg+xml": ext = "svg"
        case "avif", "bmp", "gif", "heic", "heif", "png", "webp": ext = subtype
        default: throw CodexMediaCleanupError.unsupportedImageType(subtype)
        }

        return CodexDataImage(
            mimeType: mimeType,
            subtype: subtype,
            fileExtension: ext,
            bytes: bytes,
            sha256: Self.sha256(bytes),
            originalCharacterCount: value.utf8.count
        )
    }

    static func fromCanonicalFile(_ url: URL, mediaRoot: URL) throws -> CodexDataImage {
        let root = mediaRoot.resolvingSymlinksInPath().standardizedFileURL
        let file = url.resolvingSymlinksInPath().standardizedFileURL
        guard file.path.hasPrefix(root.path + "/") else {
            throw CodexMediaCleanupError.unsafeMediaReference(url.path)
        }
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else {
            throw CodexMediaCleanupError.missingMediaObject(file.path)
        }

        let ext = file.pathExtension.lowercased()
        let subtype: String
        switch ext {
        case "jpg", "jpeg": subtype = "jpeg"
        case "tif", "tiff": subtype = "tiff"
        case "svg": subtype = "svg+xml"
        case "avif", "bmp", "gif", "heic", "heif", "png", "webp": subtype = ext
        default: throw CodexMediaCleanupError.unsupportedImageType(ext)
        }

        let bytes = try Data(contentsOf: file, options: [.mappedIfSafe])
        let digest = sha256(bytes)
        guard file.deletingPathExtension().lastPathComponent == digest else {
            throw CodexMediaCleanupError.corruptMediaObject(file.path)
        }
        return CodexDataImage(
            mimeType: "image/\(subtype)",
            subtype: subtype,
            fileExtension: ext == "jpeg" ? "jpg" : ext,
            bytes: bytes,
            sha256: digest,
            originalCharacterCount: 0
        )
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

enum CodexMediaObjectStore {
    static func canonicalURL(for image: CodexDataImage, mediaRoot: URL) -> URL {
        mediaRoot
            .appendingPathComponent(String(image.sha256.prefix(2)), isDirectory: true)
            .appendingPathComponent("\(image.sha256).\(image.fileExtension)")
    }

    static func ensureObject(
        for image: CodexDataImage,
        mediaRoot: URL,
        fileManager: FileManager = .default
    ) throws -> (url: URL, created: Bool) {
        let destination = canonicalURL(for: image, mediaRoot: mediaRoot)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try CodexDataImage.fromCanonicalFile(destination, mediaRoot: mediaRoot)
            return (destination, false)
        }

        try fileManager.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(image.sha256).\(UUID().uuidString).tmp")
        do {
            try image.bytes.write(to: temporary, options: [.atomic])
            try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: temporary.path)
            let verified = try CodexDataImage.fromLooseFile(temporary, expectedSHA256: image.sha256)
            guard verified else { throw CodexMediaCleanupError.corruptMediaObject(temporary.path) }
            do {
                try fileManager.moveItem(at: temporary, to: destination)
            } catch CocoaError.fileWriteFileExists {
                _ = try CodexDataImage.fromCanonicalFile(destination, mediaRoot: mediaRoot)
            }
            return (destination, true)
        } catch {
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }
}

private extension CodexDataImage {
    static func fromLooseFile(_ url: URL, expectedSHA256: String) throws -> Bool {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() == expectedSHA256
    }
}
