# Agent Monitoring

## Goals

Agent monitoring should answer four questions quickly:

1. Which agent is active?
2. Which session/task is it working on?
3. Which model is being used?
4. How much context and token usage has been reported?

## Data Pipeline

| Stage | Behavior |
| --- | --- |
| Cache read | Load the last successful scan immediately when the app opens. |
| Background scan | Refresh agent roots, app data, dependency data, token usage, and active sessions in the background. |
| Realtime write | Persist active-session and token updates continuously so app restart/update does not reset the page to empty. |
| Merge | Merge live process state with historical session records. |
| Display | Show exact values when available; show `unreported` when the data source does not expose a field. |

## Claude Code Data

Claude Code session files under `~/.claude/projects/**/*.jsonl` usually expose:

| Field | Source |
| --- | --- |
| Model name | Assistant message `message.model` when not `<synthetic>`. |
| Session rounds | Count of assistant messages. |
| User instruction | Latest user message, with title-generator wrapper removed. |
| Input tokens | `message.usage.input_tokens` or `prompt_tokens`. |
| Output tokens | `message.usage.output_tokens` or `completion_tokens`. |
| Cache tokens | `message.usage.cache_read_input_tokens`, `cached_input_tokens`, and `cache_creation_input_tokens`. |
| Current context estimate | `input_tokens + cache_read_input_tokens + cache_creation_input_tokens` from the latest/largest usage record. |
| Context window | Model-specific known window when available, otherwise a conservative default. |

`<synthetic>` is not a real model name. It is an internal Claude-side record used for generated side tasks such as title creation. The UI should not show it as a model, and it should not add words like `title task` to the model column.

## Token and Context Policy

- If a session reports usage, AgentGuard displays the reported/derived values.
- If usage is absent, AgentGuard displays `unreported` instead of `0`.
- If only output tokens are reported, AgentGuard displays output/total based on available values, but context usage may still be incomplete.
- If context window is not known for a model, AgentGuard should keep a documented fallback rather than inventing a precise value.

## Network Interception Policy

AgentGuard should not rely on mitmproxy-style TLS interception in the App Store build. It can expose more data, but it requires proxy configuration, certificate trust, and inspection of user network requests. That is a separate developer-tool mode at most, not a default App Store telemetry path.
