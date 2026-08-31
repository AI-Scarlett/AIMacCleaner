# TraceFence Agent Profile

Agent Profile is a first-party TraceFence plugin for generating one consistent,
provider-neutral language, timezone, coarse-location, and proxy environment for
Codex, Claude, Grok, Gemini, Antigravity, Cursor, OpenCode, DeepSeek Harness,
and other supported desktop or CLI agents. It generates CLI wrappers, desktop
launchers, a Chromium profile extension, and portable JSON/Markdown context.

The plugin deliberately treats network-path validation and provider eligibility
as separate results. A changed IP, locale, or timezone does not prove that a
Google account is eligible for Antigravity. Antigravity is one provider-specific
diagnostic inside the general Agent Profile, not the plugin's only function.
