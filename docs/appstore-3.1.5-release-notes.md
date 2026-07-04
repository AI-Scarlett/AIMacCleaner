# TraceFence 3.1.5 App Store Metadata

## Review Notes

TraceFence 3.1.5 adds sandbox-safe local capture tools alongside AI quota monitoring. The Mac App Store build does not include proxy/VPN traffic interception, root certificate installation, or third-party model credentials. Clipboard history is off by default, user-controlled, and stored only on this Mac. Screenshot capture uses macOS screen-recording permission and native system APIs.

## Build Notes

- Build: 43
- Architecture: arm64 Mac App Store package, aligned with the bundled quota helper signed as a sandboxed inherited helper.
- Quota helper: `AIMacCleaner/Resources/codexbar` is vendored in the source tree and verified during archive.
- Release metadata: `BuildMachineOSBuild` must be overridden to `25F70` before export so the package does not leak the beta macOS host build.

## What's New

- Adds local screenshot and clipboard history tools in the menu bar.
- Adds native area screenshot and full-screen screenshot copy.
- Makes clipboard history retention configurable from 20 to 500 items.
- Keeps clipboard monitoring off by default and stores capture history only on this Mac.
- Keeps Codex quota, Spark windows, reset credits, token usage, and model attribution improvements from the 3.1.5 line.

## Promotional Text

Monitor AI quota windows and local capture history from one privacy-first Mac menu bar.

## Keywords

AI quota,reset credits,clipboard history,screenshot,token usage,model attribution

## Chinese Positioning

- 核心卖点：AI 额度监控、重置次数监控、本地截图、剪贴板历史。
- 辅助卖点：Token 使用统计、任务级模型归因、本地 Agent 数据读取、隐私优先。
- 避免承诺：不宣传网络出站审计、不宣传真实 IP 检测、不承诺自动重置额度。
