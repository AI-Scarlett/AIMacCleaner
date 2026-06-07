# Product Overview

## Product

AgentGuard / AIMacCleaner is a native macOS utility focused on storage cleanup, app/dependency management, and AI Agent observability.

## Positioning

The product helps Mac users understand what AI agents and developer tools are doing locally, clean safe cache data, and keep a readable audit trail of agent activity without sending private file contents to external services.

## Core Modules

| Module | User Value | Main Data Sources |
| --- | --- | --- |
| Overview | One-screen status for storage, active sessions, token/context usage, apps, dependencies, and agent activity. | Cached scan snapshots plus background refresh. |
| Mac Cleanup | Find cache, logs, temporary files, and AI/developer tool data that can be cleaned safely. | Local filesystem scan rules and optional AI impact analysis. |
| App Management | List installed `.app` bundles, size, cache/data footprint, reset, basic uninstall, or full uninstall. | `/Applications`, `~/Applications`, app support/cache paths. |
| Dependency Management | Inspect Homebrew, npm, pip, and related developer dependencies. | Local package manager metadata and cache directories. |
| Agent Audit | Parse historical agent session files and file-operation traces. | JSONL, JSON, SQLite, Markdown, and VS Code state databases. |
| Agent Monitor | Track active agent sessions, process trees, ports, memory, current task, model, context, and token usage when available. | Local agent logs, process table, `lsof`, and cached snapshots. |
| Settings | Configure language, AI provider, monitor behavior, safety options, and update flow. | Local preferences and user-authorized paths. |

## Supported Agent Families

AgentGuard targets 50+ AI agent/tool families, including Claude Code, Codex, Cursor, OpenClaw/QClaw, Hermes, MiniMax Agent, Trae, CodeBuddy, Windsurf, Gemini CLI, Kimi, DeepSeek, Copilot, OpenHands, CrewAI, AutoGen, MetaGPT, CAMEL, DeerFlow, Dify, BrowserUse, Huginn, and related VS Code style agents.

## Product Principles

- Prefer local, user-authorized data sources.
- Show cached data immediately, then refresh in the background.
- Never display unknown usage as `0`; use `unreported` when a source does not provide usage.
- Keep model, task summary, session time, and agent identity separate.
- Avoid destructive cleanup by default; require user confirmation for risky actions.
