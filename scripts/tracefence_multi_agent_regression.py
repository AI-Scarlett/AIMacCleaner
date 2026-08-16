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
    for expected in {"codex", "grok", "cursor", "trae", "codebuddy", "minimax"}:
        assert expected in adapters, f"Missing adapter from catalog: {expected}"
    assert "claude" in adapters
    assert "qwen" in adapters
    # Authentication and local CLI availability are properties of the review
    # machine, not fixed product invariants.  A disabled adapter must explain
    # why; an enabled adapter is a valid state and must not fail the suite.
    for adapter_id in ("claude", "qwen"):
        adapter = adapters[adapter_id]
        if adapter.get("controlAvailable") is not True:
            assert adapter.get("message") or adapter.get("reason"), adapter

    agents = request("/v1/agents")
    sessions = all_sessions(agents)
    # Installed tools are allowed to have no local history.  Presence belongs
    # to the adapter catalog assertion above; session checks cover only live
    # data that actually exists on this machine.
    grok = next((
        row for row in sessions
        if row.get("agentType") == "Grok CLI" and row.get("controlAvailable") is True
    ), None)
    if grok is None:
        print("TRACEFENCE_MULTI_AGENT_REGRESSION_PASS")
        print("grok_e2e=skipped_no_controllable_session")
        print(f"qwen_control={adapters['qwen'].get('controlAvailable') is True}")
        print(f"claude_control={adapters['claude'].get('controlAvailable') is True}")
        return 0
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
    print(f"qwen_control={adapters['qwen'].get('controlAvailable') is True}")
    print(f"claude_control={adapters['claude'].get('controlAvailable') is True}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
