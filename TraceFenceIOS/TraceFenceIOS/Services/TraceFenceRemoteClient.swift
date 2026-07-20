import Foundation

struct TraceFenceRemoteClient {
    var fetchStatus: (TraceFenceConnection) async throws -> TraceFenceStatusResponse
    var probeStatus: (TraceFenceConnection, String) async throws -> TraceFenceStatusResponse
    var fetchAgentControl: (TraceFenceConnection) async throws -> TraceFenceAgentControlResponse
    var fetchSessions: (TraceFenceConnection, String?, String, String, Int) async throws -> AgentSessionPageResponse
    var fetchSessionContext: (TraceFenceConnection, String, String?, Int) async throws -> AgentSessionContextResponse
    var setMonitoring: (TraceFenceConnection, Bool) async throws -> TraceFenceStatusResponse
    var resolveApproval: (TraceFenceConnection, String, Bool, String?, UUID) async throws -> TraceFenceAgentControlResponse
    var controlSession: (TraceFenceConnection, String, AgentSessionCommand, String?, UUID) async throws -> TraceFenceAgentControlResponse
    var launchSession: (TraceFenceConnection, String, String?, UUID) async throws -> TraceFenceAgentControlResponse
    var relaunchSession: (TraceFenceConnection, AgentSessionSummary, String?, UUID) async throws -> TraceFenceAgentControlResponse
}

extension TraceFenceRemoteClient {
    static let live = TraceFenceRemoteClient(
        fetchStatus: { connection in
            try await LiveTraceFenceRemoteClient().status(connection: connection)
        },
        probeStatus: { connection, endpoint in
            try await LiveTraceFenceRemoteClient().status(
                connection: connection,
                exactEndpoint: endpoint
            )
        },
        fetchAgentControl: { connection in
            try await LiveTraceFenceRemoteClient().agentControl(connection: connection)
        },
        fetchSessions: { connection, cursor, query, scope, limit in
            try await LiveTraceFenceRemoteClient().sessions(
                connection: connection,
                cursor: cursor,
                query: query,
                scope: scope,
                limit: limit
            )
        },
        fetchSessionContext: { connection, sessionId, cursor, limit in
            try await LiveTraceFenceRemoteClient().sessionContext(
                connection: connection,
                sessionId: sessionId,
                cursor: cursor,
                limit: limit
            )
        },
        setMonitoring: { connection, enabled in
            try await LiveTraceFenceRemoteClient().setMonitoring(enabled, connection: connection)
        },
        resolveApproval: { connection, approvalId, allow, answer, operationId in
            try await LiveTraceFenceRemoteClient().resolveApproval(
                approvalId: approvalId,
                allow: allow,
                answer: answer,
                operationId: operationId,
                connection: connection
            )
        },
        controlSession: { connection, sessionId, command, instruction, operationId in
            try await LiveTraceFenceRemoteClient().controlSession(
                sessionId: sessionId,
                command: command,
                instruction: instruction,
                operationId: operationId,
                connection: connection
            )
        },
        launchSession: { connection, targetId, instruction, operationId in
            try await LiveTraceFenceRemoteClient().launchSession(
                targetId: targetId,
                instruction: instruction,
                operationId: operationId,
                connection: connection
            )
        },
        relaunchSession: { connection, session, instruction, operationId in
            try await LiveTraceFenceRemoteClient().relaunchSession(
                session: session,
                instruction: instruction,
                operationId: operationId,
                connection: connection
            )
        }
    )
}

enum AgentSessionCommand: Equatable {
    case interrupt
    case resume
    case terminate
}

private struct LiveTraceFenceRemoteClient {
    private let session: URLSession = .shared

    func status(connection: TraceFenceConnection) async throws -> TraceFenceStatusResponse {
        try await send(connection: connection, path: "/v1/status", method: "GET")
    }

    func status(
        connection: TraceFenceConnection,
        exactEndpoint: String
    ) async throws -> TraceFenceStatusResponse {
        var candidate = connection
        candidate.endpoint = exactEndpoint
        let request = try makeRequest(
            connection: candidate,
            path: "/v1/status",
            method: "GET",
            body: nil
        )
        return try await send(request)
    }

    func agentControl(connection: TraceFenceConnection) async throws -> TraceFenceAgentControlResponse {
        try await send(connection: connection, path: "/v1/agents", method: "GET")
    }

