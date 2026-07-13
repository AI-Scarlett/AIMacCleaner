#!/bin/sh
set -eu

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
CORE_DIR="$ROOT_DIR/TraceFenceAgentCore"
CORE_SOURCE="$CORE_DIR/Sources/TraceFenceAgentCore/main.swift"
INSTALL_DIR="${TRACEFENCE_CORE_INSTALL_DIR:-$HOME/Library/Application Support/TraceFence/Core}"
LAUNCH_AGENT_DIR="$HOME/Library/LaunchAgents"
LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/com.tracefence.agent-core.plist"
CODEX_ADAPTER_LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/com.tracefence.codex-adapter.plist"
CLAUDE_ADAPTER_LAUNCH_AGENT_PATH="$LAUNCH_AGENT_DIR/com.tracefence.adapter.claude.plist"
MANAGED_CODEX="$HOME/.codex/packages/standalone/current/codex"
SOCKET_PATH="$INSTALL_DIR/agent-core.sock"
CLAUDE_ADAPTER_SOCKET_PATH="$INSTALL_DIR/claude-adapter.sock"
CLAUDE_HOOK_SOCKET_PATH="$INSTALL_DIR/claude-hooks.sock"
HTTP_CONFIG_PATH="$INSTALL_DIR/remote-gateway.json"
LOG_DIR="$HOME/Library/Logs/TraceFence"
USER_TEMP_DIR="$(/usr/bin/getconf DARWIN_USER_TEMP_DIR 2>/dev/null || true)"
CORE_PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.local/bin:$HOME/.grok/bin:$HOME/.qwen/bin:$HOME/.cursor/bin:$HOME/.minimax/bin:$HOME/.opencode/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.npm-global/bin:$HOME/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH="$CORE_PATH"

CORE_VERSION="$(sed -n 's/^private let coreVersion = "\([^"]*\)"/\1/p' "$CORE_SOURCE" | head -n 1)"
CORE_BUILD="$(sed -n 's/^private let coreBuild = \([0-9][0-9]*\)/\1/p' "$CORE_SOURCE" | head -n 1)"
RELEASE_OUTPUT_DIR="$ROOT_DIR/build/TraceFenceAgentCore-$CORE_VERSION"
RELEASE_DIR="$INSTALL_DIR/releases/$CORE_VERSION-$CORE_BUILD"
RELEASE_BUNDLE="$RELEASE_DIR/TraceFenceAgentCore.bundle"

TRACEFENCE_CORE_RELEASE_OUTPUT_DIR="$RELEASE_OUTPUT_DIR" "$ROOT_DIR/scripts/build_tracefence_agent_core_release.sh"
mkdir -p "$INSTALL_DIR"
mkdir -p "$INSTALL_DIR/releases"
mkdir -p "$RELEASE_DIR"
ditto "$RELEASE_OUTPUT_DIR/TraceFenceAgentCore.bundle" "$RELEASE_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$RELEASE_BUNDLE"

install_core_link() {
  name="$1"
  destination="$2"
  path="$INSTALL_DIR/$name"
  if [ ! -L "$path" ] && [ -e "$path" ]; then
    mv "$path" "$INSTALL_DIR/legacy-$name-$(date +%s)"
  fi
  temporary="$INSTALL_DIR/.$name.$$"
  rm -f "$temporary"
  ln -s "$destination" "$temporary"
  mv -fh "$temporary" "$path"
}

install_core_link "current" "releases/$CORE_VERSION-$CORE_BUILD/TraceFenceAgentCore.bundle"
install_core_link "TraceFenceAgentCore" "current/Contents/MacOS/TraceFenceAgentCore"
install_core_link "TraceFenceAgentCoreUpdater" "current/Contents/MacOS/TraceFenceAgentCoreUpdater"
install_core_link "adapters" "current/Contents/Resources/adapters"

"$INSTALL_DIR/adapters/TraceFenceClaudeAdapter" --import-environment

mkdir -p "$LAUNCH_AGENT_DIR" "$LOG_DIR"
chmod 700 "$INSTALL_DIR"

UPDATE_CONFIG_PATH="$INSTALL_DIR/update-config.json"
if [ ! -f "$UPDATE_CONFIG_PATH" ]; then
  cp "$CORE_DIR/update-config.example.json" "$UPDATE_CONFIG_PATH"
fi
chmod 600 "$UPDATE_CONFIG_PATH"

TOKEN="$(defaults read com.tracefence.app traceFenceIOSRemoteGatewayToken 2>/dev/null || true)"
if [ "$(printf '%s' "$TOKEN" | wc -c | tr -d ' ')" -lt 32 ]; then
  TOKEN="$(openssl rand -hex 32)"
  defaults write com.tracefence.app traceFenceIOSRemoteGatewayToken "$TOKEN"
fi
REMOTE_ENABLED="$(defaults read com.tracefence.app traceFenceIOSRemoteGatewayEnabled 2>/dev/null || echo 0)"
if [ "$REMOTE_ENABLED" = "1" ]; then
  REMOTE_ENABLED_JSON=true
else
  REMOTE_ENABLED_JSON=false
fi
CONTROL_ALLOWED="$(plutil -extract controlAllowed raw "$HTTP_CONFIG_PATH" 2>/dev/null || echo false)"
case "$CONTROL_ALLOWED" in
  true|false) ;;
  *) CONTROL_ALLOWED=false ;;
