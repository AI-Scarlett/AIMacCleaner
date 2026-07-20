# TraceFence Agent Core

TraceFence Agent Core is the local, independently updatable control plane for agent integrations. It runs in the signed-in macOS user session and does not upload agent data to a TraceFence backend.

## Product Boundary

- The macOS app owns subscription state, pairing UI, local-network discovery, and the compatibility gateway on port `17895`.
- Agent Core owns adapter discovery, session snapshots, real runtime control, and approval routing. Its fallback iOS gateway listens on port `17896` with the same pairing token.
- TraceFence Sentinel races saved, Bonjour, VPN, and user-provided endpoints. On private networks it prefers Agent Core on `17896` and falls back to the Mac app on `17895`, so closing the Mac app does not break remote control.
- Screen lock does not stop either launch agent. System sleep, a closed laptop lid, shutdown, or network loss makes the Mac unreachable until it wakes and reconnects.

There is no TraceFence cloud relay. Internet access requires a user-owned route such as Tailscale, ZeroTier, WireGuard, a company VPN, DDNS with a carefully secured port, or a reverse tunnel.

## Versioned Protocol

Current Core version: `1.6.5` (`1605`). Remote status uses a nonblocking cached adapter snapshot, and optional adapter health probes have a three-second ceiling, so an unhealthy Agent integration cannot disconnect the paired iPhone. Core reinstallations preserve the existing 256-bit pairing token and replace same-version bundles from a clean, verified staging directory. Long-lived Codex readers drain decoded JSON per frame and close each IPC connection within its iteration, keeping memory bounded during continuous monitoring. Adapter session polling is cached and rate-limited per adapter; the global catalog reserves space for every detected adapter before filling the remaining rows. Active Codex automation definitions are read independently from historical run conversations and published as one future `scheduledTask` record with `nextRunAt`; paused automations and completed run history are not presented as upcoming work. Unix-socket responses now use the same JSON-compatible representation as the HTTP gateway, so large multi-agent session catalogs can be consumed by the macOS project monitor. The Core status response also publishes current LAN and Tailnet addresses, allowing an already paired iPhone to learn new routes without rescanning. Codex approval state follows the official app-server lifecycle: `serverRequest/resolved`, item completion, turn completion, interruption, and idle transitions all clear requests that are no longer actionable, while the legacy Desktop snapshot remains an automatic fallback when the native stream is unavailable.

Session context paging accepts `turnLimit`. Core derives stable turn identifiers when an Agent transcript does not provide them, returns semantic turns instead of an arbitrary message slice, and compacts tool-heavy turns to a bounded set of user, Agent, and first/last tool records. This keeps the iOS recent-three-turn view complete without rendering thousands of tool messages.

Core listens on:

`~/Library/Application Support/TraceFence/Core/agent-core.sock`

The local transport is newline-delimited JSON and currently exposes:

- `initialize`
- `health`
- `capabilities`
- `listAdapters`
- `listSessions`
- `sessionContext`
- `control` (`instruction`, `interrupt`, and `approval`)

Adapter manifests live in `Core/adapters/*.json`. External adapters use a one-request JSON process protocol, while their own daemon may retain agent-specific runtime state. The HTTP layer only reads cached Core snapshots; CLI startup and log parsing never run on the iOS request thread.

## Codex Adapter

Real Codex control uses the official standalone Codex CLI daemon and its local user WebSocket socket. TraceFence implements the local RFC 6455 client needed by the daemon and supports:

- discovery of real Codex projects and sessions
- starting a new turn
- steering an active turn
- interrupting a turn
- command, file, permission, and user-input approvals

Dependency:

```sh
curl -fsSL https://chatgpt.com/codex/install.sh | sh
~/.codex/packages/standalone/current/codex app-server daemon bootstrap
```

TraceFence does not report a control request as successful unless the Codex app-server acknowledges it.

## Claude Adapter

`TraceFenceClaudeAdapter` is a separate binary and launch agent. It can be replaced without rebuilding the macOS or iOS UI. It provides:

- bounded discovery of `~/.claude/projects` sessions
- discovery and stopping of real `claude --bg` jobs
- continuation of a historical Claude Code session with a new instruction
- blocking `PermissionRequest` hooks whose decisions are returned from iPhone
- explicit authentication diagnostics

Adapter `1.0.2` prefers a valid first-party Claude OAuth login and falls back to the configured custom provider. It checks each launched job's own startup log at multiple points; API errors, inactive keys, and login failures stop the job and are returned to iPhone instead of being reported as success.

If Claude Code uses a custom provider through `ANTHROPIC_*` environment variables, the importer writes only the allowlisted provider variables to `Core/claude-environment.json` with mode `0600`. They are never embedded in a launch-agent plist, adapter manifest, log, session payload, or iOS response. This local file avoids Keychain calls on the launch daemon's startup/RPC path, which can block a background adapter before its sockets become ready.

Claude Desktop currently exposes no supported local API for enumerating and controlling all desktop chats. TraceFence can detect Claude Desktop, but real remote execution requires the Claude Code CLI and a valid CLI login:

```sh
claude auth login
```

