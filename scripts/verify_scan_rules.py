#!/usr/bin/env python3
"""Fail the build when a cleanup rule targets broad user or app-data roots."""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "AIMacCleaner/ScanRules.swift"
RULE_PATTERN = re.compile(
    r'ScanRule\(id:\s*"([^"]+)".*?paths:\s*\[(.*?)\]\s*\)',
    re.DOTALL,
)
PATH_PATTERN = re.compile(r'"(~?/[^"\\]*(?:\\.[^"\\]*)*)"')


def is_broad(path: str) -> bool:
    normalized = path.rstrip("/")
    protected = {
        "~",
        "~/Desktop",
        "~/Documents",
        "~/Downloads",
        "~/Pictures",
        "~/Music",
        "~/Movies",
        "~/Library",
        "~/Library/Application Support",
        "~/Library/Containers",
        "~/Library/Group Containers",
        "~/Library/Developer/Xcode/DerivedData",
        "~/Library/Developer/Xcode/Archives",
        "~/Library/Unity",
        "~/.codex/sessions",
        "~/.codex/archived_sessions",
        "~/.claude/projects",
        "~/.grok/sessions",
        "~/.grok/projects",
        "~/.gemini/tmp",
        "~/.gemini/history",
        "~/.cursor/projects",
        "~/Library/Application Support/Cursor/User/workspaceStorage",
        "~/Library/Application Support/Trae/User/workspaceStorage",
        "~/Library/Application Support/CodeBuddy CN/User/workspaceStorage",
    }
    if normalized in protected:
        return True
    protected_trees = (
        "~/.codex/sessions",
        "~/.codex/archived_sessions",
        "~/.claude/projects",
        "~/.grok/sessions",
        "~/.grok/projects",
        "~/.gemini/tmp",
        "~/.gemini/history",
        "~/.cursor/projects",
        "~/Library/Application Support/Cursor/User/workspaceStorage",
        "~/Library/Application Support/Trae/User/workspaceStorage",
        "~/Library/Application Support/CodeBuddy CN/User/workspaceStorage",
    )
    if any(normalized.startswith(root + "/") for root in protected_trees):
        return True
    if normalized == "~/Library/Containers/com.docker.docker/Data/vms" or normalized.startswith(
        "~/Library/Containers/com.docker.docker/Data/vms/"
    ):
        return True

    prefixes = (
        "~/Library/Application Support/",
        "~/Library/Containers/",
        "~/Library/Group Containers/",
    )
    for prefix in prefixes:
        if not normalized.startswith(prefix):
            continue
        components = normalized[len(prefix):].split("/")
        if len(components) <= 1:
            return True
        if prefix.endswith("/Containers/") and components[1:] in (["Data"], ["Data", "Library"]):
            return True
        if prefix.endswith("/Group Containers/") and components[1:] == ["Library"]:
            return True
    return False


def main() -> int:
    text = SOURCE.read_text(encoding="utf-8")
    seen: set[str] = set()
    failures: list[str] = []
    rules = RULE_PATTERN.findall(text)
    if not rules:
        failures.append("no ScanRule definitions parsed")

    for rule_id, path_block in rules:
        if rule_id in seen:
            failures.append(f"duplicate rule id: {rule_id}")
        seen.add(rule_id)
        for raw_path in PATH_PATTERN.findall(path_block):
            path = bytes(raw_path, "utf-8").decode("unicode_escape") if "\\" in raw_path else raw_path
            if is_broad(path):
                failures.append(f"broad cleanup target in {rule_id}: {path}")

    if failures:
        for failure in failures:
            print(f"verify_scan_rules: {failure}", file=sys.stderr)
        return 1
    print(f"verify_scan_rules: PASS ({len(rules)} unique rules)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
