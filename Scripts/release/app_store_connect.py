#!/usr/bin/env python3
"""Discover Xcode Cloud IDs or wait for a tag-triggered notarized artifact."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

import jwt

BASE_URL = "https://api.appstoreconnect.apple.com/v1"


class AppStoreConnect:
    def __init__(self) -> None:
        self.private_key = os.environ["ASC_PRIVATE_KEY"].replace("\\n", "\n")

    def authorization(self) -> str:
        now = int(time.time())
        token = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 15 * 60, "aud": "appstoreconnect-v1"},
            self.private_key,
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
        )
        return f"Bearer {token}"

    def get(self, path: str) -> dict:
        request = urllib.request.Request(
            f"{BASE_URL}{path}", headers={"Authorization": self.authorization(), "Accept": "application/json"}
        )
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                return json.load(response)
        except urllib.error.HTTPError as error:
            details = error.read().decode("utf-8", errors="replace")
            raise RuntimeError(f"App Store Connect {error.code} for {path}: {details}") from error

    def download(self, url: str, destination: Path) -> None:
        with urllib.request.urlopen(url, timeout=300) as response, destination.open("wb") as output:
            while chunk := response.read(1024 * 1024):
                output.write(chunk)


def matching_run(client: AppStoreConnect, workflow_id: str, tag: str, commit: str) -> dict | None:
    query = urllib.parse.urlencode(
        {
            "limit": 200,
            "sort": "-number",
            "include": "sourceBranchOrTag",
            "fields[scmGitReferences]": "canonicalName,name",
        }
    )
    payload = client.get(f"/ciWorkflows/{workflow_id}/buildRuns?{query}")
    references = {item["id"]: item for item in payload.get("included", [])}
    for candidate in payload.get("data", []):
        source = candidate.get("attributes", {}).get("sourceCommit") or {}
        if source.get("commitSha") != commit:
            continue
        linkage = candidate.get("relationships", {}).get("sourceBranchOrTag", {}).get("data") or {}
        reference = references.get(linkage.get("id"), {})
        if reference.get("attributes", {}).get("canonicalName") == f"refs/tags/{tag}":
            return candidate
    return None


def find_notarized_artifact(client: AppStoreConnect, build_id: str) -> tuple[dict, list[dict]]:
    actions = client.get(f"/ciBuildRuns/{build_id}/actions?limit=200").get("data", [])
    action_types = {action.get("attributes", {}).get("actionType") for action in actions}
    if "ARCHIVE" not in action_types or "NOTARIZE" not in action_types:
        raise RuntimeError("Xcode Cloud build must contain ARCHIVE and NOTARIZE actions")

    for action in actions:
        status = action.get("attributes", {}).get("completionStatus")
        if status not in (None, "SUCCEEDED", "SKIPPED"):
            raise RuntimeError(f"Xcode Cloud action {action['id']} finished with {status}")

    for action in actions:
        artifacts = client.get(f"/ciBuildActions/{action['id']}/artifacts?limit=200").get("data", [])
        for artifact in artifacts:
            if artifact.get("attributes", {}).get("fileType") == "STAPLED_NOTARIZED_ARCHIVE":
                return artifact, actions
    raise RuntimeError("successful build has no STAPLED_NOTARIZED_ARCHIVE")


def discover_ids(client: AppStoreConnect, app_id: str) -> None:
    """Print the Xcode Cloud product and workflow IDs related to an app."""
    product = client.get(f"/apps/{urllib.parse.quote(app_id, safe='')}/ciProduct")["data"]
    product_id = product["id"]
    workflows = client.get(
        f"/ciProducts/{urllib.parse.quote(product_id, safe='')}/workflows"
        "?limit=200&fields%5BciWorkflows%5D=name"
    ).get("data", [])

    print(f"APP_STORE_CONNECT_APP_ID={app_id}")
    print(f"XCODE_CLOUD_PRODUCT_ID={product_id}")
    for workflow in workflows:
        name = workflow.get("attributes", {}).get("name", "unnamed")
        print(f"XCODE_CLOUD_WORKFLOW_ID={workflow['id']}  # {name}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--discover-app-id", help="print the product and workflow IDs related to this app")
    parser.add_argument("--workflow-id")
    parser.add_argument("--product-id")
    parser.add_argument("--app-id")
    parser.add_argument("--tag")
    parser.add_argument("--commit")
    parser.add_argument("--release-id")
    parser.add_argument("--version")
    parser.add_argument("--channel", choices=("stable", "beta"))
    parser.add_argument("--output-directory", type=Path)
    parser.add_argument("--timeout", type=int, default=5400)
    args = parser.parse_args()

    client = AppStoreConnect()
    if args.discover_app_id:
        discover_ids(client, args.discover_app_id)
        return

    required = (
        "workflow_id",
        "product_id",
        "app_id",
        "tag",
        "commit",
        "release_id",
        "version",
        "channel",
        "output_directory",
    )
    missing = [f"--{name.replace('_', '-')}" for name in required if getattr(args, name) is None]
    if missing:
        parser.error(f"the following arguments are required: {', '.join(missing)}")

    workflow = client.get(f"/ciWorkflows/{args.workflow_id}?include=product")
    product_link = workflow["data"]["relationships"]["product"]["data"]["id"]
    if product_link != args.product_id:
        raise RuntimeError("configured workflow does not belong to the configured Xcode Cloud product")
    product = client.get(f"/ciProducts/{args.product_id}?include=app")
    app_link = product["data"]["relationships"]["app"]["data"]["id"]
    if app_link != args.app_id:
        raise RuntimeError("configured Xcode Cloud product does not belong to the configured app")
    deadline = time.monotonic() + args.timeout
    build = None
    while time.monotonic() < deadline:
        build = matching_run(client, args.workflow_id, args.tag, args.commit)
        if build is None:
            print("Waiting for Xcode Cloud to discover the tag…", flush=True)
        else:
            attributes = client.get(f"/ciBuildRuns/{build['id']}")["data"]["attributes"]
            progress = attributes.get("executionProgress")
            completion = attributes.get("completionStatus")
            print(f"Xcode Cloud build {build['id']}: {progress} / {completion}", flush=True)
            if progress == "COMPLETE":
                if completion != "SUCCEEDED":
                    raise RuntimeError(f"Xcode Cloud build finished with {completion}")
                artifact, _ = find_notarized_artifact(client, build["id"])
                detail = client.get(f"/ciArtifacts/{artifact['id']}")["data"]["attributes"]
                args.output_directory.mkdir(parents=True, exist_ok=True)
                filename = Path(detail.get("fileName") or "Metagraf-notarized.zip").name
                client.download(detail["downloadUrl"], args.output_directory / filename)
                manifest = {
                    "tag": args.tag,
                    "version": args.version,
                    "channel": args.channel,
                    "commit": args.commit,
                    "releaseId": int(args.release_id),
                    "xcodeCloudBuildId": build["id"],
                    "build": int(attributes["number"]),
                    "artifactFile": filename,
                }
                (args.output_directory / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
                return
        time.sleep(30)
    raise RuntimeError("timed out waiting for the matching Xcode Cloud build")


if __name__ == "__main__":
    try:
        main()
    except (KeyError, OSError, RuntimeError, urllib.error.URLError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error
