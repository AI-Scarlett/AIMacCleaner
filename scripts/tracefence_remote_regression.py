#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import time
from collections import Counter
from typing import Optional
import urllib.error
import urllib.request


BASE_URL = os.environ.get("TRACEFENCE_REMOTE_BASE", "http://127.0.0.1:17895").rstrip("/")
PREFERRED_THREAD_ID = os.environ.get(
    "TRACEFENCE_CODEX_THREAD_ID",
    "019f49c9-4e92-7ff2-94cc-25daf8e99473",
)


def defaults_read(key: str) -> str:
    return subprocess.check_output(
        ["defaults", "read", "com.tracefence.app", key],
        text=True,
        stderr=subprocess.DEVNULL,
    ).strip()


def request(path: str, method: str = "GET", body: Optional[dict] = None) -> dict:
    token = os.environ.get("TRACEFENCE_REMOTE_TOKEN") or defaults_read("traceFenceIOSRemoteGatewayToken")
    payload = None
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    if body is not None:
        payload = json.dumps(body).encode("utf-8")
        headers["Content-Type"] = "application/json"
    req = urllib.request.Request(BASE_URL + path, data=payload, headers=headers, method=method)
    timeout = 60 if method != "GET" else 40
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return json.load(response)
    except urllib.error.HTTPError as exc:
        detail = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"{method} {path} failed: HTTP {exc.code} {detail}") from exc


def all_sessions(payload: dict) -> list[dict]:
    return list(payload.get("allSessions") or payload.get("sessions") or [])


def select_codex_session(payload: dict) -> dict:
    sessions = [
        item for item in all_sessions(payload)
        if item.get("agentType") == "Codex"
        and item.get("controlMode") in {"codex_native", "tracefence_agent_core"}
        and item.get("canResume") is True
    ]
    preferred_ids = {
        f"codex|{PREFERRED_THREAD_ID}",
        f"core|codex|{PREFERRED_THREAD_ID}",
    }
    for session in sessions:
        if session.get("id") in preferred_ids:
            return session
    for session in sessions:
        if session.get("phase") in {"idle", "interrupted"}:
            return session
    raise AssertionError("No controllable Codex session found in /v1/agents.")


def find_session(session_id: str) -> Optional[dict]:
    for session in all_sessions(request("/v1/agents")):
        if session.get("id") == session_id:
            return session
    return None


def wait_for_response(session_id: str, marker: str, timeout: int = 75) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        session = find_session(session_id)
        if session and marker in (session.get("lastResponse") or ""):
            return session
        time.sleep(2)
    raise AssertionError(f"Codex session did not return marker {marker!r}.")


def send_instruction(session_id: str, instruction: str) -> dict:
    result = request(
        "/v1/sessions/resume",
        "POST",
        {"sessionId": session_id, "instruction": instruction},
    )
    if not result.get("ok"):
        raise AssertionError(f"Instruction failed: {result.get('message')}")
    return result


def wait_for_approval(session_id: str, timeout: int = 75) -> dict:
    deadline = time.time() + timeout
    while time.time() < deadline:
        approvals = request("/v1/agents").get("pendingApprovals") or []
        for approval in approvals:
            if approval.get("sessionId") == session_id:
                return approval
        time.sleep(1)
    raise AssertionError(f"Codex session {session_id!r} did not request approval.")


def wait_for_approval_clear(session_id: str, timeout: int = 30) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        approvals = request("/v1/agents").get("pendingApprovals") or []
        if not any(item.get("sessionId") == session_id for item in approvals):
            return
        time.sleep(1)
    raise AssertionError(f"Resolved approval remained visible for {session_id!r}.")


