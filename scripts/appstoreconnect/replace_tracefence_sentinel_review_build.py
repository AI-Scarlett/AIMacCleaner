#!/usr/bin/env python3
"""Safely move TraceFence Sentinel build 24 into TestFlight and App Review.

The default mode is read-only. Mutating App Store Connect requires both
``--execute`` and an exact ``--confirm`` value printed by the dry run.
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

from scripts.appstoreconnect.sync_tracefence_sentinel_submission import (  # noqa: E402
    ASC,
    KEY_ID,
    REVIEW_NOTES,
    body,
    rel,
)


APP_ID = "6789015094"
VERSION = "1.0.0"
PLATFORM = "IOS"
BUILD = os.environ.get("TRACEFENCE_SENTINEL_BUILD", "24")
EXPECTED_CURRENT_BUILD = os.environ.get("TRACEFENCE_SENTINEL_OLD_BUILD", "23")
BETA_GROUP_ID = os.environ.get(
    "TRACEFENCE_SENTINEL_PUBLIC_BETA_GROUP",
    "a4e065ba-de28-40e9-957f-f7ae01e9cff2",
)
CONFIRMATION = f"REPLACE_IOS_{VERSION}_BUILD_{EXPECTED_CURRENT_BUILD}_WITH_{BUILD}"

ACTIVE_REVIEW_STATES = {
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
        raise RuntimeError(f"Missing iOS version {VERSION}")
    return version


def build_resource(api: ASC, build_number: str) -> dict[str, Any] | None:
    builds = api.json(
        "GET",
        "/builds",
        params={"filter[app]": APP_ID, "filter[version]": build_number, "limit": 20},
    )["data"]
    valid = [item for item in builds if item["attributes"].get("processingState") == "VALID"]
    if not valid:
        return None
    if len(valid) != 1:
        raise RuntimeError(f"Expected one VALID build {build_number}, found {len(valid)}")
    build = valid[0]
    if build["attributes"].get("expired"):
        raise RuntimeError(f"Build {build_number} is expired")
    return build


def wait_for_build(api: ASC, build_number: str, timeout: int) -> dict[str, Any]:
    deadline = time.time() + timeout
    while True:
        build = build_resource(api, build_number)
        if build is not None:
            return build
        if time.time() >= deadline:
            raise RuntimeError(f"Build {build_number} is missing or not VALID")
        print(f"Waiting for iOS build {build_number} to become VALID...", flush=True)
        time.sleep(30)


def validate_target_build(api: ASC, build: dict[str, Any]) -> None:
    attrs = build["attributes"]
    if attrs.get("buildAudienceType") != "APP_STORE_ELIGIBLE":
        raise RuntimeError(
            f"Build {BUILD} is not App Store eligible: {attrs.get('buildAudienceType')}"
        )
    if attrs.get("usesNonExemptEncryption") is not False:
        raise RuntimeError(
            f"Build {BUILD} export-compliance state is not the expected false value"
        )
    prerelease = api.json("GET", f"/builds/{build['id']}/preReleaseVersion").get("data")
    if not prerelease:
        raise RuntimeError(f"Build {BUILD} is missing its prerelease version")
    prerelease_attrs = prerelease["attributes"]
    if (
        prerelease_attrs.get("version") != VERSION
        or prerelease_attrs.get("platform") != PLATFORM
    ):
        raise RuntimeError(
            f"Build {BUILD} belongs to unexpected prerelease version "
            f"{prerelease_attrs.get('version')} / {prerelease_attrs.get('platform')}"
        )


def build_number(api: ASC, build_id: str | None) -> str | None:
    if not build_id:
        return None
    return api.json("GET", f"/builds/{build_id}")["data"]["attributes"].get("version")


def beta_group_preflight(api: ASC, build_id: str) -> tuple[dict[str, Any], bool]:
    group = api.json("GET", f"/betaGroups/{BETA_GROUP_ID}")["data"]
    group_app = api.json("GET", f"/betaGroups/{BETA_GROUP_ID}/app")["data"]
    if group_app["id"] != APP_ID:
        raise RuntimeError(
            f"Beta group {BETA_GROUP_ID} belongs to app {group_app['id']}, not {APP_ID}"
        )
    attrs = group["attributes"]
    if attrs.get("isInternalGroup") is not False:
        raise RuntimeError(f"Beta group {BETA_GROUP_ID} is not an external group")
    if attrs.get("publicLinkEnabled") is not True:
        raise RuntimeError(f"Beta group {BETA_GROUP_ID} does not have a public link enabled")
    linkages = api.json(
        "GET",
        f"/betaGroups/{BETA_GROUP_ID}/relationships/builds",
        params={"limit": 200},
    )["data"]
    return group, any(item["id"] == build_id for item in linkages)


def validate_beta_localization(api: ASC) -> None:
    localizations = api.json(
        "GET",
        f"/apps/{APP_ID}/betaAppLocalizations",
        params={"limit": 100},
    )["data"]
    if not any((item["attributes"].get("description") or "").strip() for item in localizations):
        raise RuntimeError(
            "External TestFlight review requires a nonempty beta app localization description"
        )


def beta_state(api: ASC, build_id: str) -> str:
    detail = api.json("GET", f"/builds/{build_id}/buildBetaDetail").get("data")
    if not detail:
        raise RuntimeError("Target build is missing buildBetaDetail")
    return detail["attributes"].get("externalBuildState") or "UNKNOWN"


def add_to_beta_group(api: ASC, build_id: str) -> None:
    api.json(
        "POST",
        f"/betaGroups/{BETA_GROUP_ID}/relationships/builds",
        ok=(204,),
        json={"data": [{"type": "builds", "id": build_id}]},
    )
    deadline = time.time() + 90
    while True:
        _, present = beta_group_preflight(api, build_id)
        if present:
            print(f"Added build {BUILD} to public TestFlight group {BETA_GROUP_ID}", flush=True)
            return
        if time.time() >= deadline:
            raise RuntimeError("TestFlight group membership did not become visible")
        time.sleep(5)


def submit_beta_review_if_needed(api: ASC, build_id: str) -> str:
    state = beta_state(api, build_id)
    if state == "READY_FOR_BETA_SUBMISSION":
        validate_beta_localization(api)
        submission = api.json(
            "POST",
            "/betaAppReviewSubmissions",
            ok=(201,),
            json=body(
                "betaAppReviewSubmissions",
                relationships={"build": rel("builds", build_id)},
            ),
        )["data"]
        state = submission["attributes"].get("betaReviewState") or beta_state(api, build_id)
        print(f"Submitted build {BUILD} for external TestFlight review: {state}", flush=True)
    else:
        print(f"External TestFlight state for build {BUILD}: {state}", flush=True)
    if state in {"BETA_REVIEW_REJECTED", "REJECTED", "PROCESSING_EXCEPTION"}:
        raise RuntimeError(f"External TestFlight cannot proceed from state {state}")
    return state


def active_submissions(api: ASC) -> list[dict[str, Any]]:
    submissions = api.json(
        "GET",
        "/reviewSubmissions",
        params={"filter[app]": APP_ID, "filter[platform]": PLATFORM, "limit": 50},
    )["data"]
    return [
        item
        for item in submissions
        if item["attributes"].get("state") in ACTIVE_REVIEW_STATES
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
        f"Canceled old iOS review {result['id']}: {result['attributes'].get('state')}",
        flush=True,
    )


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
            print(f"Bound iOS {VERSION} to build {BUILD}", flush=True)
            return
        except RuntimeError as error:
            if "RELATIONSHIP.INVALID.INVALID_STATE" not in str(error) or time.time() >= deadline:
                raise
            print("Waiting for the canceled submission to release the iOS version...", flush=True)
            time.sleep(15)


def sync_review_notes(api: ASC, version_id: str) -> None:
    review = api.json("GET", f"/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    if not review:
        raise RuntimeError("Missing iOS App Store review details")
    api.json(
        "PATCH",
        f"/appStoreReviewDetails/{review['id']}",
        json=body("appStoreReviewDetails", review["id"], {"notes": REVIEW_NOTES}),
    )
    print("Updated iOS review notes for compact pairing QR compatibility", flush=True)


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
        raise RuntimeError("More than one READY_FOR_REVIEW iOS submission exists")
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
        deadline = time.time() + 600
        while True:
            try:
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
                break
            except RuntimeError as error:
                if (
                    "ITEM_PART_OF_ANOTHER_SUBMISSION" not in str(error)
                    or time.time() >= deadline
                ):
                    raise
                print(
                    "Waiting for the canceled iOS review to release the version item...",
                    flush=True,
                )
                time.sleep(15)

    submitted = api.json(
        "PATCH",
        f"/reviewSubmissions/{submission['id']}",
        json=body("reviewSubmissions", submission["id"], {"submitted": True}),
    )["data"]
    print(
        f"Submitted iOS review {submitted['id']}: {submitted['attributes'].get('state')}",
        flush=True,
    )
    return submitted["id"]


def linked_build_id(api: ASC, version_id: str) -> str | None:
    linked = api.json("GET", f"/appStoreVersions/{version_id}/build").get("data")
    return linked and linked.get("id")


def verify(
    api: ASC,
    version_id: str,
    submission_id: str,
    build_id: str,
) -> None:
    if linked_build_id(api, version_id) != build_id:
        raise RuntimeError("iOS App Store version is not linked to the requested build")
    submission = api.json("GET", f"/reviewSubmissions/{submission_id}")["data"]
    state = submission["attributes"].get("state")
    if state not in {"WAITING_FOR_REVIEW", "IN_REVIEW"}:
        raise RuntimeError(f"Unexpected iOS review state after submission: {state}")
    _, present = beta_group_preflight(api, build_id)
    if not present:
        raise RuntimeError("Target build is not linked to the public TestFlight group")
    print(
        f"SENTINEL_REPLACEMENT_OK version={VERSION} build={BUILD} "
        f"submission={submission_id} state={state} betaState={beta_state(api, build_id)}",
        flush=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--execute", action="store_true", help="perform App Store Connect writes")
    parser.add_argument("--confirm", default="", help="exact confirmation string printed by dry run")
    parser.add_argument(
        "--wait-for-build",
        type=int,
        default=0,
        metavar="SECONDS",
        help="wait up to this many seconds for the target build to become VALID",
    )
    args = parser.parse_args()

    if args.execute and args.confirm != CONFIRMATION:
        raise RuntimeError(f"Execution requires --confirm {CONFIRMATION}")

    key_path = Path.home() / f".appstoreconnect/private_keys/AuthKey_{KEY_ID}.p8"
    if not key_path.exists():
        raise RuntimeError(f"Missing API key: {key_path}")
    api = ASC(key_path)
    version = version_resource(api)
    if args.wait_for_build:
        target_build = wait_for_build(api, BUILD, args.wait_for_build)
    else:
        target_build = build_resource(api, BUILD)
        if target_build is None:
            raise RuntimeError(f"Build {BUILD} is missing or not VALID")
    validate_target_build(api, target_build)

    group, in_group = beta_group_preflight(api, target_build["id"])
    validate_beta_localization(api)
    current_build_id = linked_build_id(api, version["id"])
    current_build_number = build_number(api, current_build_id)
    submissions = active_submissions(api)
    states = [(item["id"], item["attributes"].get("state")) for item in submissions]

    print(
        f"PREFLIGHT version={VERSION} state={version['attributes'].get('appStoreState')} "
        f"currentBuild={current_build_number} targetBuild={BUILD} "
        f"targetState={target_build['attributes'].get('processingState')}",
        flush=True,
    )
    print(
        f"PREFLIGHT betaGroup={group['attributes'].get('name')} "
        f"publicLink={group['attributes'].get('publicLink')} alreadyContainsBuild={in_group} "
        f"externalBuildState={beta_state(api, target_build['id'])}",
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

    if not in_group:
        add_to_beta_group(api, target_build["id"])
    submit_beta_review_if_needed(api, target_build["id"])

    submissions = active_submissions(api)
    if current_build_number == EXPECTED_CURRENT_BUILD and submissions:
        cancel_active_submission(api, submissions[0])
        submissions = []
    elif current_build_number == EXPECTED_CURRENT_BUILD:
        submissions = []
    elif current_build_number == BUILD:
        nonresumable = [
            item
            for item in submissions
            if item["attributes"].get("state") not in {"READY_FOR_REVIEW", "WAITING_FOR_REVIEW", "IN_REVIEW"}
        ]
        if nonresumable:
            raise RuntimeError("Target build is linked but the active review is not resumable")

    if current_build_number != BUILD:
        bind_build(api, version["id"], target_build["id"])
    sync_review_notes(api, version["id"])

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
        print(f"iOS review is already submitted: {submission_id}", flush=True)
    else:
        submission_id = create_or_resume_submission(api, version["id"], submissions)
    verify(api, version["id"], submission_id, target_build["id"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