Claude Desktop and Claude Code credentials are separate. When Claude reports `Not logged in`, TraceFence returns an error and stops the newly created background job instead of claiming the instruction ran.

## Adapter Capability Matrix

Capability is negotiated at runtime. `installed` means an app, CLI, or readable data root exists; it does not imply that remote control is available.

| Adapter | Discovery | Instruction / interrupt | Approval | Runtime rule |
| --- | --- | --- | --- | --- |
| Codex / ChatGPT Codex | Native daemon + local sessions | Native app-server control | Native approval RPC | Enabled only after daemon acknowledgement. |
| Claude Code | JSONL + background jobs | Dedicated Claude CLI adapter | Blocking `PermissionRequest` hook | Disabled when CLI/provider authentication fails. |
| Grok CLI | Official session updates | Managed resumable CLI | Official `PreToolUse` hook | Tested end to end on this Mac. |
| Qwen Code | Official project JSONL | Managed resumable CLI | Official `PreToolUse` hook | Provider errors disable controls until sign-in is repaired. |
| Cursor Agent CLI | CLI sessions + streamed jobs | Managed CLI | `preToolUse` gate | Requires `cursor-agent`; Cursor Desktop alone is monitor-only. |
| MiniMax Code / OpenCode | SQLite sessions + live local port | Native local HTTP control when alive | Native permission endpoint | Historical/offline rows are monitor-only. |
| OpenClaw | Session store / transcript | Official `openclaw agent` when CLI exists | Not advertised | Data-only installs are monitor-only. |
| Hermes | `state.db` and legacy files | Official resumable CLI when installed | Not advertised | Data-only installs are monitor-only. |
| Trae / CodeBuddy | Local IDE indexes and queues | No supported local API | No supported local API | Read-only monitoring with an explicit limitation. |
| Gemini, Kiro, Aider, Amp, Goose, Copilot CLI, Droid | Public-profile discovery or TraceFence-managed jobs | Enabled only when the matching CLI is present | Only where a verified hook/protocol exists | Uninstalled profiles remain `unavailable`, never simulated. |

Primary protocol references:

- Grok CLI: <https://docs.x.ai/build/cli/reference>
- Qwen hooks: <https://qwenlm.github.io/qwen-code-docs/en/users/features/hooks/>
- Cursor CLI: <https://docs.cursor.com/en/cli/reference/parameters>
- OpenClaw agent command: <https://docs.openclaw.ai/cli/agent>
- Hermes CLI and sessions: <https://hermes-agent.nousresearch.com/docs/reference/cli-commands>
- OpenCode server: <https://opencode.ai/docs/server/>
- Kiro CLI and hooks: <https://kiro.dev/docs/cli/reference/cli-commands/> and <https://kiro.dev/docs/cli/hooks/>
- Amp CLI: <https://ampcode.com/manual>
- Goose ACP: <https://github.com/aaif-goose/goose/blob/main/CUSTOM_DISTROS.md>
- Copilot CLI: <https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/quickstart>
- Droid Exec: <https://docs.factory.ai/cli/droid-exec/overview>

## Plugin And Skill Role

The adapter directory is the plugin boundary. A future TraceFence skill can install, upgrade, verify signatures, run health checks, and repair hook configuration. A skill must not be the runtime control plane: it cannot reliably stay alive, own another agent process, or hold a permission request open while an iPhone responds.

The intended split is:

1. Agent Core: stable, signed local protocol and iOS gateway.
2. Per-agent adapter: agent-specific parsing, IPC, process control, and approval translation.
3. Optional skill/plugin: installer, updater, diagnostics, and documentation.

## Local Installation

```sh
scripts/build_tracefence_agent_core.sh
```

The installer builds and signs the Core, Claude adapter, and universal adapter; installs both launch agents; bootstraps the official Codex daemon when present; and merges verified TraceFence hooks without discarding unrelated settings.

Installed services:

- `com.tracefence.agent-core`
- `com.tracefence.adapter.claude`

The direct website build can update these signed components independently. An App Store build may connect to a separately installed signed Core, but it must not download or execute unsigned adapter code.

## Independent Updates

The signed release bundle contains Core, its updater, the Claude adapter, the universal adapter, and all adapter manifests. Production update metadata is read from:

`~/Library/Application Support/TraceFence/Core/update-config.json`

The updater requires HTTPS, verifies the package SHA-256, bundle identifier, Developer ID Team ID, version/build monotonicity, and nested signatures, then switches the `current` symlink atomically. It launches the candidate Core and performs a health check before committing. A failed candidate automatically rolls back to the previous signed release.

Release artifacts are produced with:

```sh
scripts/build_tracefence_agent_core_release.sh
```

Publish only Core and adapter assets to the fixed stable channel with:

```sh
scripts/publish_tracefence_agent_core_release.sh
```

The `agent-core-stable` GitHub release is intentionally separate from macOS app releases. Its manifest URL does not follow the repository's latest app tag, so shipping or withholding a macOS DMG cannot break Core update checks. Versioned Core archives remain attached to the channel release for rollback, while only the stable manifest is replaced.

The macOS app is only a status and manual-check UI for this service. Core updates do not require replacing the macOS app or the iOS app.