    func sessions(
        connection: TraceFenceConnection,
        cursor: String?,
        query: String,
        scope: String,
        limit: Int
    ) async throws -> AgentSessionPageResponse {
        var components = URLComponents()
        components.path = "/v1/sessions"
        var items = [
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "scope", value: scope)
        ]
        if let cursor, !cursor.isEmpty { items.append(URLQueryItem(name: "cursor", value: cursor)) }
        if !query.isEmpty { items.append(URLQueryItem(name: "query", value: query)) }
        components.queryItems = items
        return try await send(
            connection: connection,
            path: components.string ?? "/v1/sessions",
            method: "GET"
        )
    }

    func sessionContext(
        connection: TraceFenceConnection,
        sessionId: String,
        cursor: String?,
        limit: Int
    ) async throws -> AgentSessionContextResponse {
        var body = [
            "sessionId": sessionId,
            "limit": String(limit),
            "turnLimit": "3"
        ]
        if let cursor, !cursor.isEmpty { body["cursor"] = cursor }
        return try await send(
            connection: connection,
            path: "/v1/sessions/context",
            method: "POST",
            body: body
        )
    }

    func setMonitoring(_ enabled: Bool, connection: TraceFenceConnection) async throws -> TraceFenceStatusResponse {
        let path = enabled ? "/v1/monitor/start" : "/v1/monitor/stop"
        return try await send(connection: connection, path: path, method: "POST")
    }

    func resolveApproval(
        approvalId: String,
        allow: Bool,
        answer: String?,
        operationId: UUID,
        connection: TraceFenceConnection
    ) async throws -> TraceFenceAgentControlResponse {
        var body: [String: String] = [
            "approvalId": approvalId,
            "operationId": operationId.uuidString.lowercased()
        ]
        if let answer, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            body["answer"] = answer
            body["reason"] = answer
        }
        let path = allow ? "/v1/approvals/approve" : "/v1/approvals/deny"
        return try await send(connection: connection, path: path, method: "POST", body: body)
    }

    func controlSession(
        sessionId: String,
        command: AgentSessionCommand,
        instruction: String? = nil,
        operationId: UUID,
        connection: TraceFenceConnection
    ) async throws -> TraceFenceAgentControlResponse {
        let path: String
        switch command {
        case .interrupt: path = "/v1/sessions/interrupt"
        case .resume: path = "/v1/sessions/resume"
        case .terminate: path = "/v1/sessions/terminate"
        }
        var body = [
            "sessionId": sessionId,
            "operationId": operationId.uuidString.lowercased()
        ]
        if let instruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty {
            body["instruction"] = instruction
        }
        return try await send(
            connection: connection,
            path: path,
            method: "POST",
            body: body
        )
    }

    func launchSession(
        targetId: String,
        instruction: String? = nil,
        operationId: UUID,
        connection: TraceFenceConnection
    ) async throws -> TraceFenceAgentControlResponse {
        var body = [
            "targetId": targetId,
            "operationId": operationId.uuidString.lowercased()
        ]
        if let instruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty {
            body["instruction"] = instruction
        }
        return try await send(
            connection: connection,
            path: "/v1/sessions/launch",
            method: "POST",
            body: body
        )
    }

    func relaunchSession(
        session: AgentSessionSummary,
        instruction: String? = nil,
        operationId: UUID,
        connection: TraceFenceConnection
    ) async throws -> TraceFenceAgentControlResponse {
        var body = [
            "sessionId": session.id,
            "operationId": operationId.uuidString.lowercased(),
            "agentType": session.agentType,
            "project": session.project,
            "cwd": session.cwd,
            "phase": session.phase
        ]
        if let title = session.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            body["title"] = title
        }
        if let sourcePath = session.sourcePath?.trimmingCharacters(in: .whitespacesAndNewlines), !sourcePath.isEmpty {
            body["sourcePath"] = sourcePath
        }
        if let engineLabel = session.engineLabel?.trimmingCharacters(in: .whitespacesAndNewlines), !engineLabel.isEmpty {
            body["engineLabel"] = engineLabel
        }
        if let relaunchInstruction = session.relaunchInstruction?.trimmingCharacters(in: .whitespacesAndNewlines), !relaunchInstruction.isEmpty {
            body["relaunchInstruction"] = relaunchInstruction
        }
        if let lastResponse = session.lastResponse?.trimmingCharacters(in: .whitespacesAndNewlines), !lastResponse.isEmpty {
            body["lastResponse"] = lastResponse
        }
        if let lastThought = session.lastThought?.trimmingCharacters(in: .whitespacesAndNewlines), !lastThought.isEmpty {
            body["lastThought"] = lastThought
        }
        if let targetId = session.relaunchTargetId?.trimmingCharacters(in: .whitespacesAndNewlines), !targetId.isEmpty {
            body["targetId"] = targetId
        }
        if let instruction = instruction?.trimmingCharacters(in: .whitespacesAndNewlines), !instruction.isEmpty {
            body["instruction"] = instruction
        }
        return try await send(
            connection: connection,
            path: "/v1/sessions/relaunch",
            method: "POST",
            body: body
        )
    }

    private func makeRequest(connection: TraceFenceConnection, path: String, method: String, body: [String: String]? = nil) throws -> URLRequest {
        let url = try endpointURL(connection.endpoint, path: path)
        let timeout: TimeInterval
        if method != "GET" {
            timeout = 45
        } else if path.hasPrefix("/v1/agents") || path.hasPrefix("/v1/sessions") {
            timeout = 30
        } else {
            timeout = 8
        }
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = method
        request.setValue("Bearer \(connection.token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func endpointURL(_ endpoint: String, path: String) throws -> URL {
        var text = endpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { throw TraceFenceRemoteClientError.invalidEndpoint }
        if !text.contains("://") {
            text = "http://\(text)"
        }
        while text.hasSuffix("/") {
            text.removeLast()
        }
        guard let baseURL = URL(string: text) else {
            throw TraceFenceRemoteClientError.invalidEndpoint
        }
        guard let url = URL(string: baseURL.absoluteString + "/" + path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))) else {
            throw TraceFenceRemoteClientError.invalidEndpoint
        }
        return url
    }

    private func send<T: Decodable>(
        connection: TraceFenceConnection,
        path: String,
        method: String,
        body: [String: String]? = nil
    ) async throws -> T {
        var attemptedEndpoints: [String] = []
        var lastError: Error?
        var authenticationError: TraceFenceRemoteClientError?

        for endpoint in connection.candidateEndpoints {
            var candidate = connection
            candidate.endpoint = endpoint
            attemptedEndpoints.append(endpoint)
            do {
                let request = try makeRequest(connection: candidate, path: path, method: method, body: body)
                return try await send(request)
            } catch let error as TraceFenceRemoteClientError {
                if case .httpStatus(let status, _) = error, status == 401 || status == 402 {
                    // A paired Mac can expose both the background Core gateway and
                    // the foreground app gateway. During startup, token rotation, or
                    // migration from an older install, one endpoint can briefly have
                    // stale credentials while the other is already valid. Do not let
                    // the first fast 401/402 prevent a healthy endpoint from winning.
                    if authenticationError == nil || status == 402 {
                        authenticationError = error
                    }
                }
                lastError = error
            } catch {
                lastError = error
            }
        }

        if let authenticationError {
            throw authenticationError
        }
        if let urlError = lastError as? URLError {
            throw TraceFenceRemoteClientError.unreachable(attemptedEndpoints, urlError.code)
        }
        if let clientError = lastError as? TraceFenceRemoteClientError {
            throw clientError
        }
        throw TraceFenceRemoteClientError.unreachable(attemptedEndpoints, nil)
    }

    private func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw error
        }
        guard let http = response as? HTTPURLResponse else {
            throw TraceFenceRemoteClientError.invalidResponse
        }

        if (200..<300).contains(http.statusCode) {
            guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
                throw TraceFenceRemoteClientError.invalidResponse
            }
            return decoded
        }

        let serverError = try? JSONDecoder().decode(TraceFenceServerError.self, from: data)
        throw TraceFenceRemoteClientError.httpStatus(http.statusCode, serverError?.message ?? serverError?.error)
    }
}

