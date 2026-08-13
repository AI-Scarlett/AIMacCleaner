#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
from pathlib import Path

ALLOWED_CATALOG_FILES = {
    Path("storefront-v1.json"),
    Path("storefront-v1.json.sig"),
    Path("README.md"),
}
BLOCKED_SUFFIXES = {
    ".swift", ".m", ".mm", ".h", ".hpp", ".c", ".cc", ".cpp", ".xcodeproj",
    ".xcworkspace", ".p8", ".pem", ".key", ".mobileprovision", ".entitlements",
}
SECRET_PATTERNS = [
    re.compile(rb"key_(?:live|test)_[A-Za-z0-9_\-]+"),
    re.compile(rb"BEGIN (?:OPENSSH |EC |RSA |)PRIVATE KEY"),
    re.compile(rb"gh[pousr]_[A-Za-z0-9]{20,}"),
]


def ensure_safe_destination(destination: Path) -> None:
    resolved = destination.resolve()
    if resolved == Path.home().resolve() or resolved == Path("/"):
        raise SystemExit("refusing unsafe export destination")
    if not (destination / ".git").exists():
        raise SystemExit("public destination must be an existing Git checkout")
    remote = subprocess.run(
        ["git", "-C", str(destination), "remote", "get-url", "origin"],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    ).stdout.strip()
    if "AI-Scarlett/TraceFence" not in remote:
        raise SystemExit(f"unexpected public repository remote: {remote}")


def scan_catalog_export(root: Path) -> None:
    for path in root.rglob("*"):
        if not path.is_file():
            continue
        relative = path.relative_to(root)
        if relative not in ALLOWED_CATALOG_FILES:
            raise SystemExit(f"public export contains a non-whitelisted file: {relative}")
        if any(part.startswith(".") for part in relative.parts):
            raise SystemExit(f"public export contains a hidden file: {relative}")
        if path.suffix.lower() in BLOCKED_SUFFIXES:
            raise SystemExit(f"public export contains blocked source/key material: {relative}")
        data = path.read_bytes()
        for pattern in SECRET_PATTERNS:
            if pattern.search(data):
                raise SystemExit(f"public export contains secret-like data: {relative}")


def main() -> int:
    parser = argparse.ArgumentParser(description="Export only signed TraceFence public catalog artifacts.")
    parser.add_argument("--catalog", type=Path, required=True)
    parser.add_argument("--signature", type=Path, required=True)
    parser.add_argument("--readme", type=Path, required=True)
    parser.add_argument("--destination", type=Path, required=True)
    args = parser.parse_args()

    ensure_safe_destination(args.destination)
    output = args.destination / "catalog"
    output.mkdir(parents=True, exist_ok=True)
    for source, name in [
        (args.catalog, "storefront-v1.json"),
        (args.signature, "storefront-v1.json.sig"),
        (args.readme, "README.md"),
    ]:
        if not source.is_file():
            raise SystemExit(f"missing public artifact: {source}")
        shutil.copyfile(source, output / name)
        os.chmod(output / name, 0o644)

    with subprocess.Popen(
        ["git", "-C", str(args.destination), "ls-files", "--others", "--cached", "--exclude-standard", "catalog"],
        text=True,
        stdout=subprocess.PIPE,
    ) as process:
        tracked = {Path(line.strip()) for line in process.stdout or [] if line.strip()}
        return_code = process.wait()
    if return_code != 0:
        raise SystemExit("could not enumerate the public catalog directory")
    allowed_repository_paths = {Path("catalog") / path for path in ALLOWED_CATALOG_FILES}
    unexpected = tracked - allowed_repository_paths
    if unexpected:
        raise SystemExit(f"public catalog directory contains non-whitelisted paths: {sorted(map(str, unexpected))}")

    scan_catalog_export(output)
    print("PUBLIC_EXPORT_OK files=3 source_files=0 secrets=0")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
