import Foundation
import Darwin

private func argumentValue(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name), index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

guard let adapterId = argumentValue("--adapter"),
      let profile = UniversalAdapterProfile.profile(id: adapterId) else {
    writeJSONResponse(ok: false, error: "unsupported_adapter")
    exit(2)
}

let store = AdapterStateStore()

if CommandLine.arguments.contains("--hook") {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard data.count <= 1_048_576, let input = jsonObject(data) else {
        writeJSONResponse(ok: false, error: "invalid_hook_input")
        exit(2)
    }
    let status = UniversalHookBridge(profile: profile, store: store).run(input: input)
    exit(status)
}

if CommandLine.arguments.contains("--install-hooks") {
    do {
        let result = try UniversalHookInstaller(profile: profile, executablePath: CommandLine.arguments[0]).install()
        writeJSONResponse(ok: true, result: result)
        exit(0)
    } catch {
        writeJSONResponse(ok: false, error: "hook_install_failed:\(error.localizedDescription)")
        exit(1)
    }
}

let requestData = FileHandle.standardInput.readDataToEndOfFile()
guard requestData.count <= 1_048_576,
      let request = jsonObject(requestData),
      let method = request["method"] as? String else {
    writeJSONResponse(ok: false, error: "invalid_adapter_request")
    exit(2)
}

let params = request["params"] as? [String: Any] ?? [:]
let discovery = SessionDiscovery(profile: profile, store: store)
let controls = ControlService(profile: profile, store: store, discovery: discovery)

do {
    switch method {
    case "health":
        var result = discovery.health()
        result["adapterVersion"] = universalAdapterVersion
        result["protocolVersion"] = universalProtocolVersion
        result["adapterId"] = profile.id
        result["displayName"] = profile.displayName
        writeJSONResponse(ok: true, result: result)
    case "listSessions":
        writeJSONResponse(ok: true, result: ["sessions": discovery.sessions()])
    case "sessionContext":
        let sessionId = params["sessionId"] as? String ?? params["threadId"] as? String ?? ""
        guard !sessionId.isEmpty else { throw UniversalAdapterError.invalidRequest }
        let cursor = params["cursor"] as? String
        let limit = (params["limit"] as? NSNumber)?.intValue ?? Int(params["limit"] as? String ?? "") ?? 80
        let turnLimit = (params["turnLimit"] as? NSNumber)?.intValue ?? Int(params["turnLimit"] as? String ?? "")
        writeJSONResponse(ok: true, result: discovery.context(sessionId: sessionId, cursor: cursor, limit: limit, turnLimit: turnLimit))
    case "control":
        writeJSONResponse(ok: true, result: try controls.control(params))
    default:
        throw UniversalAdapterError.unsupportedMethod(method)
    }
} catch {
    writeJSONResponse(ok: false, error: (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
    exit(1)
}