private struct TraceFenceServerError: Decodable {
    var error: String?
    var message: String?
}

enum TraceFenceRemoteClientError: LocalizedError {
    case invalidEndpoint
    case invalidResponse
    case httpStatus(Int, String?)
    case unreachable([String], URLError.Code?)

    var errorDescription: String? {
        let language = AppLanguage.current
        switch self {
        case .invalidEndpoint:
            return language.text(
                zh: "Mac 地址无效。请粘贴配对信息，或输入 http://192.168.x.x:17896。",
                en: "The Mac endpoint is invalid. Paste pairing information or enter an address such as http://192.168.x.x:17896.",
                zhHant: "Mac 位址無效。請貼上配對資料，或輸入 http://192.168.x.x:17896。",
                ja: "Mac の接続先が無効です。ペアリング情報を貼り付けるか、http://192.168.x.x:17896 のようなアドレスを入力してください。",
                ko: "Mac 엔드포인트가 올바르지 않습니다. 페어링 정보를 붙여 넣거나 http://192.168.x.x:17896 형식의 주소를 입력하세요.",
                mt: "L-endpoint tal-Mac mhuwiex validu. Waħħal l-informazzjoni tal-pairing jew daħħal indirizz bħal http://192.168.x.x:17896."
            )
        case .invalidResponse:
            return language.text(
                zh: "Mac 返回的数据无法识别。请确认连接的是 TraceFence。",
                en: "The Mac returned unrecognized data. Make sure this endpoint belongs to TraceFence.",
                zhHant: "Mac 傳回的資料無法識別。請確認此連線屬於 TraceFence。",
                ja: "Mac から認識できないデータが返されました。TraceFence の接続先であることを確認してください。",
                ko: "Mac에서 인식할 수 없는 데이터를 반환했습니다. TraceFence 엔드포인트인지 확인하세요.",
                mt: "Il-Mac irritorna data mhux magħrufa. Ikkonferma li dan l-endpoint huwa ta' TraceFence."
            )
        case .unreachable(let endpoints, let code):
            let address = endpoints.first ?? "Mac"
            switch code {
            case .notConnectedToInternet, .dataNotAllowed:
                return language.text(
                    zh: "iOS 无法访问网络。请到“设置 > TraceFence Sentinel > 本地网络”开启权限，并确认 Wi-Fi 或蜂窝网络已连接。",
                    en: "iOS cannot access the network. Enable Local Network under Settings > TraceFence Sentinel and check Wi-Fi or cellular connectivity.",
                    zhHant: "iOS 無法存取網路。請在「設定 > TraceFence Sentinel > 區域網路」開啟權限，並確認 Wi-Fi 或流動網路已連線。",
                    ja: "iOS がネットワークにアクセスできません。「設定 > TraceFence Sentinel > ローカルネットワーク」を有効にし、Wi-Fi またはモバイル通信を確認してください。",
                    ko: "iOS에서 네트워크에 접근할 수 없습니다. 설정 > TraceFence Sentinel > 로컬 네트워크를 활성화하고 Wi-Fi 또는 셀룰러 연결을 확인하세요.",
                    mt: "iOS ma jistax jaċċessa n-network. Attiva Local Network f'Settings > TraceFence Sentinel u ċċekkja l-Wi-Fi jew id-data mobbli."
                )
            case .timedOut:
                return language.text(
                    zh: "连接 \(address) 超时。Mac 可能已睡眠、控制服务已退出，或当前网络无法到达该地址；锁屏但未睡眠不会导致服务断开。",
                    en: "Connection to \(address) timed out. The Mac may be asleep, the control service may have stopped, or this network cannot reach the endpoint. Locking the screen alone does not stop the service.",
                    zhHant: "連線至 \(address) 逾時。Mac 可能已睡眠、控制服務已停止，或目前網路無法到達此位址；只鎖定螢幕不會中斷服務。",
                    ja: "\(address) への接続がタイムアウトしました。Mac がスリープ中、制御サービスが停止中、または現在のネットワークから到達できない可能性があります。画面ロックだけではサービスは停止しません。",
                    ko: "\(address) 연결 시간이 초과되었습니다. Mac이 잠자기 상태이거나 제어 서비스가 중지되었거나 현재 네트워크에서 이 주소에 도달할 수 없습니다. 화면 잠금만으로 서비스가 중단되지는 않습니다.",
                    mt: "Il-konnessjoni ma' \(address) skadiet. Il-Mac jista' jkun rieqed, is-servizz waqaf, jew in-network ma jilħaqx l-endpoint. Lock tal-iskrin waħdu ma jwaqqafx is-servizz."
                )
            case .cannotConnectToHost, .networkConnectionLost:
                return language.text(
                    zh: "已找到 Mac 地址，但控制端口无法连接。请唤醒 Mac，并确认 TraceFence 常驻服务在线、左下角连接图标为绿色，且端口 17896/17895 未被防火墙拦截。",
                    en: "The Mac address was found, but the control port is unreachable. Wake the Mac and confirm the TraceFence background service is online, the connection indicator is green, and ports 17896/17895 are not blocked.",
                    zhHant: "已找到 Mac 位址，但無法連接控制連接埠。請喚醒 Mac，確認 TraceFence 常駐服務在線、左下角圖示為綠色，且防火牆未封鎖 17896/17895。",
                    ja: "Mac のアドレスは見つかりましたが、制御ポートに接続できません。Mac を起動し、TraceFence バックグラウンドサービスがオンラインで接続アイコンが緑色、ポート 17896/17895 が遮断されていないことを確認してください。",
                    ko: "Mac 주소를 찾았지만 제어 포트에 연결할 수 없습니다. Mac을 깨우고 TraceFence 백그라운드 서비스가 온라인이며 연결 아이콘이 녹색인지, 17896/17895 포트가 차단되지 않았는지 확인하세요.",
                    mt: "L-indirizz tal-Mac instab iżda l-port tal-kontroll ma jintlaħaqx. Qajjem il-Mac u ċċekkja s-servizz, l-indikatur aħdar u l-ports 17896/17895."
                )
            case .cannotFindHost, .dnsLookupFailed:
                return language.text(
                    zh: "无法解析 Mac 地址。客户端已尝试历史地址和 Bonjour；请确认 VPN/Tailnet 在线，或在 Mac 配对弹窗重新扫码。",
                    en: "The Mac hostname could not be resolved. The app tried saved endpoints and Bonjour. Check your VPN or tailnet, or scan the pairing code again on the Mac.",
                    zhHant: "無法解析 Mac 位址。App 已嘗試已儲存位址及 Bonjour；請確認 VPN/Tailnet 在線，或重新掃描 Mac 配對碼。",
                    ja: "Mac のホスト名を解決できません。保存済み接続先と Bonjour を試しました。VPN/Tailnet を確認するか、Mac のペアリングコードを再スキャンしてください。",
                    ko: "Mac 호스트 이름을 확인할 수 없습니다. 저장된 엔드포인트와 Bonjour를 시도했습니다. VPN/Tailnet을 확인하거나 Mac의 페어링 코드를 다시 스캔하세요.",
                    mt: "L-isem tal-Mac ma setax jiġi riżolt. Ġew ippruvati endpoints issejvjati u Bonjour. Iċċekkja l-VPN/Tailnet jew erġa' skennja l-kodiċi."
                )
            default:
                return language.text(
                    zh: "无法连接 Mac。已自动尝试 Bonjour、历史地址和配对信息中的网络入口；请确认 Mac 未睡眠且常驻服务在线。",
                    en: "Unable to connect to the Mac. Bonjour, saved endpoints, and paired network endpoints were tried automatically. Make sure the Mac is awake and the background service is online.",
                    zhHant: "無法連接 Mac。已自動嘗試 Bonjour、已儲存位址及配對網路入口；請確認 Mac 未睡眠且常駐服務在線。",
                    ja: "Mac に接続できません。Bonjour、保存済み接続先、ペアリングされたネットワーク接続先を自動的に試しました。Mac が起動中でバックグラウンドサービスがオンラインか確認してください。",
                    ko: "Mac에 연결할 수 없습니다. Bonjour, 저장된 엔드포인트 및 페어링된 네트워크 엔드포인트를 자동으로 시도했습니다. Mac이 깨어 있고 백그라운드 서비스가 온라인인지 확인하세요.",
                    mt: "Ma setax jikkonnettja mal-Mac. Ġew ippruvati Bonjour u l-endpoints issejvjati. Kun żgur li l-Mac huwa mqajjem u s-servizz huwa online."
                )
            }
        case .httpStatus(let status, let message):
            if status == 401 {
                return language.text(
                    zh: "配对密钥不正确。请在 Mac 端重置并重新复制配对信息。",
                    en: "The pairing token is incorrect. Reset it on the Mac and copy the pairing information again.",
                    zhHant: "配對權杖不正確。請在 Mac 重設並重新複製配對資料。",
                    ja: "ペアリングトークンが正しくありません。Mac でリセットし、ペアリング情報を再度コピーしてください。",
                    ko: "페어링 토큰이 올바르지 않습니다. Mac에서 재설정한 후 페어링 정보를 다시 복사하세요.",
                    mt: "It-token tal-pairing mhuwiex korrett. Irrisettjah fuq il-Mac u erġa' kkopja l-informazzjoni."
                )
            }
            if status == 402 {
                return message?.tfLocalized ?? language.text(
                    zh: "远程控制需要有效订阅或试用。",
                    en: "Remote control requires an active subscription or trial.",
                    zhHant: "遠端控制需要有效的訂閱或試用。",
                    ja: "リモート制御には有効なサブスクリプションまたはトライアルが必要です。",
                    ko: "원격 제어에는 활성 구독 또는 평가판이 필요합니다.",
                    mt: "Il-kontroll remot jeħtieġ abbonament jew prova attiva."
                )
            }
            return message?.tfLocalized ?? language.text(
                zh: "请求失败，状态码 \(status)。",
                en: "The request failed with status code \(status).",
                zhHant: "請求失敗，狀態碼為 \(status)。",
                ja: "リクエストに失敗しました。ステータスコード: \(status)。",
                ko: "요청에 실패했습니다. 상태 코드: \(status).",
                mt: "It-talba falliet bil-kodiċi \(status)."
            )
        }
    }
}
