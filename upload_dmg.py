#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

REPO = "AI-Scarlett/TraceFence"
APP_NAME = "TraceFence"
VERSION = os.environ.get("TRACEFENCE_VERSION", "1.1.5")
TAG = f"v{VERSION}"
DMG_PATH = f"/tmp/{APP_NAME}-{TAG}-arm64.dmg"
RELEASE_NAME = f"{APP_NAME} {TAG}"
MANIFEST_NAME = "tracefence-update.json"
RELEASE_BODY = (
    "TraceFence direct-download release.\n\n"
    "- Moves API-equivalent model pricing into a versioned public GitHub catalog that the direct-download client refreshes with strict validation, ETag caching, and an offline built-in fallback.\n"
    "- Applies OpenAI's July 30 GPT-5.6 Terra and Luna reductions only from their effective date, while preserving earlier usage at the historical reference prices.\n"
    "- Reprices compact local usage counters when the catalog revision changes, without replaying multi-gigabyte Agent transcripts.\n"
    "- Fixes inflated Codex token totals by removing inherited parent counters replayed inside forked subagent rollouts, with a one-time targeted cache migration and append-only refreshes afterward.\n"
    "- Makes installer and distribution-package findings actionable from the storage overview: filter candidates, inspect originals, select explicitly, and move only the chosen files to Trash.\n"
    "- Clarifies that exact duplicate media embedded in Agent histories is analysis-only and remains protected unless a future cold-archive workflow can preserve session integrity.\n"
    "- Adds public API-equivalent pricing for GPT-5.6 Sol/Terra/Luna, Claude Opus 5/Fable 5, and MiniMax M3/M2.7, calculated from input, cached-input, output, and long-context tiers where applicable.\n"
    "- Reprices compact usage caches without rescanning multi-gigabyte transcripts, while internal or unpublished model aliases now show Price unknown instead of a misleading $0.00.\n"
    "- Adds a bounded, metadata-only file inventory grouped by images, videos, audio, documents, archives, installers, code, and other formats, with size plus last-opened, accessed, and modified dates.\n"
    "- Adds 7-, 30-, and 90-day inactivity filters, Quick Look and Finder inspection, and explicit selection before any file is moved to Trash.\n"
    "- Adds incremental Agent and build storage analysis for exact duplicate media, historical build outputs, and DMG/IPA/APK/EXE-style distribution artifacts while preserving original sessions and the newest three builds per group.\n"
    "- Fixes the menu-bar Open TraceFence Console action so a closed main window is reliably recreated, activated, and brought to the front.\n"
    "- Aligns Overview, Token & Usage, and the menu-bar snapshot on the same cached aggregate, with visible refresh and backfill status.\n"
    "- Hardens Agent hooks, webhook delivery, local profile serving, and protected-content scanning while keeping read/list/search tools responsive when a hook times out.\n"
    "- Tightens iOS local-network transport defaults without changing the compact pairing QR or existing pairing identity.\n"
    "- Completes localized Disk Advisor verdicts and explanations.\n"
    "- Promotes Claude Fable to a first-class weekly quota in the menu-bar title, detailed quota deck, and primary-metric settings, including its own remaining percentage and reset time.\n"
    "- Removes legacy WeChat, QQ, DingTalk, WPS, and XMind cleanup targets; TraceFence has no integration with those apps and no longer scans their containers.\n"
    "- Adds strict cleanup-path allowlists, symlink and protected-root checks, and a build-time rule audit to prevent broad app-container or user-data deletion.\n"
    "- Replaces iOS Remote Pairing Bearer requests with timestamp- and nonce-bound HMAC-SHA256 authentication, replay protection, private-source checks, and removal of the remote generic-shell target.\n"
    "- Moves pairing, AI-provider, and webhook secrets to Keychain with migration safeguards that preserve the old record if secure storage fails.\n"
    "- Hardens webhooks, local profile serving, hook configuration writes, sensor detection, and direct-download signing and notarization gates.\n"
    "- Reads Claude Desktop's official 5-hour, weekly, and model-scoped weekly windows such as Fable as separate quota rows with their own reset times; credentials stay in memory and are sent only to claude.ai.\n"
    "- Preserves one shared 256-bit iPhone pairing token between the direct-download Mac app and its independently installed Agent Core, so app or Core upgrades cannot invalidate an existing pairing.\n"
    "- Keeps the background Core status endpoint responsive while optional Agent adapters are slow or unhealthy, preventing heartbeat timeouts from appearing as intermittent disconnects.\n"
    "- Replaces same-version Agent Core bundles through a clean verified staging directory so stale backup files cannot corrupt an update signature.\n"
    "- Stabilizes iOS Remote Pairing by preventing separate TraceFence processes with different pairing tokens from sharing the same TCP listener port.\n"
    "- Keeps trying the paired Mac's foreground and background gateways when one stale endpoint rejects an old token, instead of turning endpoint startup races into intermittent disconnects.\n"
    "- Clears stale remote status immediately when a new pairing code is imported, so old online indicators cannot mask a failed re-pair.\n"
    "- Rebuilds the menu-bar panel as a continuous-corner live deck with glass telemetry cards, clearer hierarchy, and reliable first-click navigation.\n"
    "- Merges the sparse Usage tab into Provider Quota so live local Token totals, cache status, and provider reset windows share one actionable page.\n"
    "- Unifies Overview and Token & Usage on one combined local snapshot across Codex, Claude Code, OpenCode / MiniMax, and OpenClaw / QClaw, with consistent B/M/K formatting and exact token counts.\n"
    "- Persists final aggregate snapshots so large local histories render immediately, while cheap source fingerprints and per-file parser caches limit refresh work to changed data.\n"
    "- Completes explicitly requested Codex history backfill in one cancellable pass and reports checked, remaining, skipped, and failed sessions instead of ending with ambiguous progress.\n"
    "- Restores automatic Grok quota discovery in the main window and menu bar when Grok is installed locally.\n"
    "- Caps universal Agent approval hooks at five seconds and lets timed-out read/list/search operations continue, preventing TraceFence from freezing Grok file tools.\n"
    "- Adds a 180-day activity heatmap, 7-day comparison, project/tool/Skill rankings, and a four-lane current-task board without storing prompts, replies, tool bodies, or credentials.\n"
    "- Adds visible local-scan progress, bounded incremental caches, system/UTC/fixed-IANA day boundaries, diagnostics, cache clearing, and redacted JSON export.\n"
    "- Adds icon-only, single-metric, and detailed menu-bar modes with used/remaining quota choice, today-token metrics, and reset countdowns.\n"
    "- Preserves last-known-good provider quotas during temporary failures, strictly classifies official Codex 5-hour/7-day windows, and hardens customizable shortcut conflict validation.\n"
    "- Makes current-task artifacts responsive even for near-gigabyte conversations by scanning only the latest 16 MiB on first open and loading complete history only when the user explicitly requests it.\n"
    "- Shows whether the artifact shelf is reading recent records, displaying a partial history, loading the full history, paused, complete, or failed, while keeping already found outputs available.\n"
    "- Stops Agent launch alert floods by recognizing only real desktop/CLI entry processes, excluding system tools, app helpers, and TraceFence-owned probes, and emitting one alert per Agent availability transition.\n"
    "- Moves rollout-summary parsing off the main actor, caches unchanged logs by file identity, and reduces repeated catalog publication during background refreshes.\n"
    "- Pauses task following and indexing while an artifact is being read, reuses Accessibility selections, and uses a lightweight private HTML preview for smoother scrolling.\n"
    "- Rebuilds iOS Remote Pairing QR codes with a compact pairing URI, a proper quiet zone, and pixel-aligned rendering for reliable scanning from the Mac display.\n"
    "- Prevents Agent Guard from automatically traversing protected Music, Movies, and Photos libraries when a parent Home folder was previously authorized.\n"
    "- Adds a compact TraceFence-icon artifact capsule that follows the active Codex, Claude, or Cursor task and expands only when needed.\n"
    "- Shows the current or selected historical task's final user-facing deliverables, with code, configuration, draft, and process files filtered by default.\n"
    "- Opens Markdown, HTML, images, and directories inside the TraceFence sidecar instead of sending users to Finder.\n"
    "- Streams very large historical Codex rollouts incrementally in the background, avoiding main-thread stalls while preserving searchable older artifacts.\n"
    "- Enables the production Dodo Payments Standard monthly and annual subscriptions with live checkout and strict business/product license validation.\n"
    "- Restores continuous Agent Guard ingestion after long-running sessions and detects destructive commands nested inside Codex functions.exec payloads.\n"
    "- Removes duplicate overview refresh stores and timers to reduce sustained CPU and memory use.\n"
    "- Moves Codex approval-log discovery and incremental JSONL parsing off the main actor so background monitoring no longer stalls the desktop UI.\n"
    "- Fixes duplicate TraceFence desktop windows caused by the legacy SwiftUI WindowGroup state and the former AppKit fallback window racing during launch.\n"
    "- Migrates the desktop shell to one uniquely identified main window, closes stale restored duplicates, and safely reopens the same scene when upgrading from an older saved window state.\n"
    "- Keeps repeated Finder, Dock, and updater launches attached to the existing TraceFence process and main window.\n"
    "- Simplifies Agent Environment Profile actions: Codex and Claude stay as primary one-click controls, while all other installed desktop and CLI agents move into More Agents.\n"
    "- Adds a shared Agent catalog for desktop apps and CLIs so More Agents and Provider Quota only show agents that are actually installed on the Mac.\n"
    "- Fixes Grok CLI login/network failures caused by injecting a stale proxy URL into agent processes; launchers now keep language, timezone, and local probe overrides without forcing HTTP_PROXY/HTTPS_PROXY.\n"
    "- Keeps the configured proxy as profile metadata for detection and agent-aware integrations through TRACEFENCE_PROFILE_PROXY_URL instead of overriding process networking by default.\n"
    "- Fixes Grok CLI launched from a normal Terminal by automatically managing `~/.grok/bin/grok` while Agent Environment Profile is enabled, so direct `grok` commands inherit TraceFence timezone, locale, proxy, PATH shims, and profile URLs.\n"
    "- Restores the original Grok symlink or command when Agent Environment Profile is turned off, keeping the takeover reversible and beginner-friendly.\n"
    "- Adds a universal local Agent Profile endpoint for new CLIs and desktop agents: TraceFence now serves the generated profile from a read-only 127.0.0.1 URL while the Agent Environment Profile switch is on.\n"
    "- Generates stable `agent-profile.json`, `agent-profile.md`, and `profile-url.txt` files and injects `TRACEFENCE_PROFILE_URL`, `TRACEFENCE_PROFILE_CONTEXT_URL`, `TRACEFENCE_PROFILE_PATH`, and `AGENT_PROFILE_URL` into TraceFence-launched agent environments.\n"
    "- Adds a beginner-friendly Universal Profile section in Settings with running status plus Open Profile, Open Context, and Copy Link actions for troubleshooting.\n"
    "- Adds Grok CLI coverage to Agent Environment Profile with `tf-grok`, a direct `grok` command shim, and one-click Grok/Profile Shell terminal launchers.\n"
    "- Routes normal CLI agent commands such as `grok`, `codex`, and `claude` through generated Profile shims when the TraceFence CLI shell is active.\n"
    "- Sorts Provider quota cards so Agents with readable quota data appear before unused or unconfigured provider diagnostics.\n"
    "- Makes AI Disk Advisor scan/analyze activity much more visible with the same radar-style status indicator used by Overview.\n"
    "- Adds strong Codex / Claude Code CLI update reminders to the existing Check for Updates flow, including startup auto-checks, in-app alerts, and macOS notifications.\n"
    "- Adds a default-on Strong Reminder switch in Settings so users can disable CLI update popups while keeping passive status checks visible.\n"
    "- Checks local `codex` and `claude` commands against npm registry latest versions and surfaces broken CLI installs whose version cannot be read.\n"
    "- Adds an AI CLI Security Updates panel in Settings with local/latest versions, package links, and one-click copyable upgrade commands.\n"
    "- Fixes Codex Desktop reconnect loops when Agent Environment Profile is enabled by clearing HTTP_PROXY, HTTPS_PROXY, and ALL_PROXY for desktop launchers while keeping language, timezone, and local probe overrides active.\n"
    "- Keeps desktop Agent launch and restart buttons available after Agent Environment Profile is turned off, so they can still be used as normal app launch controls.\n"
    "- Makes Restart Codex and other restart actions wait for the existing app to quit, then force-terminate remaining processes before launching the app again automatically.\n"
    "- Adds one-click Open Codex and Restart Codex actions in Agent Environment Profile settings so users do not have to find generated .command launchers manually.\n"
    "- Adds a More Agents launcher menu for Claude, Cursor, Windsurf, VS Code, ChatGPT, Trae, and Codex desktop apps.\n"
    "- Adds a clear TRACEFENCE=1 environment marker to generated profiles while keeping timezone and language overrides active for local shell probes.\n"
    "- Adds a generated Codex desktop launcher so Codex.app can be relaunched through the Agent Environment Profile instead of leaking the normal Dock/Finder-launched macOS language and timezone.\n"
    "- Replaces the browser extension button with a browser picker for Chrome, Edge, Brave, Arc, and Vivaldi, and opens the generated BrowserExtension folder for loading in Developer Mode.\n"
    "- Clarifies that browser pages use the extension, while Codex/Claude/Cursor desktop apps need generated launchers and CLI agents need tf-* wrappers.\n"
    "- Hardens Agent Environment Profile for Codex/Claude-style local probes: generated wrappers now mirror timezone and language through `systemsetup`, `defaults`, `locale`, `/etc/localtime`, nested `zsh -lc`, nested `bash -lc`, and related local shell checks.\n"
    "- Refreshes already-enabled Agent Environment Profiles automatically on app launch so existing users receive the new shell/profile shims after updating without manually regenerating the profile.\n"
    "- Keeps the menu-bar monitor on a dedicated AppKit panel instead of an `NSPopover`, avoiding the AppKit popover crash seen in direct builds.\n"
    "- Fixes Docker image/container storage reporting by counting sparse disk images such as Docker.raw by actual allocated disk blocks instead of virtual logical size.\n"
    "- Refreshes scan cache compatibility so old oversized Docker cleanup results are discarded after update.\n"
    "- Moves Agent Environment Profile out of Lab into its own Settings tab so the long configuration page has room to breathe.\n"
    "- Changes Agent Environment Profile into a beginner-friendly start switch: turning it on automatically generates and enables the local profile, while turning it off writes a disabled profile state.\n"
    "- Adds the same Agent Environment Profile switch to the menu-bar System Monitor popover for quick start/stop without opening full Settings.\n"
    "- Adds direct-build Agent Environment Profile: generate proxy-aligned browser extension, CLI wrappers, and desktop launchers for Claude, Cursor, Windsurf, VS Code, ChatGPT, Codex, Gemini, and other agents.\n"
    "- Lets users configure proxy URL, country/city, IANA timezone, locale, languages, Accept-Language, and coarse geolocation without changing macOS global language or timezone.\n"
    "- Optimizes Agent Monitor performance: project-board snapshots are cached, live detail filtering is reused per render, and expensive audit/analytics refresh work is throttled so the page stays responsive during long monitoring sessions.\n"
    "- Reduces background CPU spikes by lowering process/lsof/snapshot fallback polling cadence while keeping FSEvents-based realtime monitoring active.\n"
    "- Rebuilds the visible Agent Monitor page as a project-management board with live projects, scheduled work, blockers, recent completion lanes, project progress, session flow, active tools, and audit timeline details.\n"
    "- Adds Local Diagnostics for public IP, local network interfaces, key endpoint reachability, and read-only LaunchAgent/LaunchDaemon review.\n"
    "- Adds an explicit Clear Clipboard action that clears the current pasteboard without reading clipboard history.\n"
    "- Adds a TraceFence-owned Tools entry inspired by MacTools while keeping App Store-safe read-only boundaries and direct-build advanced maintenance separation.\n"
    "- Fixes AI Disk Advisor responses wrapped in Markdown or prose so valid structured cleanup advice is still parsed instead of showing a JSON error.\n"
    "- Keeps AI Disk Advisor usable when the model returns partial or non-JSON text by falling back to local rule suggestions without a blocking alert.\n"
    "- Restores the AI Settings entry in the direct-download Settings window so model strategy and external provider configuration are available in both release routes.\n"
    "- Makes the Lab and Toolbox navigation scroll internally so expanded tools no longer push the top identity area or bottom controls out of view.\n"
    "- Adds an explicit AI model mode: Auto, Apple Intelligence only, or External provider only.\n"
    "- Defaults AI Disk Advisor to Apple Intelligence first, then falls back to the configured external model only when Apple is unavailable.\n"
    "- Fixes external model HTTP 404s caused by appending duplicate OpenAI-compatible chat-completions paths; API Base can now be a host root, a /v1 base, or a full /chat/completions URL.\n"
    "- Shows a metadata-sharing confirmation before any AI Disk Advisor request can use a third-party model provider.\n"
    "- Keeps the AI Disk Advisor source path compatible with Mac App Store sandbox rules by scanning only user-authorized folders in sandboxed builds.\n"
    "- Adds an experimental AI Disk Advisor in Lab for the direct-download build.\n"
    "- Uses Apple Intelligence or a user-configured OpenAI-compatible model to explain disk usage, cleanup risk, and likely impact before deleting anything.\n"
    "- Detects high-value disk pressure sources such as temporary build files, simulator devices, simulator dyld caches, Downloads, hidden app data, package caches, Xcode derived data, app update caches, and generated media/task outputs discovered under project folders.\n"
    "- Avoids machine-specific directory names; personal directories, hidden app state, simulator devices, Xcode archives, and project roots stay conservative by default so users explicitly choose what to move to Trash.\n"
    "- Adds a local capture shelf in the menu bar for screenshots and clipboard history.\n"
    "- Adds native area screenshot capture and full-screen screenshot copy without third-party runtime tools.\n"
    "- Makes clipboard history retention user-configurable from 20 to 500 items instead of a fixed 100-item cap.\n"
    "- Keeps clipboard monitoring off by default and stores captured text, images, and file references only on this Mac.\n"
    "- Separates the capture overlay implementation from the capture history service for cleaner maintenance.\n"
    "- Shows Codex Spark 5-hour and weekly quota windows from the bundled provider quota engine.\n"
    "- Uses Codex OAuth quota data when available so Spark and reset-credit rows match the direct-download build.\n"
    "- Keeps Codex manual reset credits visible even when the remaining count is 0.\n"
    "- Adds a radar-style scanning indicator to the overview dashboard.\n"
    "- Tidies the Settings feature-toggle layout into one consistent grouped section.\n"
    "- Makes direct updates more resilient with retry logic and a fallback release manifest for GitHub API/TLS failures.\n"
    "- Localizes provider quota reset-credit labels in Chinese mode, including manual resets and Codex Spark reset windows.\n"
    "- Keeps provider quota service messages language-neutral so menu-bar diagnostics follow the selected app language.\n"
    "- Fixes remaining menu-bar quota window titles that could stay Chinese in English mode.\n"
    "- Replaces the SwiftUI MenuBarExtra entry with a resilient AppKit status item and popover controller.\n"
    "- Rebuilds stale menu bar popovers on click and repairs the status item periodically during long runs.\n"
    "- Adds hard timeouts around provider quota subprocess calls so background quota reads cannot hang indefinitely.\n"
    "- Optimizes Codex rollout discovery to read lightweight metadata instead of loading multi-GB session logs into memory.\n"
    "- Avoids full-text scans of Codex logs_2.sqlite during menu bar agent discovery.\n"
    "- Caches overview dashboard aggregates per render so long-running main windows no longer starve menu bar clicks.\n"
    "- Lowers high-frequency focused-session refresh work to utility priority and a calmer polling cadence.\n"
    "- Opens the status popover on mouse-down for a faster, more native menu bar response.\n"
    "- Limits Codex operation import to recent session files and bounded log tails to avoid long-running CPU spikes.\n"
    "- Replaces expensive full-session UI fingerprints with lightweight count/latest markers.\n"
    "- Stops full historical audit import from running automatically on app launch; audit history now loads from Agent Guard actions.\n"
    "- Caches file modification dates before sorting session logs to avoid repeated filesystem metadata reads.\n"
    "- Fixes direct-update installation hanging when the old app process refuses to quit.\n"
    "- Lets the updater helper terminate the old process and continue installation safely.\n"
    "- Fixes direct-update download validation when GitHub asset metadata is temporarily stale.\n"
    "- Uses SHA256 checksums as the authoritative installer validation when available.\n"
    "- Adds no-cache update checks to avoid stale release metadata after a package replacement.\n"
    "- Bundles the provider quota engine inside TraceFence so releases no longer depend on an external CodexBar checkout.\n"
    "- Closes the menu bar popover when users click outside the panel or press Escape.\n"
    "- Adds configurable shortcuts for opening TraceFence, region screenshots, full screenshots, and screen recording.\n"
    "- Adds a double-click and right-click menu bar emergency menu with refresh, quit, and force-quit actions.\n"
    "- Delays heavier quota and capture startup work until after the popover appears to reduce menu bar stalls.\n"
    "- Uses Dodo Payments Standard monthly or annual subscriptions with local license-key activation.\n"
    "- Restores the default release build path to signed and Apple-notarized output.\n"
)


