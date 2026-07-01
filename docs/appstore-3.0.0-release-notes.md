# AgentGuard 3.0.0 App Store Notes

## What's New

AgentGuard 3.0 brings a deeper native maintenance and AI agent safety workflow for Mac users:

- New Mac maintenance surface inspired by Mole: review project build artifacts, downloaded installers, app-related caches, dependency caches, and local service artifacts before cleanup.
- Improved Agent Monitor audit results: more agent sessions and tool events are parsed from local Codex/Claude-style logs, so audit actions now show concrete records instead of empty states.
- Enhanced guarded directory protection: cleanup of guarded directory items inside AgentGuard requires macOS system authentication.
- New Trash safety reminders for guarded items: AgentGuard tracks protected items moved to Trash, reminds users before emptying Trash, and records a critical audit event if a protected item disappears from Trash.
- Refined App Store-safe app management: installed apps are inventoried with cache context while uninstall/reset actions remain disabled in the Mac App Store build.
- UI updates for Overview, Agent Guard, Agent Monitor, and Maintenance workflows to make review-first cleanup and agent activity auditing easier to understand.

## Review Notes

AgentGuard is a sandboxed macOS utility for local storage review, app/dependency inventory, and AI agent activity monitoring.

All cleanup actions are review-first. Files are moved to Trash where possible, and the app does not perform background deletion after the user quits. Guarded directory cleanup inside the app uses macOS LocalAuthentication (`deviceOwnerAuthentication`) to confirm the user before moving protected items to Trash. AgentGuard does not collect, store, or transmit the user's macOS password.

For App Store safety, AgentGuard does not forcibly intercept Finder or Terminal empty-Trash operations. Instead, it records protected items moved to Trash, displays reminders in the guarded directory UI, and adds audit alerts if protected items are no longer found in Trash.

The app reads only local data the user authorizes through the standard macOS sandbox permission model, security-scoped bookmarks, or files inside the app container. Agent activity audit features use local log/session files and do not rely on proxy interception or network traffic inspection.