esac
CHANNEL="$(plutil -extract channel raw "$HTTP_CONFIG_PATH" 2>/dev/null || echo direct)"
TIER="$(plutil -extract tier raw "$HTTP_CONFIG_PATH" 2>/dev/null || echo directStandard)"

cat > "$HTTP_CONFIG_PATH" <<EOF
{
  "port": 17896,
  "token": "$TOKEN",
  "enabled": $REMOTE_ENABLED_JSON,
  "controlAllowed": $CONTROL_ALLOWED,
  "channel": "$CHANNEL",
  "tier": "$TIER"
}
EOF
chmod 600 "$HTTP_CONFIG_PATH"

cat > "$LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tracefence.agent-core</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/TraceFenceAgentCore</string>
    <string>--socket</string>
    <string>$SOCKET_PATH</string>
    <string>--http-config</string>
    <string>$HTTP_CONFIG_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$CORE_PATH</string>
    <key>TMPDIR</key>
    <string>$USER_TEMP_DIR</string>
  </dict>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/agent-core.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/agent-core.error.log</string>
</dict>
</plist>
EOF

chmod 600 "$LAUNCH_AGENT_PATH"
plutil -lint "$LAUNCH_AGENT_PATH" >/dev/null

cat > "$CLAUDE_ADAPTER_LAUNCH_AGENT_PATH" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.tracefence.adapter.claude</string>
  <key>ProgramArguments</key>
  <array>
    <string>$INSTALL_DIR/adapters/TraceFenceClaudeAdapter</string>
    <string>--daemon</string>
    <string>--socket</string>
    <string>$CLAUDE_ADAPTER_SOCKET_PATH</string>
    <string>--hook-socket</string>
    <string>$CLAUDE_HOOK_SOCKET_PATH</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>ProcessType</key>
  <string>Background</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>$CORE_PATH</string>
    <key>TMPDIR</key>
    <string>$USER_TEMP_DIR</string>
  </dict>
  <key>ThrottleInterval</key>
  <integer>5</integer>
  <key>StandardOutPath</key>
  <string>$LOG_DIR/claude-adapter.log</string>
  <key>StandardErrorPath</key>
  <string>$LOG_DIR/claude-adapter.error.log</string>
</dict>
</plist>
EOF

chmod 600 "$CLAUDE_ADAPTER_LAUNCH_AGENT_PATH"
plutil -lint "$CLAUDE_ADAPTER_LAUNCH_AGENT_PATH" >/dev/null

launchctl bootout "gui/$(id -u)/com.tracefence.codex-adapter" >/dev/null 2>&1 || true
rm -f "$CODEX_ADAPTER_LAUNCH_AGENT_PATH"
rm -rf "$INSTALL_DIR/TraceFence Codex Adapter.app"
pkill -f "TraceFenceCodexAdapterHost" >/dev/null 2>&1 || true
pkill -f "codex app-server --listen ws://127.0.0.1:17897" >/dev/null 2>&1 || true

