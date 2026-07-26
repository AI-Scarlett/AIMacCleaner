# TraceFence 1.0.87 audit remediation

This note maps the 2026-07-26 code-review findings to the 1.0.87 hardening
work. It distinguishes complete fixes from mitigations so release decisions do
not rely on an overstated security claim.

## Release-blocking findings

| Finding | 1.0.87 status | Remediation |
| --- | --- | --- |
| Broad app-container cleanup rules | Fixed | Rules now target explicit cache/log subdirectories. `verify_scan_rules.py` rejects duplicate IDs, user-data roots, whole app containers, whole Application Support entries, and Docker VM data during both direct and Mac App Store builds. The deletion path independently repeats canonical-path, symlink, protected-root, container-root, and Docker-VM checks before moving anything to Trash. |
| Unvalidated AI cleanup paths | Fixed | The model only sees candidates from an authorized, explicit cache/log/build-root snapshot. Returned paths must exactly match that snapshot and are revalidated immediately before deletion. AI-derived rows are not restored from a previous app cache. |
| LAN remote-control RCE chain | Mitigated; TLS still pending | The pairing secret is no longer returned by API responses. Requests use timestamp- and nonce-bound HMAC-SHA256 over method, target, and body; replays and stale requests are rejected. Public source addresses, CORS, remote generic-shell targets, and legacy Bearer authentication are rejected. Only the health route is unauthenticated. Transport confidentiality still requires a future TLS certificate-pinning migration. |
| Legacy Python/Web cleaner | Not present | The reviewed `app.py`, `scanner.py`, `ai_scanner.py`, and `static/index.html` files are not in the current source tree. |

## Important findings

| Finding | 1.0.87 status | Remediation |
| --- | --- | --- |
| Hook config overwrite | Fixed | Invalid/empty JSON aborts without mutation. The first pre-TraceFence file is preserved as `.agentguard.bak`, and writes remain atomic. |
| Disk Advisor negation parsing | Fixed | Unsafe/negative phrases are evaluated first; positive actions and risk values require token matches. |
| Fake webhook HMAC / unsafe URL | Fixed for reported cases | Uses CryptoKit HMAC-SHA256, HTTPS-only URLs, redirect revalidation, cookie-free ephemeral sessions, and rejection of loopback/private/link-local/CGNAT/multicast literals. The webhook secret is migrated to Keychain and removed from the JSON config. |
| Profile mirror CORS / traversal / credentials | Mitigated | Removed CORS and OPTIONS support, restricted routing to the exact active profile, removed raw-profile and URL-list HTTP routes, redacted proxy credentials, and set generated files/directories to 0600/0700. A per-launch HTTP token remains future defense-in-depth work. |
| Intel replacement deletes first | Fixed | Architecture is no longer inferred from an install-path prefix. Replacement only opens a validated HTTPS candidate and never removes the installed item; the row stays pending until the user installs and verifies it. |
| Plaintext AI and pairing secrets | Fixed | Mac AI key, Mac pairing secret, iOS pairing secret, and webhook secret use Keychain. Legacy plaintext values are migrated and removed only after a successful secure write. |
| Shared scanner/monitor state races | Fixed for cited state | Agent parsing is serialized separately from the short-lived source/flag lock. Operation-record fingerprint rebuild, prune, load, and flush use one recursive lock. Sensor state is main-actor isolated. |
| Sensor monitor invalid probes / pipe deadlock | Fixed | Replaced Linux device and subprocess heuristics with CoreMediaIO and CoreAudio running-state queries. |
| Shortcut recorder swallows input after navigation | Fixed | Recording stops on tab changes and view disappearance; an inactive monitor returns the event. |
| Unsafe legacy release script | Fixed | `build_native.sh` is now only a strict compatibility wrapper around the Developer ID, Hardened Runtime, verification, notarization, and stapling release pipeline. |
| Global `/tmp` hook socket | Mitigated | Moved to a 0700 user Application Support directory; the socket is 0600 and UTF-8 records are buffered as bytes. Explicit peer-credential verification remains future defense-in-depth work. |
| Personal data and absolute paths | Fixed in current tree | Submission contact fields now come from required environment variables; scripts derive repository/home paths. Rewriting already-published Git history is intentionally outside this non-destructive source change. |

## Additional reliability fixes

- Claude cache creation is priced separately at the 5-minute and 1-hour write
  rates instead of the cache-read rate.
- Disk and cleanup sizes use one Finder-compatible decimal unit basis; swap
  reports current `vm.swapusage`, and process count uses `proc_listallpids`.
- Deleted conversation files are reconciled out of the UI.
- Agent Core metadata reads are capped at 16 MiB.
- Hook transport preserves UTF-8 characters split across network chunks.
- Normal app termination performs synchronous cleanup and no longer schedules a
  forced `exit(0)` that can skip persistence.
- App Store archive metadata is verified against the real build host and is no
  longer rewritten.

## Release gates

Run before packaging:

```bash
python3 scripts/verify_scan_rules.py
python3 -m py_compile scripts/verify_scan_rules.py scripts/tracefence_remote_auth_regression.py
bash -n build_native.sh scripts/build_tracefence_dmg.sh scripts/release_tracefence_mac_appstore.sh
swift build --package-path TraceFenceAgentCore
xcodebuild -project AIMacCleaner.xcodeproj -scheme AIMacCleaner -configuration Release -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project TraceFenceIOS/TraceFenceIOS.xcodeproj -scheme TraceFenceIOS -configuration Release -sdk iphonesimulator CODE_SIGNING_ALLOWED=NO build
```

With an isolated local Agent Core test instance running, also run:

```bash
TRACEFENCE_REMOTE_BASE=http://127.0.0.1:17901 \
TRACEFENCE_REMOTE_TOKEN='<test-token>' \
python3 scripts/tracefence_remote_auth_regression.py
```
