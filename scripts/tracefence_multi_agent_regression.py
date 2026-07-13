#!/usr/bin/env python3
import time
import uuid

from tracefence_remote_regression import all_sessions, request


def wait_until(fetch, predicate, timeout=45, interval=0.5):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = fetch()
        if predicate(last):
            return last
        time.sleep(interval)
    raise AssertionError(f"Timed out waiting for condition. Last value: {last!r}")


def session_by_id(session_id):
    return next((row for row in all_sessions(request("/v1/agents")) if row.get("id") == session_id), None)


def main():
    status = request("/v1/status")
    adapters = {
        row.get("id"): row
        for row in (status.get("agentCore") or {}).get("adapters", [])
    }
    assert len(adapters) >= 18, f"Expected the full adapter catalog, got {len(adapters)}"
    assert adapters["claude"].get("authenticated") is False
    assert adapters["qwen"].get("controlAvailable") is False
    assert "invalid or expired" in (adapters["qwen"].get("message") or "")

    agents = request("/v1/agents")
    sessions = all_sessions(agents)
    types = {row.get("agentType") for row in sessions}
    for expected in {"Codex", "Grok CLI", "Cursor Agent", "Trae", "CodeBuddy", "MiniMax Code"}:
        assert expected in types, f"Missing monitored agent type: {expected}"
    grok = next(
        row for row in sessions
        if row.get("agentType") == "Grok CLI" and row.get("controlAvailable") is True
    )
    session_id = grok["id"]

    marker = f"TRACEFENCE_GROK_E2E_{int(time.time())}"
    result = request(
        "/v1/sessions/resume",
        "POST",
        {
            "sessionId": session_id,
            "instruction": f"Do not use tools. Reply only: {marker}",
            "operationId": str(uuid.uuid4()),
        },
    )
    assert result.get("ok") is True, result

    def context():
        return request(
            "/v1/sessions/context",
            "POST",
            {"sessionId": session_id, "limit": "80"},
        )

    wait_until(
        context,
        lambda payload: any(marker in (message.get("text") or "") for message in payload.get("messages", [])),
        timeout=90,
        interval=1,
    )

    sleep_marker = f"TRACEFENCE_GROK_INTERRUPT_{int(time.time())}"
    request(
        "/v1/sessions/resume",
        "POST",
        {
            "sessionId": session_id,
            "instruction": f"Use the shell tool to run sleep 30, then reply only: {sleep_marker}",
            "operationId": str(uuid.uuid4()),
        },
    )

    def pending():
        rows = request("/v1/agents").get("pendingApprovals") or []
        return next(
            (
                row for row in rows
                if row.get("agentType") == "Grok CLI" and row.get("sessionId") == session_id
            ),
            None,
        )

    approval = wait_until(pending, lambda value: value is not None, timeout=60, interval=0.5)
    approved = request(
        "/v1/approvals/approve",
        "POST",
        {"approvalId": approval["id"], "operationId": str(uuid.uuid4())},
    )
    assert approved.get("ok") is True, approved
    time.sleep(2)
    interrupted = request(
        "/v1/sessions/interrupt",
        "POST",
        {"sessionId": session_id, "operationId": str(uuid.uuid4())},
    )
    assert interrupted.get("ok") is True, interrupted
    wait_until(
        lambda: session_by_id(session_id),
        lambda value: value is not None and value.get("phase") in {"interrupted", "idle", "done"},
        timeout=20,
        interval=0.5,
    )

    print("TRACEFENCE_MULTI_AGENT_REGRESSION_PASS")
    print(f"grok_session={session_id}")
    print(f"instruction_marker={marker}")
    print(f"approval_id={approval['id']}")
    print("qwen=disabled_invalid_token")
    print("claude=disabled_invalid_credentials")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