if [ -x "$MANAGED_CODEX" ]; then
  "$MANAGED_CODEX" app-server daemon bootstrap >/dev/null
  CODEX_DAEMON_READY=false
  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if [ -S "$HOME/.codex/app-server-control/app-server-control.sock" ]; then
      CODEX_DAEMON_READY=true
      break
    fi
    sleep 1
  done
  if [ "$CODEX_DAEMON_READY" != "true" ]; then
    printf '%s\n' "Official Codex app-server daemon did not become ready." >&2
    exit 1
  fi
else
  printf '%s\n' "Codex control requires the official standalone CLI: https://chatgpt.com/codex/install.sh" >&2
fi

launchctl bootout "gui/$(id -u)/com.tracefence.adapter.claude" >/dev/null 2>&1 || true
pkill -f "$INSTALL_DIR/adapters/TraceFenceClaudeAdapter --daemon" >/dev/null 2>&1 || true
rm -f "$CLAUDE_ADAPTER_SOCKET_PATH" "$CLAUDE_HOOK_SOCKET_PATH"
launchctl bootstrap "gui/$(id -u)" "$CLAUDE_ADAPTER_LAUNCH_AGENT_PATH"
launchctl enable "gui/$(id -u)/com.tracefence.adapter.claude"
launchctl kickstart "gui/$(id -u)/com.tracefence.adapter.claude"

CLAUDE_ADAPTER_READY=false
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  if [ -S "$CLAUDE_ADAPTER_SOCKET_PATH" ] && [ -S "$CLAUDE_HOOK_SOCKET_PATH" ]; then
    CLAUDE_HEALTH="$(printf '%s\n' '{"method":"health","params":{}}' | "$INSTALL_DIR/adapters/TraceFenceClaudeAdapter" 2>/dev/null || true)"
    case "$CLAUDE_HEALTH" in
      *'"ok":true'*) CLAUDE_ADAPTER_READY=true; break ;;
    esac
  fi
  sleep 1
done
if [ "$CLAUDE_ADAPTER_READY" != "true" ]; then
  printf '%s\n' "Claude adapter daemon did not become ready." >&2
  exit 1
fi
"$INSTALL_DIR/adapters/TraceFenceClaudeAdapter" --install-hooks --hook-socket "$CLAUDE_HOOK_SOCKET_PATH"

if command -v grok >/dev/null 2>&1; then
  "$INSTALL_DIR/adapters/TraceFenceUniversalAdapter" --adapter grok --install-hooks
fi
if command -v qwen >/dev/null 2>&1; then
  "$INSTALL_DIR/adapters/TraceFenceUniversalAdapter" --adapter qwen --install-hooks
fi
if command -v gemini >/dev/null 2>&1; then
  "$INSTALL_DIR/adapters/TraceFenceUniversalAdapter" --adapter gemini --install-hooks
fi
if command -v cursor-agent >/dev/null 2>&1; then
  "$INSTALL_DIR/adapters/TraceFenceUniversalAdapter" --adapter cursor --install-hooks
fi

launchctl bootout "gui/$(id -u)/com.tracefence.agent-core" >/dev/null 2>&1 || true
pkill -f "$INSTALL_DIR/TraceFenceAgentCore --socket $SOCKET_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$LAUNCH_AGENT_PATH"
launchctl enable "gui/$(id -u)/com.tracefence.agent-core"
launchctl kickstart "gui/$(id -u)/com.tracefence.agent-core"

printf '%s\n' "Installed TraceFence Agent Core at $INSTALL_DIR/TraceFenceAgentCore"
printf '%s\n' "Started persistent service com.tracefence.agent-core"
if [ -x "$MANAGED_CODEX" ]; then
  printf '%s\n' "Connected to the official Codex standalone daemon over its local user socket"
fi
printf '%s\n' "Started independently upgradable Claude Code adapter and installed permission hooks"
printf '%s\n' "Registered independently upgradable adapters for Grok, Qwen, Cursor, Trae, CodeBuddy, OpenClaw, Hermes, MiniMax, Gemini, OpenCode, Kiro, Aider, Amp, Goose, Copilot CLI, and Droid"
