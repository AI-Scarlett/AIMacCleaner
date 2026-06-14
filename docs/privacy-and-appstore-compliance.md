# Privacy and App Store Compliance

## Product Commitments

- AgentGuard scans local paths only after user authorization where sandboxing requires it.
- The app does not upload file contents for cleanup or monitoring.
- AI impact analysis in the Mac App Store build should use Apple Intelligence on-device through Apple's public Foundation Models framework.
- The Mac App Store build should not require or expose user-configured third-party AI model credentials.
- Unknown model/token/context values must be displayed as `unreported`, not as fake zeros.
- Users must be able to understand what is being monitored and why.

## Data Categories

| Category | Examples | Handling |
| --- | --- | --- |
| File metadata | Path, size, modified time, risk category | Local scan and local cache. |
| Agent session metadata | Agent name, session id, project path, current instruction summary, model, turns, token usage when reported | Local parse and local cache. |
| Process metadata | PID, command name, parent/child relation, memory, ports | Local runtime monitor. |
| AI request metadata | Directory names and sizes for impact analysis | Processed on-device with Apple Intelligence in the Mac App Store build. |

## App Store Notes

The App Store build should prefer:

- User-authorized local files.
- System APIs such as process/file metadata where allowed.
- Apple Intelligence / Foundation Models for AI summaries and recommendations when available.
- Clear privacy labels and review notes for data that is collected or cached.
- Optional controls for monitoring features.

The App Store build should avoid:

- User-configured third-party model credentials as the default AI path.
- Transparent TLS interception.
- Installing or asking users to trust a root certificate for general traffic inspection.
- Capturing request/response bodies from unrelated apps.
- Default-on proxy/VPN behavior for extracting model/token data.

## Apple Intelligence AI Analysis

The App Store build uses Apple's public Foundation Models framework as the AI analysis engine. The app checks model availability at runtime and reports the system reason when Apple Intelligence is unavailable, such as device eligibility, Apple Intelligence being disabled, or the model still preparing.

AI scan prompts are built from local directory summaries: path labels, child names, sizes, and cleanup context. The app does not send file contents, documents, credentials, or unrelated app traffic to a third-party model for this feature. Users still authorize scan locations through the macOS sandbox file access flow before those locations are analyzed.

The AI output is treated as a recommendation layer. Cleanup still uses the existing reviewed scan item model, risk labels, and user confirmation flow. High-risk App Store-sensitive actions such as full app uninstall/reset remain disabled in the Mac App Store build.

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
