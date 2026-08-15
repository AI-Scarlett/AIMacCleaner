#!/usr/bin/env python3
import json
import os
import subprocess
from pathlib import Path
from typing import Optional


ROOT = Path(__file__).resolve().parents[1]
ADAPTER = Path(
    os.environ.get(
        "TRACEFENCE_UNIVERSAL_ADAPTER",
        ROOT / "TraceFenceAgentCore/.build/debug/TraceFenceUniversalAdapter",
    )
)


def invoke(method: str, params: Optional[dict] = None) -> dict:
    request = json.dumps({"method": method, "params": params or {}}) + "\n"
    completed = subprocess.run(
        [str(ADAPTER), "--adapter", "deepseek-harness"],
        input=request,
        text=True,
        capture_output=True,
        check=False,
        timeout=20,
    )
    assert completed.returncode in {0, 1}, completed.stderr
    return json.loads(completed.stdout)


def expected_session_ids() -> set[str]:
    catalog = Path.home() / ".dsh/storages/workspace.json"
    if not catalog.exists():
        return set()
    payload = json.loads(catalog.read_text(encoding="utf-8"))
    workspaces = ((payload.get("tables") or {}).get("workspaces") or {}).values()
    return {
        session_id
        for workspace in workspaces
        for session_id in workspace.get("sessionIds") or []
    }


def main() -> int:
    assert ADAPTER.is_file(), f"Adapter binary not found: {ADAPTER}"
    health = invoke("health")
    assert health.get("ok") is True, health
    details = health.get("result") or {}
    assert details.get("adapterId") == "deepseek-harness", details
    assert details.get("displayName") == "DeepSeek Harness", details

    sessions_response = invoke("listSessions")
    assert sessions_response.get("ok") is True, sessions_response
    sessions = (sessions_response.get("result") or {}).get("sessions") or []
    expected = expected_session_ids()
    actual = {row.get("id") for row in sessions}
    assert expected <= actual, {"missing": sorted(expected - actual)}
    for row in sessions:
        assert row.get("agentType") == "DeepSeek Harness", row
        assert row.get("project"), row
        assert row.get("contextAvailable") is False, row
        assert row.get("controlReason") in {
            "new_headless_task_adapter",
            "agent_runtime_not_installed",
        }, row
        assert set((row.get("tokens") or {}).keys()) == {
            "input",
            "output",
            "cacheRead",
            "cacheCreate",
        }, row

    rejected = invoke("control", {"action": "instruction", "sessionId": next(iter(actual), "missing")})
    assert rejected.get("ok") is False, rejected
    assert rejected.get("error") == "instruction_required", rejected

    print("TRACEFENCE_DEEPSEEK_HARNESS_REGRESSION_PASS")
    print(f"sessions={len(sessions)}")
    print(f"controlAvailable={details.get('controlAvailable') is True}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
