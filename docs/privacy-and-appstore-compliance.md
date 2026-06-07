# Privacy and App Store Compliance

## Product Commitments

- AgentGuard scans local paths only after user authorization where sandboxing requires it.
- The app does not upload file contents for cleanup or monitoring.
- AI impact analysis should send only minimal metadata needed for the request.
- Unknown model/token/context values must be displayed as `unreported`, not as fake zeros.
- Users must be able to understand what is being monitored and why.

## Data Categories

| Category | Examples | Handling |
| --- | --- | --- |
| File metadata | Path, size, modified time, risk category | Local scan and local cache. |
| Agent session metadata | Agent name, session id, project path, current instruction summary, model, turns, token usage when reported | Local parse and local cache. |
| Process metadata | PID, command name, parent/child relation, memory, ports | Local runtime monitor. |
| AI request metadata | Directory names and sizes for impact analysis | Sent only to the user-configured provider when the user requests AI analysis. |

## App Store Notes

The App Store build should prefer:

- User-authorized local files.
- System APIs such as process/file metadata where allowed.
- Clear privacy labels and review notes for data that is collected or cached.
- Optional controls for monitoring features.

The App Store build should avoid:

- Transparent TLS interception.
- Installing or asking users to trust a root certificate for general traffic inspection.
- Capturing request/response bodies from unrelated apps.
- Default-on proxy/VPN behavior for extracting model/token data.

Relevant Apple policy anchors:

- App Store Review Guideline 2.5.1: apps may only use public APIs and should use APIs/frameworks for their intended purposes.
- App Store Review Guideline 2.5.14: apps that record user activity must request explicit user consent and provide a clear indication.
- Mac App Store software requirements: apps should be sandboxed and must not run background code after the user quits without consent.
- Apple Network Extensions Entitlement documentation: App Store apps need the Network Extensions capability in Xcode to customize networking features.

## Claude Token Strategy

For Claude, the recommended App Store-safe strategy is:

1. Parse `~/.claude/projects/**/*.jsonl` after the user authorizes the Claude data directory.
2. Use `message.model` for model name when it is a real model.
3. Use `message.usage` for token and context estimates when present.
4. Display `unreported` for missing usage fields.
5. Document that full request/response interception is not used in the App Store build.

## Optional Developer Mode

A separate, explicitly opt-in developer mode could support proxy-based inspection outside the App Store build. It must be off by default, disclose what traffic is inspected, avoid unrelated traffic, and never be required for normal product value.
