#!/usr/bin/env python3
"""Deterministic helpers shared by the Metagraf release workflow."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from typing import Any

SPARKLE_NS = "http://www.andymatuschak.org/xml-namespaces/sparkle"
NUMBER = r"(?:0|[1-9]\d*)"
SEMVER = re.compile(
    rf"^v(?P<version>{NUMBER}\.{NUMBER}\.{NUMBER}(?P<suffix>-beta\.(?P<beta>{NUMBER}))?)$"
)


@dataclass(frozen=True)
class ReleaseVersion:
    tag: str
    version: str
    channel: str
    prerelease: bool


def parse_tag(tag: str) -> ReleaseVersion:
    match = SEMVER.fullmatch(tag)
    if match is None:
        raise ValueError(f"unsupported release tag: {tag}")
    prerelease = match.group("beta") is not None
    return ReleaseVersion(tag, match.group("version"), "beta" if prerelease else "stable", prerelease)


def is_ancestor(commit: str, main_ref: str, repository: Path = Path(".")) -> bool:
    result = subprocess.run(
        ["git", "merge-base", "--is-ancestor", commit, main_ref],
        cwd=repository,
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return result.returncode == 0


def select_history(releases: list[dict[str, Any]], current_tag: str) -> list[dict[str, Any]]:
    """Return current + four prior stable + two prior beta releases."""
    current = next((release for release in releases if release["tagName"] == current_tag), None)
    if current is None:
        raise ValueError(f"current draft release {current_tag} was not provided")

    published = [release for release in releases if not release.get("isDraft") and release["tagName"] != current_tag]
    published.sort(key=lambda item: item.get("publishedAt") or "", reverse=True)
    stable = [item for item in published if not item.get("isPrerelease")][:4]
    beta = [item for item in published if item.get("isPrerelease")][:2]
    selected = [current, *stable, *beta]
    selected.sort(key=lambda item: item.get("publishedAt") or "9999", reverse=True)
    return selected


def placeholder_notes(url: str) -> str:
    with urllib.request.urlopen(url, timeout=15) as response:  # noqa: S310 - fixed workflow URL
        payload = json.load(response)
    title = str(payload.get("title", "Release")).strip()
    body = str(payload.get("body", "Keine Details verfügbar.")).strip()
    if not title or not body:
        raise ValueError("placeholder notes response needs non-empty title and body")
    return (
        "<!-- PLACEHOLDER: replace Scripts/release/release_tools.py notes provider -->\n"
        "## Änderungen\n\n"
        f"**{title}**\n\n{body}\n\n"
        "_Diese Versionshinweise wurden vorübergehend aus dem Typicode-Testdienst erzeugt._\n"
    )


def build_appcast(entries: list[dict[str, Any]], output: Path) -> None:
    ET.register_namespace("sparkle", SPARKLE_NS)
    rss = ET.Element("rss", {"version": "2.0"})
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "Metagraf Updates"
    ET.SubElement(channel, "link").text = "https://github.com/benjamin-kraatz/metagraf"
    ET.SubElement(channel, "description").text = "Metagraf release feed"
    ET.SubElement(channel, "language").text = "de"

    for entry in entries:
        item = ET.SubElement(channel, "item")
        ET.SubElement(item, "title").text = f"Metagraf {entry['version']}"
        ET.SubElement(item, f"{{{SPARKLE_NS}}}version").text = str(entry["build"])
        ET.SubElement(item, f"{{{SPARKLE_NS}}}shortVersionString").text = entry["version"]
        if entry.get("channel") == "beta":
            ET.SubElement(item, f"{{{SPARKLE_NS}}}channel").text = "beta"
        published = datetime.fromisoformat(entry["publishedAt"].replace("Z", "+00:00"))
        ET.SubElement(item, "pubDate").text = format_datetime(published.astimezone(timezone.utc))
        notes = ET.SubElement(item, "description", {f"{{{SPARKLE_NS}}}format": "markdown"})
        notes.text = entry["notes"]
        ET.SubElement(
            item,
            "enclosure",
            {
                "url": entry["url"],
                f"{{{SPARKLE_NS}}}edSignature": entry["signature"],
                "length": str(entry["length"]),
                "type": "application/octet-stream",
            },
        )

    ET.indent(rss)
    output.write_bytes(ET.tostring(rss, encoding="utf-8", xml_declaration=True))


def validate_appcast(path: Path, entries: list[dict[str, Any]]) -> None:
    items = ET.parse(path).getroot().findall("channel/item")
    if len(items) != len(entries) or not 1 <= len(items) <= 7:
        raise ValueError("appcast entry count does not match the retained release history")
    builds = [int(item.findtext(f"{{{SPARKLE_NS}}}version", "-1")) for item in items]
    if builds != sorted(builds, reverse=True) or len(builds) != len(set(builds)):
        raise ValueError("appcast build versions must be unique and descending")
    for item, entry in zip(items, entries, strict=True):
        enclosure = item.find("enclosure")
        if enclosure is None or enclosure.get("url") != entry["url"]:
            raise ValueError("appcast enclosure URL does not match its release")
        if enclosure.get(f"{{{SPARKLE_NS}}}edSignature") != entry["signature"]:
            raise ValueError("appcast enclosure signature does not match its release")
        channel = item.findtext(f"{{{SPARKLE_NS}}}channel")
        expected_channel = "beta" if entry["channel"] == "beta" else None
        if channel != expected_channel:
            raise ValueError("appcast channel classification is invalid")


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    validate = commands.add_parser("validate-tag")
    validate.add_argument("tag")

    ancestry = commands.add_parser("validate-ancestry")
    ancestry.add_argument("commit")
    ancestry.add_argument("main-ref")

    notes = commands.add_parser("placeholder-notes")
    notes.add_argument("--url", default="https://jsonplaceholder.typicode.com/posts/1")
    notes.add_argument("--output", type=Path, required=True)

    history = commands.add_parser("select-history")
    history.add_argument("--releases", type=Path, required=True)
    history.add_argument("--current-tag", required=True)
    history.add_argument("--output", type=Path, required=True)

    appcast = commands.add_parser("build-appcast")
    appcast.add_argument("--entries", type=Path, required=True)
    appcast.add_argument("--output", type=Path, required=True)

    appcast_validation = commands.add_parser("validate-appcast")
    appcast_validation.add_argument("--entries", type=Path, required=True)
    appcast_validation.add_argument("--appcast", type=Path, required=True)

    args = parser.parse_args()
    try:
        if args.command == "validate-tag":
            print(json.dumps(asdict(parse_tag(args.tag))))
        elif args.command == "validate-ancestry":
            if not is_ancestor(args.commit, args.main_ref):
                raise ValueError(f"{args.commit} is not contained in {args.main_ref}")
        elif args.command == "placeholder-notes":
            args.output.write_text(placeholder_notes(args.url), encoding="utf-8")
        elif args.command == "select-history":
            releases = json.loads(args.releases.read_text(encoding="utf-8"))
            args.output.write_text(json.dumps(select_history(releases, args.current_tag), indent=2), encoding="utf-8")
        elif args.command == "build-appcast":
            build_appcast(json.loads(args.entries.read_text(encoding="utf-8")), args.output)
        elif args.command == "validate-appcast":
            validate_appcast(args.appcast, json.loads(args.entries.read_text(encoding="utf-8")))
    except (ValueError, OSError, KeyError, json.JSONDecodeError, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
