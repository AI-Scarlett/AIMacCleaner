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
VERSION = os.environ.get("TRACEFENCE_VERSION", "1.2.17")
TAG = f"v{VERSION}"
DMG_PATH = f"/tmp/{APP_NAME}-{TAG}-arm64.dmg"
RELEASE_NAME = f"{APP_NAME} {TAG}"
MANIFEST_NAME = "tracefence-update.json"
RELEASE_BODY = (
    f"TraceFence {VERSION} adds an active-Agent quota surface for Touch Bar MacBook Pro models.\n\n"
    "- Shows the current provider and two key remaining-quota windows on Touch Bar.\n"
    "- Follows foreground apps and active Codex, Claude, Grok, or DeepSeek Harness sessions.\n"
    "- Reuses the quota monitor plugin cache without extra credential reads or polling.\n"
    "- Keeps persistent Touch Bar integration isolated to the direct website build.\n"
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
    manifest_path = os.path.join(os.path.dirname(args.dmg), MANIFEST_NAME)
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
