import SwiftUI

struct SoundSettingsView: View {
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
                Toggle("Enable Sounds", isOn: Binding(
                    get: { profile.enabled },
                    set: { profile.enabled = $0; saveProfile() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()
            }

            HStack(spacing: 8) {
                Text("Volume:")
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
                Toggle("Mute during Do Not Disturb", isOn: Binding(
                    get: { profile.muteWhenDnD },
                    set: { profile.muteWhenDnD = $0; saveProfile() }
                ))
                .toggleStyle(.checkbox)
                .font(.system(size: 12))
                .disabled(!profile.enabled)

                Spacer()
            }

            Divider()

            Text("Event Sounds")
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
                            Text("None").tag("none")
                            Text("Pop").tag("pop")
                            Text("Whoosh").tag("whoosh")
                            Text("Tick").tag("tick")
                            Text("Tock").tag("tock")
                            Text("Ping").tag("ping")
                            Text("Chime").tag("chime")
                            Text("Success").tag("success")
                            Text("Error").tag("error")
                            Text("Pause").tag("pause")
                            Text("Bell").tag("bell")
                            Text("Swoosh").tag("swoosh")
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
        case "session_start": return "Session Start"
        case "session_end": return "Session End"
        case "tool_start": return "Tool Start"
        case "tool_end": return "Tool End"
        case "permission_request": return "Permission Request"
        case "question": return "Question"
        case "plan_approval": return "Plan Approval"
        case "task_complete": return "Task Complete"
        case "error": return "Error"
        case "interrupt": return "Interrupt"
        case "notification": return "Notification"
        case "subagent_start": return "Subagent Start"
        case "subagent_end": return "Subagent End"
        case "shell_execution": return "Shell Execution"
        case "rate_limit": return "Rate Limit"
        default: return key.replacingOccurrences(of: "_", with: " ").capitalized
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
                Toggle("Enable Webhook Notifications", isOn: Binding(
                    get: { config.enabled },
                    set: { config.enabled = $0; saveConfig() }
                ))
                .toggleStyle(.switch)
                .controlSize(.small)

                Spacer()
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Webhook URL")
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
                Text("Secret (optional)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                SecureField("HMAC secret key", text: Binding(
                    get: { config.secret ?? "" },
                    set: { config.secret = $0.isEmpty ? nil : $0; saveConfig() }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 12))
                .disabled(!config.enabled)
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Retry Count")
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
                    Text("Timeout (seconds)")
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
                Text("Remote Hosts")
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
                    Text("No remote hosts configured")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text("Add an SSH host to monitor remote agent sessions")
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
                Text("Security")
                    .font(.system(size: 13, weight: .semibold))

                Picker("Security Level", selection: Binding(
                    get: { config.securityLevel },
                    set: { config.securityLevel = $0; saveConfig() }
                )) {
                    Text("Permissive").tag(RemoteConfig.SecurityLevel.permissive)
                    Text("Standard").tag(RemoteConfig.SecurityLevel.standard)
                    Text("Strict").tag(RemoteConfig.SecurityLevel.strict)
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
                        Text("Auto-connect to known hosts")
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
        case .permissive: return "All remote agent activity is allowed without verification"
        case .standard: return "Trusted hosts and verified fingerprints are allowed; others require approval"
        case .strict: return "Only explicitly trusted hosts with valid fingerprints are allowed"
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

            PillBadge(text: host.isOnline ? "Online" : "Offline", color: host.isOnline ? .green : .secondary)

            Button(action: { removeHost(host) }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.red.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.primary.opacity(0.03))
        .cornerRadius(6)
    }

    private var addHostForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add Remote Host")
                .font(.system(size: 12, weight: .semibold))

            HStack(spacing: 8) {
                TextField("Host (IP or hostname)", text: $newHost)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(minWidth: 120)

                TextField("Port", value: $newPort, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 60)

                TextField("Username", text: $newUser)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 100)

                TextField("Nickname", text: $newNickname)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 100)
            }

            HStack {
                Spacer()
                Button("Cancel") { showAddHost = false }
                    .font(.system(size: 11))
                Button("Add") { confirmAddHost() }
                    .font(.system(size: 11, weight: .medium))
                    .disabled(newHost.isEmpty || newUser.isEmpty)
            }
        }
        .padding(10)
        .background(.primary.opacity(0.03))
        .cornerRadius(8)
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