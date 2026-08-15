#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import zipfile
from pathlib import Path


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1_048_576), b""):
            value.update(chunk)
    return value.hexdigest()


def is_metadata_path(name: str) -> bool:
    parts = Path(name).parts
    return name.startswith("__MACOSX/") or any(part.startswith("._") for part in parts)


def copy_entry(
    source: zipfile.ZipFile,
    destination: zipfile.ZipFile,
    info: zipfile.ZipInfo,
    data: bytes | None = None,
) -> None:
    copied = zipfile.ZipInfo(filename=info.filename, date_time=info.date_time)
    copied.compress_type = zipfile.ZIP_DEFLATED
    copied.comment = info.comment
    copied.extra = b""
    copied.create_system = info.create_system
    copied.create_version = info.create_version
    copied.extract_version = info.extract_version
    copied.flag_bits = info.flag_bits
    copied.internal_attr = info.internal_attr
    copied.external_attr = info.external_attr
    if info.is_dir():
        destination.writestr(copied, b"")
    else:
        destination.writestr(copied, source.read(info.filename) if data is None else data)


def repack(
    source_path: Path,
    destination_path: Path,
    plugin_id: str,
    version: str,
    license_bytes: bytes,
    upstream_commit: str,
) -> None:
    with zipfile.ZipFile(source_path) as source:
        entries = [info for info in source.infolist() if not is_metadata_path(info.filename)]
        roots = {Path(info.filename).parts[0] for info in entries if Path(info.filename).parts}
        expected_root = f"{plugin_id}.mactoolsplugin"
        if roots != {expected_root}:
            raise ValueError(f"unexpected package roots: {sorted(roots)}")
        if not any(info.filename == f"{expected_root}/plugin.json" for info in entries):
            raise ValueError("plugin manifest is missing")

        provenance = (
            "TraceFence mirrored plugin distribution\n"
            f"Plugin: {plugin_id} {version}\n"
            "Source: https://github.com/ggbond268/MacTools\n"
            f"Pinned source commit: {upstream_commit}\n"
            "Upstream license: Apache License 2.0 (see LICENSE in this package)\n"
            "Distribution changes: mirrored into the TraceFence-owned release pipeline, "
            "built as a universal macOS bundle, Developer ID signed, and packaged for PluginKit v4.\n"
            "Runtime downloads and updates are served from AI-Scarlett/TraceFence and do not depend "
            "on continued availability of the upstream repository.\n"
        ).encode("utf-8")

        destination_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(
            prefix=f".{plugin_id}.",
            suffix=".zip",
            dir=destination_path.parent,
            delete=False,
        ) as handle:
            temporary_path = Path(handle.name)
        try:
            with zipfile.ZipFile(
                temporary_path,
                "w",
                compression=zipfile.ZIP_DEFLATED,
                compresslevel=9,
                strict_timestamps=False,
            ) as destination:
                for info in entries:
                    if info.filename in {
                        f"{expected_root}/LICENSE",
                        f"{expected_root}/TRACEFENCE-PROVENANCE.txt",
                    }:
                        continue
                    if info.filename == f"{expected_root}/plugin.json":
                        manifest = json.loads(source.read(info.filename))
                        manifest.pop("build", None)
                        manifest.pop("buildProject", None)
                        copy_entry(
                            source,
                            destination,
                            info,
                            (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode("utf-8"),
                        )
                        continue
                    copy_entry(source, destination, info)
                destination.writestr(f"{expected_root}/LICENSE", license_bytes)
                destination.writestr(f"{expected_root}/TRACEFENCE-PROVENANCE.txt", provenance)
            os.replace(temporary_path, destination_path)
        finally:
            temporary_path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Repack mirrored plugins without AppleDouble files and with required license provenance."
    )
    parser.add_argument("--catalog-input", type=Path, required=True)
    parser.add_argument("--catalog-output", type=Path, required=True)
    parser.add_argument("--source-assets", type=Path, required=True)
    parser.add_argument("--output-assets", type=Path, required=True)
    parser.add_argument("--license", type=Path, required=True)
    parser.add_argument("--upstream-commit", required=True)
    args = parser.parse_args()

    catalog = json.loads(args.catalog_input.read_text(encoding="utf-8"))
    plugins = catalog.get("plugins")
    if not isinstance(plugins, list) or len(plugins) != 45:
        raise SystemExit(f"expected 45 mirrored plugins, found {len(plugins) if isinstance(plugins, list) else 0}")
    license_bytes = args.license.read_bytes()

    for plugin in plugins:
        plugin_id = str(plugin["id"])
        version = str(plugin["version"])
        source_path = args.source_assets / f"{plugin_id}.mactoolsplugin.zip"
        destination_path = args.output_assets / source_path.name
        repack(
            source_path,
            destination_path,
            plugin_id,
            version,
            license_bytes,
            args.upstream_commit,
        )
        plugin["package"]["sha256"] = digest(destination_path)
        plugin["package"]["size"] = destination_path.stat().st_size

    args.catalog_output.parent.mkdir(parents=True, exist_ok=True)
    args.catalog_output.write_text(json.dumps(catalog, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"PLUGIN_REPACK_OK plugins={len(plugins)} upstream={args.upstream_commit}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
