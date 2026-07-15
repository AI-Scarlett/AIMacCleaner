# TraceFence v2 Two-Track Subscription and Remote Control Plan

Date: 2026-07-09

## Product Lines

TraceFence v2 uses two macOS distribution lines and one shared iOS client.

| Line | Payment | Feature Level | Notes |
| --- | --- | --- | --- |
| Mac App Store | Apple in-app subscription | Standard | Monthly/yearly subscription. Same price and core feature level as Website Standard. No external checkout, no direct updater, no system-extension firewall promise. |
| Website Standard | Dodo Payments subscription | Standard | Current website feature set. Monthly is $9.99 and annual is $79.99. Dodo Payments provides checkout, subscription billing, tax handling, invoices, and license-key entitlement delivery. |

There is no Website Enhanced tier in the current product. A future multi-Mac plan may be designed after centralized iOS management and concurrent device authorization are implemented and tested.

## iOS Client

The iOS app remains one app. It pairs with either Mac build and reads the Mac's reported channel:

- `appStore`: Apple subscription unlocks Standard.
- `direct`: A Dodo Payments license unlocks Website Standard.

The iOS UI should not sell separate tiers. It should explain what the paired Mac supports and send users back to the Mac build's correct subscription surface.

Current implementation lives in `TraceFenceIOS/` as a standalone SwiftUI iOS project. It can scan the Mac pairing QR code, import copied pairing JSON, persist the Mac endpoint/token locally, fetch `/v1/status`, and send remote monitor start/stop commands.

## No Backend Remote Control

TraceFence will not operate a cloud relay or store user agent data. Remote control over the Internet therefore requires one user-owned connectivity path:

| Mode | User Dependency | Recommended Use |
| --- | --- | --- |
| Same Wi-Fi or LAN | Mac and iPhone on the same network | Easiest local setup. Not Internet remote. |
| Private VPN / Tailnet | Tailscale, ZeroTier, WireGuard, or company VPN on both devices | Recommended Internet setup without TraceFence backend. |
| Port forwarding + DDNS | Router port forward, firewall rule, DDNS/static IP | Power-user option. Must use encrypted pairing and clear risk copy. |
| User-owned reverse tunnel | Cloudflare Tunnel, frp, SSH reverse tunnel, or VPS relay | Flexible option where the tunnel provider is outside TraceFence. |

The clients must say plainly that Internet access depends on the user's network path. TraceFence can provide pairing, encrypted local API, token rotation, and status checks, but cannot make an unreachable Mac reachable without a network path.

## Current Code Hooks

The first implementation pass added:

- `TraceFenceDistributionPolicy` for channel and plan detection.
- `TraceFenceSubscriptionTier` for App Store Standard and Website Standard gating.
- `AppStoreSubscriptionService` for StoreKit product loading, purchase, restore, and entitlement refresh.
- Dodo Payments static checkout links for Website Standard monthly and annual billing.
- Public Dodo Payments license activation, validation, and deactivation calls, with business-ID and product-ID allowlists. No Dodo API secret is embedded in the app.
- Settings UI that explains both macOS lines and the no-backend remote control options.
- `IOSRemoteControlGatewayService`, a default-off local HTTP JSON API for the shared iOS client.
- Build-time channel switching through `TRACEFENCE_DISTRIBUTION_CHANNEL`; default local builds remain `direct`, while App Store builds can pass `TRACEFENCE_DISTRIBUTION_CHANNEL=appStore`.
- App Store channel gating for updates: website DMG update checks and installers are suppressed when the channel is `appStore`.
- `TraceFenceIOS`, a buildable SwiftUI iOS client with Dashboard, Pairing, and Connection Guide tabs.
- QR pairing: Mac Settings renders a compact pairing QR code; the iOS client can scan it with the camera or import copied JSON.

Initial local API endpoints:

| Endpoint | Auth | Purpose |
| --- | --- | --- |
| `GET /v1/health` | None | Basic reachability check. |
| `GET /v1/status` | Bearer pairing token | App/channel/subscription/system status and supported no-backend connectivity modes. |
| `GET /v1/agents` | Bearer pairing token + active entitlement | Active Hook sessions, monitor snapshots, pending approvals, recent activity, and per-session control capabilities. |
| `GET /v1/events` | Bearer pairing token + active entitlement | Recent Agent activity timeline. |
| `GET /v1/approvals` | Bearer pairing token + active entitlement | Pending Hook permission, question, and plan approvals. |
| `POST /v1/approvals/approve` | Bearer pairing token + active entitlement | Approve a pending Hook request and resume its blocked continuation. |
| `POST /v1/approvals/deny` | Bearer pairing token + active entitlement | Deny a pending Hook request. |
| `POST /v1/sessions/launch` | Bearer pairing token + active entitlement | Launch a CLI Agent through TraceFence-owned PTY so iOS can truly interrupt, continue, and inject instructions. |
| `POST /v1/sessions/interrupt` | Bearer pairing token + active entitlement | Interrupt a session only when the Mac reports a controllable runtime target. |
| `POST /v1/sessions/resume` | Bearer pairing token + active entitlement | Continue a session only through Hook continuation, writable tty, or process resume capability. |
| `POST /v1/sessions/terminate` | Bearer pairing token + active entitlement | End a TraceFence-owned PTY session or a safely attached CLI runtime. |
| `POST /v1/monitor/start` | Bearer pairing token + active entitlement | Start Mac monitoring from iOS. |
| `POST /v1/monitor/stop` | Bearer pairing token + active entitlement | Stop Mac monitoring from iOS. |

The pairing payload copied from Settings includes the endpoint, token, channel, local addresses, and user-owned connectivity requirements. It is intentionally local-first and does not contact a TraceFence backend.

## Control Plane Contract

The Mac API must be treated as the source of truth for control ability. Every session returned to iOS includes:

- `controlMode`: `hook_question`, `hook_approval`, `process_group`, `process_tree`, `single_process`, or `display_only`.
- `controlAvailable`: whether the row has any real control path.
- `canInterrupt` / `canResume` / `canTerminate`: whether the specific buttons should be enabled.
- `resumeRequiresInstruction`: whether iOS must collect a user instruction before continuing.
- `controlReason`: machine-readable reason for the current mode.
- `controlLimitations`: user-facing limitations for the current row.
- `deliveryModes`: `hook_question`, `hook_approval`, `tty`, and/or `signal`.

This avoids presenting log/database/GUI snapshots as controllable tasks. A session may be visible and active but still be `display_only` when TraceFence cannot bind it to a Hook continuation, TraceFence-owned PTY, Agent API, or safe CLI process group.

## Real Control Boundaries

| Mode | Real effect | Product meaning |
| --- | --- | --- |
| `tracefence_pty` | TraceFence starts and owns the CLI terminal, writes user instructions, and controls the process group. | Preferred true remote control path. |
| `hook_question` | Sends the iOS reply into the blocked Hook continuation. | True task continuation. |
| `hook_approval` | Approves or denies a blocked permission/plan request. | True remote approval. |
| `process_group` / `process_tree` / `single_process` | Sends SIGSTOP/SIGCONT to a safe CLI runtime target. | Execution control only; it does not rewrite model context. |
| `display_only` | No control action is available. | Observation only; buttons must stay disabled. |

The current Standard plan only claims controls backed by the capability contract above. A future multi-Mac plan must be based on real centralized device management and simultaneous authorization, not on renaming existing local features.

## Required Follow-up Work

- Add real App Store product IDs in App Store Connect and update `TraceFenceAppStoreMonthlyProductID` / `TraceFenceAppStoreYearlyProductID`.
- Complete Dodo Payments Test Mode checkout and license lifecycle tests for both Standard products.
- Before release, copy both products to Dodo Live Mode, replace both product IDs, and set `TRACEFENCE_DODO_ENVIRONMENT=live`.
- Publish `purchase-success.html` before enabling the live checkout buttons.
- Add dedicated release scripts/schemes for Website and App Store builds so the channel override, signing, export options, and notarization/App Store upload paths cannot be mixed accidentally.
- Harden the TraceFence PTY runner with richer terminal history and per-Agent launch presets.
- Expand Agent adapters from installation/status into runtime controls: `observe`, `interrupt`, `resume(instruction)`, `approve`, `deny`, and `capabilities`.
