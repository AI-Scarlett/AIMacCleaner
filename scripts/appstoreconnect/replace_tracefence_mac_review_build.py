#!/usr/bin/env python3
"""Safely replace the active TraceFence macOS review submission.

The default mode is read-only. Mutating App Store Connect requires both
``--execute`` and the exact ``--confirm`` value printed by the dry run.
"""

from __future__ import annotations

import argparse
import os
import sys
import time
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from scripts.appstoreconnect.sync_tracefence_sentinel_submission import ASC, KEY_ID, body, rel
from scripts.appstoreconnect import sync_tracefence_mac_submission as mac_sync


APP_ID = "6772386897"
VERSION = "3.1.8"
BUILD = os.environ.get("TRACEFENCE_MAC_BUILD", "75")
EXPECTED_CURRENT_BUILD = os.environ.get("TRACEFENCE_MAC_OLD_BUILD", "73")
PLATFORM = "MAC_OS"
CONFIRMATION = f"REPLACE_MAC_{VERSION}_BUILD_{EXPECTED_CURRENT_BUILD}_WITH_{BUILD}"
ACTIVE_STATES = {
    "READY_FOR_REVIEW",
    "WAITING_FOR_REVIEW",
    "IN_REVIEW",
    "UNRESOLVED_ISSUES",
}


def version_resource(api: ASC) -> dict[str, Any]:
    versions = api.json(
        "GET",
        f"/apps/{APP_ID}/appStoreVersions",
        params={"filter[platform]": PLATFORM, "limit": 50},
    )["data"]
    version = next(
        (item for item in versions if item["attributes"].get("versionString") == VERSION),
        None,
    )
    if version is None:
        raise RuntimeError(f"Missing macOS version {VERSION}")
    return version


def build_resource(api: ASC) -> dict[str, Any]:
    builds = api.json(
        "GET",
        "/builds",
        params={"filter[app]": APP_ID, "filter[version]": BUILD, "limit": 20},
    )["data"]
    build = next(
        (item for item in builds if item["attributes"].get("processingState") == "VALID"),
        None,
    )
    if build is None:
        state = builds[0]["attributes"].get("processingState") if builds else "missing"
        raise RuntimeError(f"Build {BUILD} is not VALID: {state}")
    return build


def active_submissions(api: ASC) -> list[dict[str, Any]]:
    submissions = api.json(
        "GET",
        "/reviewSubmissions",
        params={"filter[app]": APP_ID, "filter[platform]": PLATFORM, "limit": 50},
    )["data"]
    return [
        item
        for item in submissions
        if item["attributes"].get("state") in ACTIVE_STATES
    ]


def cancel_active_submission(api: ASC, submission: dict[str, Any]) -> None:
    state = submission["attributes"].get("state")
    if state == "IN_REVIEW":
        raise RuntimeError(
            f"Refusing to cancel review {submission['id']} while it is IN_REVIEW"
        )
    if state not in {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "UNRESOLVED_ISSUES"}:
        raise RuntimeError(
            f"Refusing to cancel review {submission['id']} in unexpected state {state}"
        )
    result = api.json(
        "PATCH",
        f"/reviewSubmissions/{submission['id']}",
        json=body("reviewSubmissions", submission["id"], {"canceled": True}),
    )["data"]
    print(
        f"Canceled review {result['id']}: {result['attributes'].get('state')}",
        flush=True,
    )


def linked_build_id(api: ASC, version_id: str) -> str | None:
    linked = api.json("GET", f"/appStoreVersions/{version_id}/build").get("data")
    return linked and linked.get("id")


def build_number(api: ASC, build_id: str | None) -> str | None:
    if not build_id:
        return None
    return api.json("GET", f"/builds/{build_id}")["data"]["attributes"].get("version")


def bind_build(api: ASC, version_id: str, build_id: str) -> None:
    deadline = time.time() + 600
    while True:
        try:
            api.json(
                "PATCH",
                f"/appStoreVersions/{version_id}",
                json=body(
                    "appStoreVersions",
                    version_id,
                    relationships={"build": rel("builds", build_id)},
                ),
            )
            print(f"Bound macOS {VERSION} to build {BUILD}", flush=True)
            return
        except RuntimeError as error:
            if "RELATIONSHIP.INVALID.INVALID_STATE" not in str(error) or time.time() >= deadline:
                raise
            print("Waiting for canceled submission to release the version…", flush=True)
            time.sleep(15)


def item_version_id(api: ASC, item_id: str) -> str | None:
    linked = api.json("GET", f"/reviewSubmissionItems/{item_id}/appStoreVersion").get("data")
    return linked and linked.get("id")


def create_or_resume_submission(
    api: ASC,
    version_id: str,
    submissions: list[dict[str, Any]],
) -> str:
    ready = [item for item in submissions if item["attributes"].get("state") == "READY_FOR_REVIEW"]
    if len(ready) > 1:
        raise RuntimeError("More than one READY_FOR_REVIEW Mac submission exists")
    if ready:
        submission = ready[0]
        print(f"Resuming review submission {submission['id']}", flush=True)
    else:
        submission = api.json(
            "POST",
            "/reviewSubmissions",
            ok=(201,),
            json=body(
                "reviewSubmissions",
                attributes={"platform": PLATFORM},
                relationships={"app": rel("apps", APP_ID)},
            ),
        )["data"]
        print(f"Created review submission {submission['id']}", flush=True)

    items = api.json(
        "GET",
        f"/reviewSubmissions/{submission['id']}/items",
        params={"limit": 100},
    )["data"]
    linked_versions = {item_version_id(api, item["id"]) for item in items}
    if version_id not in linked_versions:
        api.json(
            "POST",
            "/reviewSubmissionItems",
            ok=(201,),
            json=body(
                "reviewSubmissionItems",
                relationships={
                    "reviewSubmission": rel("reviewSubmissions", submission["id"]),
                    "appStoreVersion": rel("appStoreVersions", version_id),
                },
            ),
        )
    submitted = api.json(
        "PATCH",
        f"/reviewSubmissions/{submission['id']}",
        json=body("reviewSubmissions", submission["id"], {"submitted": True}),
    )["data"]
    state = submitted["attributes"].get("state")
    print(f"Submitted review {submitted['id']}: {state}", flush=True)
    return submitted["id"]


