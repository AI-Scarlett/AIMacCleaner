import SwiftUI

struct SoundSettingsView: View {
    @EnvironmentObject var localizer: Localizer
    let soundEngine: SoundEngine
    @State private var profile: SoundProfile = .default
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                soundSettingsContent
            }
        }
        .padding(16)
        .task {
            await loadProfile()
        }
    }

    private var soundSettingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Toggle(localizer.enableSounds, isOn: Binding(
                    get: { profile.enabled },
                    set: { profile.enabled = $0; saveProfile() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()
            }

            HStack(spacing: 8) {
                Text(localizer.soundVolume)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                Slider(value: Binding(
                    get: { Double(profile.volume) },
                    set: { profile.volume = Float($0); saveProfile() }
                ), in: 0...1)

                Text("\(Int(profile.volume * 100))%")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 36)
            }
            .disabled(!profile.enabled)

            HStack {
                Toggle(localizer.muteDuringDND, isOn: Binding(
                    get: { profile.muteWhenDnD },
                    set: { profile.muteWhenDnD = $0; saveProfile() }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(!profile.enabled)

                Spacer()
            }

            Divider()

            Text(localizer.eventSounds)
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 4) {
                ForEach(Array(profile.eventSounds.keys.sorted()), id: \.self) { key in
                    HStack {
                        Text(eventLabel(key))
                            .font(.system(size: 12))
                            .foregroundStyle(.primary)

                        Spacer()

                        Button(action: {
                            let name = profile.eventSounds[key] ?? "pop"
                            Task { await soundEngine.playSound(named: name) }
                        }) {
                            Image(systemName: "play.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.blue.opacity(0.6))
                        }
                        .buttonStyle(.plain)
                        .disabled(!profile.enabled)

                        Picker("", selection: Binding(
                            get: { profile.eventSounds[key] ?? "none" },
                            set: { profile.eventSounds[key] = $0; saveProfile() }
                        )) {
                            Text(soundLabel("none")).tag("none")
                            Text(soundLabel("pop")).tag("pop")
                            Text(soundLabel("whoosh")).tag("whoosh")
                            Text(soundLabel("tick")).tag("tick")
                            Text(soundLabel("tock")).tag("tock")
                            Text(soundLabel("ping")).tag("ping")
                            Text(soundLabel("chime")).tag("chime")
                            Text(soundLabel("success")).tag("success")
                            Text(soundLabel("error")).tag("error")
                            Text(soundLabel("pause")).tag("pause")
                            Text(soundLabel("bell")).tag("bell")
                            Text(soundLabel("swoosh")).tag("swoosh")
                        }
                        .pickerStyle(.menu)
                        .frame(width: 100)
                        .disabled(!profile.enabled)
                    }
                    .padding(.vertical, 3)
                }
            }
        }
    }

    private func eventLabel(_ key: String) -> String {
        switch key {
        case "session_start": return localizer.eventSessionStart
        case "session_end": return localizer.eventSessionEnd
        case "tool_start": return localizer.eventToolStart
        case "tool_end": return localizer.eventToolEnd
        case "permission_request": return localizer.eventPermissionRequest
        case "question": return localizer.agentCenterQuestion
        case "plan_approval": return localizer.eventPlanApproval
        case "task_complete": return localizer.eventTaskComplete
        case "error": return localizer.soundError
        case "interrupt": return localizer.eventInterrupt
        case "notification": return localizer.eventNotification
        case "subagent_start": return localizer.eventSubagentStart
        case "subagent_end": return localizer.eventSubagentEnd
        case "shell_execution": return localizer.eventShellExecution
        case "rate_limit": return localizer.eventRateLimit
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func soundLabel(_ key: String) -> String {
        switch key {
        case "none": return localizer.soundNone
        case "pop": return localizer.soundPop
        case "whoosh": return localizer.soundWhoosh
        case "tick": return localizer.soundTick
        case "tock": return localizer.soundTock
        case "ping": return localizer.soundPing
        case "chime": return localizer.soundChime
        case "success": return localizer.soundSuccess
        case "error": return localizer.soundError
        case "pause": return localizer.soundPause
        case "bell": return localizer.soundBell
        case "swoosh": return localizer.soundSwoosh
        default: return key.capitalized
        }
    }

    private func loadProfile() async {
        profile = await soundEngine.getProfile()
        isLoading = false
    }

    private func saveProfile() {
        Task { await soundEngine.updateProfile(profile) }
    }
}

struct WebhookSettingsView: View {
    @EnvironmentObject var localizer: Localizer
    let webhookNotifier: WebhookNotifier
    @State private var config: WebhookConfig = WebhookConfig()
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                webhookContent
            }
        }
        .padding(16)
        .task {
            await loadConfig()
        }
    }

    private var webhookContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Toggle(localizer.enableWebhookNotifications, isOn: Binding(
                    get: { config.enabled },
                    set: { config.enabled = $0; saveConfig() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.webhookURL)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                TextField("https://your-server.com/webhook", text: Binding(
                    get: { config.url },
                    set: { config.url = $0; saveConfig() }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .disabled(!config.enabled)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(localizer.webhookSecretOptional)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField(localizer.webhookSecretPlaceholder, text: Binding(
                    get: { config.secret ?? "" },
                    set: { config.secret = $0.isEmpty ? nil : $0; saveConfig() }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .disabled(!config.enabled)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.webhookRetryCount)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Stepper("\(config.retryCount)", value: Binding(
                        get: { config.retryCount },
                        set: { config.retryCount = $0; saveConfig() }
                    ), in: 0...10)
                    .font(.system(size: 12))
                    .disabled(!config.enabled)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text(localizer.webhookTimeoutSeconds)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                    Stepper(String(format: "%.0f", config.timeoutSeconds), value: Binding(
                        get: { config.timeoutSeconds },
                        set: { config.timeoutSeconds = $0; saveConfig() }
                    ), in: 1...60, step: 5)
                    .font(.system(size: 12))
                    .disabled(!config.enabled)
                }
            }
        }
    }

    private func loadConfig() async {
        config = await webhookNotifier.getConfig()
        isLoading = false
    }

    private func saveConfig() {
        Task { await webhookNotifier.updateConfig(config) }
    }
}

