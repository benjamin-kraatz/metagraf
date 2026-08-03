#!/usr/bin/env python3
"""Deterministic helpers shared by the Metagraf release workflow."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import xml.etree.ElementTree as ET
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from email.utils import format_datetime
from pathlib import Path
from typing import Any
from urllib.parse import quote, unquote, urlsplit

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


def select_delta_sources(releases: list[dict[str, Any]], current_tag: str) -> list[dict[str, Any]]:
    """Return the three newest stable and two newest beta predecessors."""
    current = next((release for release in releases if release["tagName"] == current_tag), None)
    if current is None:
        raise ValueError(f"current draft release {current_tag} was not provided")

    published = [release for release in releases if not release.get("isDraft") and release["tagName"] != current_tag]
    published.sort(key=lambda item: item.get("publishedAt") or "", reverse=True)
    stable = [item for item in published if not item.get("isPrerelease")][:3]
    beta = [item for item in published if item.get("isPrerelease")][:2]
    selected = [*stable, *beta]
    selected.sort(key=lambda item: item.get("publishedAt") or "", reverse=True)
    return selected


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
        if entry.get("deltas"):
            deltas = ET.SubElement(item, f"{{{SPARKLE_NS}}}deltas")
            for delta in entry["deltas"]:
                attributes = {
                    "url": delta["url"],
                    f"{{{SPARKLE_NS}}}deltaFrom": str(delta["fromBuild"]),
                    "length": str(delta["length"]),
                    "type": "application/octet-stream",
                    f"{{{SPARKLE_NS}}}edSignature": delta["signature"],
                }
                if delta.get("fromSparkleExecutableSize") is not None:
                    attributes[f"{{{SPARKLE_NS}}}deltaFromSparkleExecutableSize"] = str(
                        delta["fromSparkleExecutableSize"]
                    )
                if delta.get("fromSparkleLocales"):
                    attributes[f"{{{SPARKLE_NS}}}deltaFromSparkleLocales"] = delta["fromSparkleLocales"]
                ET.SubElement(deltas, "enclosure", attributes)

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

        delta_parent = item.find(f"{{{SPARKLE_NS}}}deltas")
        actual_deltas = [] if delta_parent is None else delta_parent.findall("enclosure")
        expected_deltas = entry.get("deltas", [])
        if len(actual_deltas) != len(expected_deltas):
            raise ValueError("appcast delta entry count does not match the generated delta files")
        seen_from_builds: set[str] = set()
        for delta_item, delta in zip(actual_deltas, expected_deltas, strict=True):
            from_build = delta_item.get(f"{{{SPARKLE_NS}}}deltaFrom")
            if from_build != str(delta["fromBuild"]) or from_build in seen_from_builds:
                raise ValueError("appcast delta source builds are invalid")
            seen_from_builds.add(from_build)
            if delta_item.get("url") != delta["url"]:
                raise ValueError("appcast delta URL does not match its generated delta")
            if delta_item.get(f"{{{SPARKLE_NS}}}edSignature") != delta["signature"]:
                raise ValueError("appcast delta signature does not match its generated delta")
            if delta_item.get("length") != str(delta["length"]):
                raise ValueError("appcast delta length does not match its generated delta")
            if delta_item.get("type") != "application/octet-stream":
                raise ValueError("appcast delta enclosure type is invalid")
            expected_executable_size = delta.get("fromSparkleExecutableSize")
            actual_executable_size = delta_item.get(f"{{{SPARKLE_NS}}}deltaFromSparkleExecutableSize")
            if actual_executable_size != (
                str(expected_executable_size) if expected_executable_size is not None else None
            ):
                raise ValueError("appcast delta Sparkle executable metadata is invalid")
            expected_locales = delta.get("fromSparkleLocales")
            actual_locales = delta_item.get(f"{{{SPARKLE_NS}}}deltaFromSparkleLocales")
            if actual_locales != expected_locales:
                raise ValueError("appcast delta Sparkle locale metadata is invalid")


def extract_deltas(
    path: Path,
    target_build: int,
    delta_directory: Path,
    download_url_prefix: str,
) -> list[dict[str, Any]]:
    """Extract and validate the latest item's deltas from Sparkle's generated appcast."""
    root = ET.parse(path).getroot()
    items = root.findall("channel/item")
    matching = [
        item
        for item in items
        if item.findtext(f"{{{SPARKLE_NS}}}version") == str(target_build)
    ]
    if len(matching) != 1:
        raise ValueError(f"generated delta appcast does not contain exactly one build {target_build}")

    delta_parent = matching[0].find(f"{{{SPARKLE_NS}}}deltas")
    if delta_parent is None:
        return []

    delta_directory = delta_directory.resolve()
    deltas: list[dict[str, Any]] = []
    seen_from_builds: set[str] = set()
    for enclosure in delta_parent.findall("enclosure"):
        from_build = enclosure.get(f"{{{SPARKLE_NS}}}deltaFrom")
        signature = enclosure.get(f"{{{SPARKLE_NS}}}edSignature")
        length_text = enclosure.get("length")
        raw_url = enclosure.get("url")
        if not from_build or not signature or not length_text or not raw_url:
            raise ValueError("generated delta appcast contains an incomplete enclosure")
        if from_build in seen_from_builds:
            raise ValueError("generated delta appcast contains duplicate source builds")
        seen_from_builds.add(from_build)
        try:
            length = int(length_text)
            int(from_build)
        except ValueError as error:
            raise ValueError("generated delta appcast contains a non-numeric build or length") from error

        filename = unquote(Path(urlsplit(raw_url).path).name)
        if not filename or not filename.endswith(".delta"):
            raise ValueError(f"generated delta URL does not name a .delta file: {raw_url}")
        delta_path = (delta_directory / filename).resolve()
        if delta_path.parent != delta_directory or not delta_path.is_file():
            raise ValueError(f"generated delta file is missing: {filename}")
        actual_length = delta_path.stat().st_size
        if actual_length != length:
            raise ValueError(f"generated delta length is incorrect for {filename}")

        delta: dict[str, Any] = {
            "file": filename,
            "url": f"{download_url_prefix.rstrip('/')}/{quote(filename)}",
            "fromBuild": int(from_build),
            "length": length,
            "signature": signature,
        }
        executable_size = enclosure.get(f"{{{SPARKLE_NS}}}deltaFromSparkleExecutableSize")
        if executable_size is not None:
            try:
                delta["fromSparkleExecutableSize"] = int(executable_size)
            except ValueError as error:
                raise ValueError(f"generated delta executable metadata is invalid for {filename}") from error
        locales = enclosure.get(f"{{{SPARKLE_NS}}}deltaFromSparkleLocales")
        if locales:
            delta["fromSparkleLocales"] = locales
        deltas.append(delta)

    return deltas


def main() -> None:
    parser = argparse.ArgumentParser()
    commands = parser.add_subparsers(dest="command", required=True)

    validate = commands.add_parser("validate-tag")
    validate.add_argument("tag")

    ancestry = commands.add_parser("validate-ancestry")
    ancestry.add_argument("commit")
    ancestry.add_argument("main_ref", metavar="main-ref")

    notes = commands.add_parser("generate-notes")
    notes.add_argument("--tag", required=True)
    notes.add_argument("--output", type=Path, required=True)
    notes.add_argument("--repository", type=Path, default=Path("."))
    notes.add_argument("--model", default="composer-2.5")
    notes.add_argument("--api-key", default=None)

    history = commands.add_parser("select-history")
    history.add_argument("--releases", type=Path, required=True)
    history.add_argument("--current-tag", required=True)
    history.add_argument("--output", type=Path, required=True)

    delta_history = commands.add_parser("select-delta-sources")
    delta_history.add_argument("--releases", type=Path, required=True)
    delta_history.add_argument("--current-tag", required=True)
    delta_history.add_argument("--output", type=Path, required=True)

    appcast = commands.add_parser("build-appcast")
    appcast.add_argument("--entries", type=Path, required=True)
    appcast.add_argument("--output", type=Path, required=True)

    appcast_validation = commands.add_parser("validate-appcast")
    appcast_validation.add_argument("--entries", type=Path, required=True)
    appcast_validation.add_argument("--appcast", type=Path, required=True)

    delta_extraction = commands.add_parser("extract-deltas")
    delta_extraction.add_argument("--appcast", type=Path, required=True)
    delta_extraction.add_argument("--target-build", type=int, required=True)
    delta_extraction.add_argument("--delta-directory", type=Path, required=True)
    delta_extraction.add_argument("--download-url-prefix", required=True)

    args = parser.parse_args()
    try:
        if args.command == "validate-tag":
            print(json.dumps(asdict(parse_tag(args.tag))))
        elif args.command == "validate-ancestry":
            if not is_ancestor(args.commit, args.main_ref):
                raise ValueError(f"{args.commit} is not contained in {args.main_ref}")
        elif args.command == "generate-notes":
            try:
                from release_notes import generate_release_notes
            except ImportError:  # pragma: no cover - package import path for tests
                from Scripts.release.release_notes import generate_release_notes
            from cursor_sdk import CursorAgentError

            try:
                notes_text = generate_release_notes(
                    args.tag,
                    repository=args.repository,
                    api_key=args.api_key or os.environ.get("CURSOR_API_KEY"),
                    model=args.model,
                )
            except CursorAgentError as error:
                print(f"error: {error}", file=sys.stderr)
                raise SystemExit(1) from error
            except RuntimeError as error:
                print(f"error: {error}", file=sys.stderr)
                raise SystemExit(2) from error
            args.output.write_text(notes_text, encoding="utf-8")
        elif args.command == "select-history":
            releases = json.loads(args.releases.read_text(encoding="utf-8"))
            args.output.write_text(json.dumps(select_history(releases, args.current_tag), indent=2), encoding="utf-8")
        elif args.command == "select-delta-sources":
            releases = json.loads(args.releases.read_text(encoding="utf-8"))
            args.output.write_text(json.dumps(select_delta_sources(releases, args.current_tag), indent=2), encoding="utf-8")
        elif args.command == "build-appcast":
            build_appcast(json.loads(args.entries.read_text(encoding="utf-8")), args.output)
        elif args.command == "validate-appcast":
            validate_appcast(args.appcast, json.loads(args.entries.read_text(encoding="utf-8")))
        elif args.command == "extract-deltas":
            print(
                json.dumps(
                    extract_deltas(
                        args.appcast,
                        args.target_build,
                        args.delta_directory,
                        args.download_url_prefix,
                    )
                )
            )
    except (ValueError, OSError, KeyError, json.JSONDecodeError, ET.ParseError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1) from error


if __name__ == "__main__":
    main()
