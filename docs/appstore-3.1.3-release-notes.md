# TraceFence 3.1.3 App Store Metadata

## Review Notes

TraceFence 3.1.3 adds sandbox-safe AI quota monitoring for user-authorized local agent data. The Mac App Store build does not include proxy/VPN traffic interception, network egress auditing, root certificate installation, or third-party model credentials. Quota and token attribution features read local agent status/session files only after the user authorizes the relevant data folder.

## Build Notes

- Build: 35
- Architecture: arm64 Mac App Store package, aligned with the bundled quota helper.
- Release metadata: `BuildMachineOSBuild` is overridden to `25F70` before export so the package does not leak the beta macOS host build.

## What's New

Adds AI provider quota monitoring for 5-hour, weekly, and monthly quota windows, plus manual reset credit counts. TokenScope now makes model attribution clearer by showing which task/session used each reported model. The Mac App Store build reads only user-authorized local agent data.

## Promotional Text

Track AI quota windows, manual reset credits, token usage, and model attribution from user-authorized local agent data on your Mac.

## Keywords

AI quota,reset credits,token usage,model attribution,agent monitor,developer tools

## Chinese Positioning

- 核心卖点：AI 额度监控、5 小时/每周/每月额度窗口、手动重置次数监控。
- 辅助卖点：Token 使用统计、任务级模型归因、本地 Agent 数据读取、隐私优先。
- 避免承诺：不宣传网络出站审计、不宣传真实 IP 检测、不承诺自动重置额度。