def release_payload(*, draft):
    return {
        "tag_name": TAG,
        "name": RELEASE_NAME,
        "body": RELEASE_BODY,
        "draft": draft,
        "prerelease": False,
    }


def github_token():
    if os.environ.get("GITHUB_TOKEN"):
        return os.environ["GITHUB_TOKEN"]
    result = subprocess.run(
        ["git", "credential", "fill"],
        input=b"protocol=https\nhost=github.com\n",
        capture_output=True,
        check=False,
    )
    for line in result.stdout.decode().splitlines():
        if line.startswith("password="):
            return line.split("=", 1)[1]
    return None


def request(method, path_or_url, token, data=None, headers=None):
    if path_or_url.startswith("https://"):
        url = path_or_url
    else:
        url = f"https://api.github.com/repos/{REPO}{path_or_url}"
    body = None
    merged_headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": f"{APP_NAME}-release-uploader",
        "Authorization": f"Bearer {token}",
    }
    if headers:
        merged_headers.update(headers)
    if data is not None:
        body = json.dumps(data).encode()
        merged_headers["Content-Type"] = "application/json"
    req = urllib.request.Request(url, data=body, headers=merged_headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            payload = response.read()
            return json.loads(payload.decode()) if payload else None
    except urllib.error.HTTPError as error:
        detail = error.read().decode(errors="replace")
        raise RuntimeError(f"{method} {url} failed: HTTP {error.code} {detail}") from error


def upload_asset(upload_url, token, path, name, content_type):
    with open(path, "rb") as file:
        data = file.read()
    url = upload_url.replace("{?name,label}", "")
    url = f"{url}?{urllib.parse.urlencode({'name': name})}"
    req = urllib.request.Request(
        url,
        data=data,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "Content-Type": content_type,
            "User-Agent": f"{APP_NAME}-release-uploader",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=300) as response:
        return json.loads(response.read().decode())


def sha256_file(path):
    digest = hashlib.sha256()
    with open(path, "rb") as file:
        for chunk in iter(lambda: file.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def find_release_by_tag(token):
    page = 1
    while True:
        releases = request("GET", f"/releases?per_page=100&page={page}", token) or []
        for release in releases:
            if release.get("tag_name") == TAG:
                return release
        if len(releases) < 100:
            return None
        page += 1


def find_or_create_release(token):
    release = find_release_by_tag(token)
    if release:
        if not release.get("draft"):
            raise RuntimeError(
                f"Refusing to replace assets on published release {TAG}. "
                "Publish a new version instead."
            )
        print(f"Resuming draft release {TAG}: {release['html_url']}")
        return request(
            "PATCH",
            f"/releases/{release['id']}",
            token,
            release_payload(draft=True),
        )
    print(f"Creating draft release {TAG}...")
    return request("POST", "/releases", token, release_payload(draft=True))


def verify_uploaded_asset(token, upload_result, local_path, expected_name=None):
    expected_name = expected_name or os.path.basename(local_path)
    expected_size = os.path.getsize(local_path)
    expected_digest = f"sha256:{sha256_file(local_path)}"
    asset_id = upload_result.get("id")
    if not asset_id:
        raise RuntimeError(f"GitHub did not return an asset id for {expected_name}")

    asset = upload_result
    for attempt in range(10):
        if (
            asset.get("state") == "uploaded"
            and asset.get("digest")
        ):
            break
        if attempt < 9:
            time.sleep(1)
            asset = request("GET", f"/releases/assets/{asset_id}", token)

    if asset.get("name") != expected_name:
        raise RuntimeError(
            f"Release asset name mismatch: {asset.get('name')} != {expected_name}"
        )
    if asset.get("state") != "uploaded":
        raise RuntimeError(
            f"Release asset is not ready: {expected_name} ({asset.get('state')})"
        )
    if asset.get("size") != expected_size:
        raise RuntimeError(
            f"Release asset size mismatch: {expected_name} "
            f"({asset.get('size')} != {expected_size})"
        )
    if asset.get("digest") != expected_digest:
        raise RuntimeError(
            f"Release asset digest mismatch: {expected_name} "
            f"({asset.get('digest')} != {expected_digest})"
        )


def publish_release(token, release):
    payload = release_payload(draft=False)
    payload["make_latest"] = "true"
    published = request("PATCH", f"/releases/{release['id']}", token, payload)
    if published.get("draft"):
        raise RuntimeError(f"Release {TAG} is still a draft after publication")
    return published


def clean_release_assets(token, release):
    assets = request("GET", f"/releases/{release['id']}/assets?per_page=100", token) or []
    for asset in assets:
        name = asset["name"].lower()
        if name.endswith(".dmg") or "source" in name or name.endswith(".zip") or name.endswith(".sha256") or name == MANIFEST_NAME:
            print(f"Deleting old asset: {asset['name']}")
            request("DELETE", f"/releases/assets/{asset['id']}", token)


def release_version_key(release):
    tag = release.get("tag_name", "")
    match = re.fullmatch(r"v(\d+)\.(\d+)\.(\d+)", tag)
    if not match:
        return (-1, -1, -1)
    return tuple(int(part) for part in match.groups())


def clean_historical_release_assets(token, keep_release_id, keep_count=3):
    all_releases = []
    page = 1
    while True:
        releases = request("GET", f"/releases?per_page=100&page={page}", token) or []
        if not releases:
            break
        all_releases.extend(releases)
        page += 1

    # Only direct-download app releases use semantic vX.Y.Z tags. Stable
    # component channels such as agent-core-stable have their own lifecycle
    # and must never be pruned by a DMG publication.
    direct_releases = [
        release for release in all_releases
        if release_version_key(release) != (-1, -1, -1)
    ]
    latest_release_ids = {keep_release_id}
    for release in sorted(direct_releases, key=release_version_key, reverse=True):
        if len(latest_release_ids) >= keep_count:
            break
        latest_release_ids.add(release["id"])

    for release in direct_releases:
        if release["id"] in latest_release_ids:
            print(f"Keeping release assets: {release.get('tag_name', release['id'])}")
            continue
        clean_release_assets(token, release)


def main():
    parser = argparse.ArgumentParser(description="Publish the latest TraceFence DMG to GitHub Releases.")
    parser.add_argument("--dmg", default=DMG_PATH)
    parser.add_argument("--clean-historical-assets", action="store_true")
    args = parser.parse_args()

    token = github_token()
    if not token:
        print("Missing GitHub token. Run `gh auth login` or set GITHUB_TOKEN.", file=sys.stderr)
        return 1
    if not os.path.exists(args.dmg):
        print(f"DMG not found: {args.dmg}", file=sys.stderr)
        return 1

    release = find_or_create_release(token)
    if not release.get("draft"):
        raise RuntimeError(f"Release {TAG} must remain a draft until every asset is verified")
    clean_release_assets(token, release)

    digest = sha256_file(args.dmg)
    sha_path = f"{args.dmg}.sha256"
    with open(sha_path, "w") as file:
        file.write(f"{digest}  {os.path.basename(args.dmg)}\n")

    upload_url = release["upload_url"]
    dmg_name = os.path.basename(args.dmg)
    checksum_name = os.path.basename(sha_path)
    manifest_path = f"{args.dmg}.json"
    manifest = {
        "version": VERSION,
        "releaseName": RELEASE_NAME,
        "notes": RELEASE_BODY,
        "downloadURL": f"https://github.com/{REPO}/releases/download/{TAG}/{dmg_name}",
        "checksumURL": f"https://github.com/{REPO}/releases/download/{TAG}/{checksum_name}",
        "fileName": dmg_name,
        "size": os.path.getsize(args.dmg),
        "sha256": digest,
    }
    with open(manifest_path, "w") as file:
        json.dump(manifest, file, ensure_ascii=False, indent=2)
        file.write("\n")

    print(f"Uploading {dmg_name}...")
    dmg_asset = upload_asset(upload_url, token, args.dmg, dmg_name, "application/octet-stream")
    print(f"Uploading {checksum_name}...")
    checksum_asset = upload_asset(upload_url, token, sha_path, checksum_name, "text/plain")
    print(f"Uploading {MANIFEST_NAME}...")
    manifest_asset = upload_asset(upload_url, token, manifest_path, MANIFEST_NAME, "application/json")

    verify_uploaded_asset(token, dmg_asset, args.dmg)
    verify_uploaded_asset(token, checksum_asset, sha_path)
    verify_uploaded_asset(token, manifest_asset, manifest_path, MANIFEST_NAME)
    release = publish_release(token, release)
    if args.clean_historical_assets:
        clean_historical_release_assets(token, release["id"])

    print(f"Published release: {release['html_url']}")
    print(f"SHA256: {digest}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