def main() -> int:
    status = request("/v1/status")
    if not status.get("ok"):
        raise AssertionError("/v1/status did not return ok=true.")

    agents = request("/v1/agents")
    if os.environ.get("TRACEFENCE_APPROVAL_AUDIT") == "1":
        approvals = agents.get("pendingApprovals") or []
        print(json.dumps({
            "pendingCount": len(approvals),
            "approvals": [
                {
                    "id": item.get("id"),
                    "sessionId": item.get("sessionId"),
                    "agentType": item.get("agentType"),
                    "kind": item.get("kind"),
                    "title": item.get("title"),
                    "createdAt": item.get("createdAt"),
                    "expiresAt": item.get("expiresAt"),
                }
                for item in approvals
            ],
        }, ensure_ascii=False, indent=2))
        return 0

    if os.environ.get("TRACEFENCE_CONTEXT_TURN_AUDIT") == "1":
        catalog = request("/v1/sessions?limit=120")
        candidates = [
            item for item in catalog.get("sessions", [])
            if item.get("contextAvailable") is True
        ]
        if not candidates:
            raise AssertionError("No session with readable context was found.")

        selected = candidates[0]
        context = request(
            "/v1/sessions/context",
            "POST",
            {"sessionId": selected["id"], "limit": 120, "turnLimit": 3},
        )
        messages = context.get("messages") or []
        if not messages:
            raise AssertionError("Selected session returned no context messages.")
        if any(not item.get("turnId") for item in messages):
            raise AssertionError("Core returned a context record without turnId.")

        contiguous_turns = []
        for item in messages:
            turn_id = item["turnId"]
            if not contiguous_turns or contiguous_turns[-1] != turn_id:
                contiguous_turns.append(turn_id)
        if len(contiguous_turns) > 3:
            raise AssertionError(f"Expected at most three turns, got {len(contiguous_turns)}.")

        print(json.dumps({
            "coreVersion": (status.get("agentCore") or {}).get("coreVersion"),
            "sessionId": selected["id"],
            "messageCount": len(messages),
            "turnCount": len(contiguous_turns),
            "hasMore": context.get("hasMore"),
            "nextCursor": context.get("nextCursor"),
        }, ensure_ascii=False, indent=2))
        print("TRACEFENCE_CONTEXT_TURN_AUDIT_PASS")
        return 0

    if os.environ.get("TRACEFENCE_REMOTE_ADAPTER_AUDIT") == "1":
        core = status.get("agentCore") or status.get("core") or {}
        adapter_rows = core.get("adapters") or []
        sessions = all_sessions(agents)
        counts = Counter(str(item.get("agentType") or "Unknown") for item in sessions)
        controllable = Counter(
            str(item.get("agentType") or "Unknown")
            for item in sessions
            if item.get("controlAvailable") is True or item.get("canResume") is True
        )
        summary = {
            "coreVersion": core.get("coreVersion") or status.get("coreVersion"),
            "adapterCount": len(adapter_rows),
            "adapters": [
                {
                    "id": row.get("id"),
                    "displayName": row.get("displayName"),
                    "operational": row.get("operational"),
                    "authenticated": row.get("authenticated"),
                    "integrationTier": row.get("integrationTier"),
                    "controlAvailable": row.get("controlAvailable"),
                    "approvalAvailable": row.get("approvalAvailable"),
                    "message": row.get("message"),
                }
                for row in adapter_rows
            ],
            "sessionCounts": dict(sorted(counts.items())),
            "controllableCounts": dict(sorted(controllable.items())),
            "totalSessions": len(sessions),
        }
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        return 0

    if os.environ.get("TRACEFENCE_REMOTE_INVENTORY") == "1":
        inventory = {
            "controlPlane": agents.get("controlPlane", {}),
            "launchTargets": agents.get("launchTargets", []),
            "sessions": [
                {
                    "id": session.get("id"),
                    "title": session.get("title"),
                    "phase": session.get("phase"),
                    "cwd": session.get("cwd"),
                    "agentType": session.get("agentType"),
                    "controlMode": session.get("controlMode"),
                    "canResume": session.get("canResume"),
                    "canInterrupt": session.get("canInterrupt"),
                    "canTerminate": session.get("canTerminate"),
                }
                for session in all_sessions(agents)
                if session.get("controlAvailable") is True or session.get("canRelaunch") is True
            ],
        }
        print(json.dumps(inventory, ensure_ascii=False, indent=2))
        return 0

    control_plane = agents.get("controlPlane", {})
    has_legacy_control = control_plane.get("codexNative") is True
    has_core_control = (
        control_plane.get("available") is True
        and control_plane.get("truthModel") == "agent_core_adapter"
    )
    if not has_legacy_control and not has_core_control:
        raise AssertionError("Mac API does not expose Codex control.")
    session = select_codex_session(agents)
    session_id = session["id"]
    print("selected", session_id, session.get("title"))

    if os.environ.get("TRACEFENCE_CODEX_APPROVAL_LIFECYCLE") == "1":
        stamp = int(time.time())
        marker = f"TRACEFENCE_CODEX_APPROVAL_{stamp}"
        probe_path = f"/Users/zhouxiaoming/Downloads/.tracefence-approval-{stamp}"
        send_instruction(
            session_id,
            "TraceFence approval lifecycle regression. Use the shell tool once to run exactly "
            f"`touch {probe_path} && rm {probe_path}`. Wait for approval and execution. "
            f"After the command succeeds, reply only: {marker}",
        )
        approval = wait_for_approval(session_id)
        approved = request(
            "/v1/approvals/approve",
            "POST",
            {
                "approvalId": approval["id"],
                "operationId": f"approval-regression-{stamp}",
            },
        )
        if not approved.get("ok"):
            raise AssertionError(f"Approval failed: {approved.get('message')}")
        wait_for_response(session_id, marker, timeout=120)
        wait_for_approval_clear(session_id)
        if os.path.exists(probe_path):
            raise AssertionError(f"Approval probe file was not removed: {probe_path}")
        print(json.dumps({
            "sessionId": session_id,
            "approvalId": approval["id"],
            "approvalSource": approval.get("sourceLabel"),
            "marker": marker,
            "cleared": True,
        }, ensure_ascii=False, indent=2))
        print("TRACEFENCE_CODEX_APPROVAL_LIFECYCLE_PASS")
        return 0

    start_marker = f"TRACEFENCE_CODEX_START_{int(time.time())}"
    start = send_instruction(
        session_id,
        f"TraceFence regression. Do not call tools. Reply only: {start_marker}",
    )
    if start.get("command") not in {"codex_start", "codex_desktop_start"}:
        raise AssertionError(f"Expected a real Codex start, got {start.get('command')!r}.")
    wait_for_response(session_id, start_marker)
    print("start ok", start_marker)

    send_instruction(
        session_id,
        "TraceFence interrupt regression. Run sleep 20, then reply SLEEP_FINISHED.",
    )
    time.sleep(4)
    interrupted = request("/v1/sessions/interrupt", "POST", {"sessionId": session_id})
    if not interrupted.get("ok") or interrupted.get("command") != "codex_interrupt":
        raise AssertionError(f"Interrupt failed: {interrupted.get('message')}")
    print("interrupt ok")

    steer_marker = f"TRACEFENCE_CODEX_STEER_{int(time.time())}"
    send_instruction(
        session_id,
        "TraceFence steering regression. Run sleep 12, then reply ORIGINAL_RESPONSE.",
    )
    time.sleep(3)
    steered = send_instruction(
        session_id,
        f"Replace the previous response. After the wait, reply only: {steer_marker}",
    )
    if steered.get("command") not in {"codex_steer", "codex_desktop_steer"}:
        raise AssertionError(f"Expected a real Codex steer, got {steered.get('command')!r}.")
    wait_for_response(session_id, steer_marker)
    print("steer ok", steer_marker)

    print("TRACEFENCE_REMOTE_REGRESSION_PASS")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"TRACEFENCE_REMOTE_REGRESSION_FAIL: {exc}", file=sys.stderr)
        raise