struct RemoteSettingsView: View {
    @EnvironmentObject var localizer: Localizer
    let remoteManager: RemoteManager
    @State private var hosts: [RemoteHost] = []
    @State private var config: RemoteConfig = RemoteConfig()
    @State private var isLoading = true
    @State private var showAddHost = false
    @State private var newHost = ""
    @State private var newPort = 22
    @State private var newUser = ""
    @State private var newNickname = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                remoteContent
            }
        }
        .padding(16)
        .task {
            await loadData()
        }
    }

    private var remoteContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localizer.remoteHosts)
                    .font(.system(size: 14, weight: .semibold))

                Spacer()

                Button(action: { showAddHost = true }) {
                    Image(systemName: "plus")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain)
            }

            if hosts.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network.slash")
                        .font(.system(size: 24))
                        .foregroundStyle(.secondary.opacity(0.4))
                    Text(localizer.noRemoteHosts)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(localizer.noRemoteHostsHint)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ForEach(hosts) { host in
                    remoteHostRow(host)
                }
            }

            if showAddHost {
                addHostForm
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text(localizer.security)
                    .font(.system(size: 13, weight: .semibold))

                Picker(localizer.securityLevel, selection: Binding(
                    get: { config.securityLevel },
                    set: { config.securityLevel = $0; saveConfig() }
                )) {
                    Text(localizer.securityPermissive).tag(RemoteConfig.SecurityLevel.permissive)
                    Text(localizer.securityStandard).tag(RemoteConfig.SecurityLevel.standard)
                    Text(localizer.securityStrict).tag(RemoteConfig.SecurityLevel.strict)
                }
                .pickerStyle(.segmented)

                Text(securityLevelDescription)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)

                HStack {
                    Toggle(isOn: Binding(
                        get: { config.autoConnectEnabled },
                        set: { config.autoConnectEnabled = $0; saveConfig() }
                    )) {
                        Text(localizer.autoConnectKnownHosts)
                            .font(.system(size: 12))
                    }
                    .toggleStyle(.checkbox)

                    Spacer()
                }
            }
        }
    }

    private var securityLevelDescription: String {
        switch config.securityLevel {
        case .permissive: return localizer.securityPermissiveDesc
        case .standard: return localizer.securityStandardDesc
        case .strict: return localizer.securityStrictDesc
        }
    }

    private func remoteHostRow(_ host: RemoteHost) -> some View {
        HStack(spacing: 8) {
            Image(systemName: host.isOnline ? "network" : "network.slash")
                .font(.system(size: 12))
                .foregroundStyle(host.isOnline ? .green : .secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text(host.nickname ?? "\(host.username)@\(host.host)")
                    .font(.system(size: 13, weight: .medium))
                Text("\(host.username)@\(host.host):\(host.port)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            PillBadge(text: host.isOnline ? localizer.online : localizer.offline, color: host.isOnline ? .green : .secondary)

            Button(action: { removeHost(host) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.sm))
    }

    private var addHostForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizer.addRemoteHost)
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                TextField(localizer.hostPlaceholder, text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(minWidth: 120)

                TextField(localizer.port, value: $newPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 60)

                TextField(localizer.username, text: $newUser)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 100)

                TextField(localizer.nickname, text: $newNickname)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 100)
            }

            HStack {
                Spacer()
                Button(localizer.agentCancel) { showAddHost = false }
                    .font(.system(size: 11))
                Button(localizer.add) { confirmAddHost() }
                    .font(.system(size: 11, weight: .medium))
                    .disabled(newHost.isEmpty || newUser.isEmpty)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.03))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md))
    }

    private func confirmAddHost() {
        let host = RemoteHost(
            id: UUID().uuidString,
            host: newHost,
            port: newPort,
            username: newUser,
            identityFile: nil,
            nickname: newNickname.isEmpty ? nil : newNickname
        )
        Task { await remoteManager.addHost(host) }
        hosts.append(host)
        showAddHost = false
        newHost = ""
        newUser = ""
        newNickname = ""
    }

    private func removeHost(_ host: RemoteHost) {
        Task { await remoteManager.removeHost(host.id) }
        hosts.removeAll { $0.id == host.id }
    }

    private func loadData() async {
        hosts = await remoteManager.getHosts()
        config = await remoteManager.getConfig()
        isLoading = false
    }

    private func saveConfig() {
        Task { await remoteManager.updateConfig(config) }
    }
}