def sync_review_material(api: ASC, version_id: str, build_id: str) -> None:
    localization_id = mac_sync.sync_localization(api, version_id)
    review_id = mac_sync.sync_version(api, version_id, build_id)
    mac_sync.sync_screenshots(api, localization_id)
    mac_sync.sync_review_attachment(api, review_id)


def verify(api: ASC, version_id: str, submission_id: str, build_id: str) -> None:
    linked_build = api.json("GET", f"/appStoreVersions/{version_id}/build").get("data")
    if not linked_build or linked_build.get("id") != build_id:
        raise RuntimeError("App Store version is not linked to the requested build")
    submission = api.json("GET", f"/reviewSubmissions/{submission_id}")["data"]
    state = submission["attributes"].get("state")
    if state not in {"WAITING_FOR_REVIEW", "IN_REVIEW"}:
        raise RuntimeError(f"Unexpected submitted review state: {state}")
    print(
        f"REVIEW_REPLACEMENT_OK version={VERSION} build={BUILD} "
        f"submission={submission_id} state={state}",
        flush=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="perform App Store Connect writes")
    parser.add_argument("--confirm", default="", help="exact confirmation string printed by dry run")
    args = parser.parse_args()

    if args.execute and args.confirm != CONFIRMATION:
        raise RuntimeError(f"Execution requires --confirm {CONFIRMATION}")

    demo_video_url = os.environ.get("TRACEFENCE_PAIRING_DEMO_VIDEO_URL", "").strip()
    attachment_value = os.environ.get("TRACEFENCE_REVIEW_ATTACHMENT", "").strip()
    if args.execute and not demo_video_url.startswith("https://"):
        raise RuntimeError(
            "Set TRACEFENCE_PAIRING_DEMO_VIDEO_URL to the public or unlisted HTTPS "
            "physical-device pairing demo before replacing the review submission"
        )
    if args.execute and not attachment_value:
        raise RuntimeError(
            "Set TRACEFENCE_REVIEW_ATTACHMENT to the physical Mac + iPhone pairing "
            "demo video before replacing the review submission"
        )
    if args.execute and not Path(attachment_value).is_file():
        raise RuntimeError(f"Missing physical-device pairing video: {attachment_value}")
    key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
    if not key_path.exists():
        raise RuntimeError(f"Missing API key: {key_path}")
    api = ASC(key_path)
    version = version_resource(api)
    build = build_resource(api)
    current_build_id = linked_build_id(api, version["id"])
    current_build_number = build_number(api, current_build_id)
    submissions = active_submissions(api)
    states = [(item["id"], item["attributes"].get("state")) for item in submissions]

    print(
        f"PREFLIGHT version={VERSION} state={version['attributes'].get('appStoreState')} "
        f"currentBuild={current_build_number} targetBuild={BUILD} "
        f"targetState={build['attributes'].get('processingState')}",
        flush=True,
    )
    print(f"PREFLIGHT activeReviews={states}", flush=True)

    if current_build_number not in {EXPECTED_CURRENT_BUILD, BUILD, None}:
        raise RuntimeError(
            f"Refusing replacement: version currently uses unexpected build {current_build_number}"
        )
    if len(submissions) > 1:
        raise RuntimeError(f"Refusing replacement with multiple active submissions: {states}")

    if not args.execute:
        print("DRY_RUN no App Store Connect writes were performed", flush=True)
        print(f"To execute: --execute --confirm {CONFIRMATION}", flush=True)
        return 0

    if current_build_number == EXPECTED_CURRENT_BUILD and submissions:
        cancel_active_submission(api, submissions[0])
        submissions = []
    elif current_build_number == BUILD:
        states_for_target = {
            item["attributes"].get("state") for item in submissions
        }
        if "IN_REVIEW" in states_for_target:
            raise RuntimeError("Target build is already IN_REVIEW; refusing to mutate review material")
        unsupported = states_for_target - {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW"}
        if unsupported:
            raise RuntimeError(
                f"Target build has a non-resumable active review state: {sorted(unsupported)}"
            )

    if current_build_number != BUILD:
        bind_build(api, version["id"], build["id"])
    sync_review_material(api, version["id"], build["id"])

    submissions = active_submissions(api)
    already_submitted = next(
        (
            item
            for item in submissions
            if item["attributes"].get("state") in {"WAITING_FOR_REVIEW", "IN_REVIEW"}
        ),
        None,
    )
    if already_submitted:
        submission_id = already_submitted["id"]
        print(f"Mac review is already submitted: {submission_id}", flush=True)
    else:
        submission_id = create_or_resume_submission(api, version["id"], submissions)
    verify(api, version["id"], submission_id, build["id"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
