import Foundation

struct BridgeBinary {
    let name = "agentguard-bridge"
    let targetDir = "~/.agentguard/bin/"
    let platformTriple: String

    var installPath: String {
        NSString(string: targetDir).expandingTildeInPath + "/" + name
    }

    var sourcePath: String? {
        if let bundled = Bundle.main.path(forResource: name, ofType: nil) {
            return bundled
        }
        return nil
    }

    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: installPath)
    }

    init() {
#if arch(x86_64)
        platformTriple = "x86_64-apple-darwin"
#elseif arch(arm64)
        platformTriple = "aarch64-apple-darwin"
#else
        platformTriple = "unknown"
#endif
    }

    func install() throws {
        let dir = NSString(string: targetDir).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        guard let source = sourcePath else {
            throw NSError(domain: "AgentGuardBridge", code: -1, userInfo: [
                NSLocalizedDescriptionKey: "Bridge binary not found in app bundle"
            ])
        }

        let dest = installPath
        if FileManager.default.fileExists(atPath: dest) {
            try FileManager.default.removeItem(atPath: dest)
        }

        try FileManager.default.copyItem(atPath: source, toPath: dest)

        var attrs = [FileAttributeKey: Any]()
        attrs[.posixPermissions] = 0o755
        try FileManager.default.setAttributes(attrs, ofItemAtPath: dest)

        print("[AgentGuard] Bridge binary installed at \(dest)")
    }

    func uninstall() {
        let path = installPath
        if FileManager.default.fileExists(atPath: path) {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    func runAsCLI(args: [String]) -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installPath)
        process.arguments = args
        return process
    }

    func queryVersion() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: installPath)
        process.arguments = ["--version"]

        let pipe = Pipe()
        process.standardOutput = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    func deployToRemote(host: String, port: Int, username: String, identityFile: String?) async throws -> String {
        let sshArgs: [String]
        if let identity = identityFile {
            sshArgs = ["ssh", "-i", identity, "-p", "\(port)", "\(username)@\(host)", "mkdir -p \(targetDir)"]
        } else {
            sshArgs = ["ssh", "-p", "\(port)", "\(username)@\(host)", "mkdir -p \(targetDir)"]
        }

        let mkdirProcess = Process()
        mkdirProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        mkdirProcess.arguments = Array(sshArgs.dropFirst())
        try mkdirProcess.run()
        mkdirProcess.waitUntilExit()

        var scpArgs: [String]
        if let identity = identityFile {
            scpArgs = ["scp", "-i", identity, "-P", "\(port)", installPath, "\(username)@\(host):\(targetDir)\(name)"]
        } else {
            scpArgs = ["scp", "-P", "\(port)", installPath, "\(username)@\(host):\(targetDir)\(name)"]
        }

        let scpProcess = Process()
        scpProcess.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
        scpProcess.arguments = Array(scpArgs.dropFirst())
        try scpProcess.run()
        scpProcess.waitUntilExit()

        guard scpProcess.terminationStatus == 0 else {
            throw RemoteError.bridgeDeployFailed
        }

        var chmodArgs: [String]
        if let identity = identityFile {
            chmodArgs = ["ssh", "-i", identity, "-p", "\(port)", "\(username)@\(host)", "chmod +x \(targetDir)\(name)"]
        } else {
            chmodArgs = ["ssh", "-p", "\(port)", "\(username)@\(host)", "chmod +x \(targetDir)\(name)"]
        }

        let chmodProcess = Process()
        chmodProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        chmodProcess.arguments = Array(chmodArgs.dropFirst())
        try chmodProcess.run()
        chmodProcess.waitUntilExit()

        return "Bridge deployed to \(host):\(port)"
    }
}