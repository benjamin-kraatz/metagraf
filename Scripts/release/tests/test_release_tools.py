import subprocess
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path
from unittest.mock import MagicMock

from Scripts.release.release_notes import (
    CommitInfo,
    PullRequestInfo,
    format_reference_footer,
    generate_release_notes,
    normalize_notes_body,
)
from Scripts.release.release_tools import (
    SPARKLE_NS,
    build_appcast,
    extract_deltas,
    is_ancestor,
    parse_tag,
    select_delta_sources,
    select_history,
    validate_appcast,
)


class ReleaseToolsTests(unittest.TestCase):
    def test_tag_parsing(self):
        self.assertEqual(parse_tag("v1.2.3").channel, "stable")
        beta = parse_tag("v1.2.3-beta.4")
        self.assertTrue(beta.prerelease)
        self.assertEqual(beta.version, "1.2.3-beta.4")
        for invalid in ("1.2.3", "v1.2", "v1.2.3-rc.1", "v01.2.3"):
            with self.assertRaises(ValueError):
                parse_tag(invalid)

    def test_history_retains_four_stable_and_two_beta_plus_current(self):
        releases = [{"tagName": "v2.0.0", "isDraft": True, "isPrerelease": False, "publishedAt": None}]
        for index in range(1, 7):
            releases.append({"tagName": f"v1.{index}.0", "isDraft": False, "isPrerelease": False, "publishedAt": f"2026-0{index}-01T00:00:00Z"})
        for index in range(1, 5):
            releases.append({"tagName": f"v2.0.0-beta.{index}", "isDraft": False, "isPrerelease": True, "publishedAt": f"2026-07-0{index}T00:00:00Z"})
        selected = select_history(releases, "v2.0.0")
        self.assertEqual(len(selected), 7)
        self.assertEqual(sum(not item["isPrerelease"] and not item["isDraft"] for item in selected), 4)
        self.assertEqual(sum(item["isPrerelease"] for item in selected), 2)

    def test_delta_sources_retain_three_stable_and_two_beta_predecessors(self):
        releases = [{"tagName": "v0.21.0", "isDraft": True, "isPrerelease": False, "publishedAt": None}]
        for index in range(1, 7):
            releases.append(
                {
                    "tagName": f"v0.{20 - index}.0",
                    "isDraft": False,
                    "isPrerelease": False,
                    "publishedAt": f"2026-0{index}-01T00:00:00Z",
                }
            )
        for index in range(1, 5):
            releases.append(
                {
                    "tagName": f"v0.21.0-beta.{index}",
                    "isDraft": False,
                    "isPrerelease": True,
                    "publishedAt": f"2026-07-0{index}T00:00:00Z",
                }
            )

        selected = select_delta_sources(releases, "v0.21.0")

        self.assertEqual(len(selected), 5)
        self.assertEqual(sum(not item["isPrerelease"] for item in selected), 3)
        self.assertEqual(sum(item["isPrerelease"] for item in selected), 2)
        self.assertNotIn("v0.21.0", {item["tagName"] for item in selected})

    def test_git_ancestry(self):
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "Release Test"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.email", "release@example.test"], cwd=repository, check=True)
            (repository / "value").write_text("one", encoding="utf-8")
            subprocess.run(["git", "add", "value"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-qm", "one"], cwd=repository, check=True)
            first = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository, text=True).strip()
            (repository / "value").write_text("two", encoding="utf-8")
            subprocess.run(["git", "commit", "-qam", "two"], cwd=repository, check=True)
            second = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=repository, text=True).strip()
            self.assertTrue(is_ancestor(first, second, repository))
            self.assertFalse(is_ancestor(second, first, repository))

    def test_validate_ancestry_cli(self):
        result = subprocess.run(
            [sys.executable, "Scripts/release/release_tools.py", "validate-ancestry", "HEAD", "HEAD"],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_reference_footer_lists_prs_with_thanks(self):
        footer = format_reference_footer(
            [
                PullRequestInfo(12, "Add dark mode", "alice", "https://example.test/12"),
                PullRequestInfo(13, "Fix crash", None, "https://example.test/13"),
            ],
            [],
        )
        self.assertIn("Add dark mode (#12) thanks to @alice", footer)
        self.assertIn("- Fix crash (#13)", footer)
        self.assertNotIn("Fix crash (#13) thanks to", footer)

    def test_reference_footer_falls_back_to_commits(self):
        footer = format_reference_footer(
            [],
            [
                CommitInfo("aaaaaaaa", "feat: one", "", "1 file changed"),
                CommitInfo("bbbbbbbb", "fix: two", "", "1 file changed"),
            ],
        )
        self.assertIn("feat: one (aaaaaaa)", footer)
        self.assertIn("fix: two (bbbbbbb)", footer)

    def test_normalize_notes_strips_code_fences(self):
        self.assertEqual(normalize_notes_body("```markdown\nHallo\n```"), "Hallo")

    def test_generate_release_notes_appends_footer(self):
        result = MagicMock()
        result.id = "run-1"
        result.agent_id = "agent-1"
        result.status = "finished"
        result.result = "## Features\n\n- Dunkler Modus\n"
        result.model = MagicMock(id="cursor-grok-4.5-low")
        result.duration_ms = 12
        result.usage = None

        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "Release Test"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.email", "release@example.test"], cwd=repository, check=True)
            (repository / "value").write_text("one", encoding="utf-8")
            subprocess.run(["git", "add", "value"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-qm", "feat: one"], cwd=repository, check=True)
            subprocess.run(["git", "tag", "-am", "v0.1.0", "v0.1.0"], cwd=repository, check=True)
            (repository / "value").write_text("two", encoding="utf-8")
            subprocess.run(["git", "commit", "-qam", "feat: two (#7)"], cwd=repository, check=True)
            subprocess.run(["git", "tag", "-am", "v0.2.0", "v0.2.0"], cwd=repository, check=True)

            notes = generate_release_notes(
                "v0.2.0",
                repository=repository,
                api_key="test-key",
                github_repository=None,
                github_token=None,
                prompt_runner=lambda *_: result,
            )

        self.assertIn("Dunkler Modus", notes)
        self.assertIn("feat: two (#7)", notes)
        self.assertIn("---", notes)

    def test_appcast_contains_build_channel_and_signature(self):
        entry = {
            "version": "1.2.3-beta.1",
            "build": 42,
            "channel": "beta",
            "publishedAt": "2026-08-02T12:00:00Z",
            "notes": "## Änderungen\n\nTest",
            "url": "https://example.test/Metagraf.zip",
            "signature": "signed",
            "length": 123,
            "deltas": [
                {
                    "file": "Metagraf43-42.delta",
                    "fromBuild": 41,
                    "url": "https://example.test/Metagraf43-42.delta",
                    "signature": "delta-signed",
                    "length": 17,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "appcast.xml"
            build_appcast([entry], path)
            validate_appcast(path, [entry])
            root = ET.parse(path).getroot()
        self.assertEqual(root.findtext(f"channel/item/{{{SPARKLE_NS}}}version"), "42")
        self.assertEqual(root.findtext(f"channel/item/{{{SPARKLE_NS}}}channel"), "beta")
        enclosure = root.find("channel/item/enclosure")
        self.assertEqual(enclosure.attrib[f"{{{SPARKLE_NS}}}edSignature"], "signed")
        delta = root.find(f"channel/item/{{{SPARKLE_NS}}}deltas/enclosure")
        self.assertEqual(delta.attrib[f"{{{SPARKLE_NS}}}deltaFrom"], "41")
        self.assertEqual(delta.attrib[f"{{{SPARKLE_NS}}}edSignature"], "delta-signed")

    def test_extract_deltas_validates_generated_file_and_rewrites_download_url(self):
        entry = {
            "version": "1.2.3",
            "build": 42,
            "channel": "stable",
            "publishedAt": "2026-08-02T12:00:00Z",
            "notes": "Test",
            "url": "Metagraf-1.2.3.zip",
            "signature": "signed",
            "length": 123,
            "deltas": [
                {
                    "file": "Metagraf42-41.delta",
                    "fromBuild": 41,
                    "url": "Metagraf42-41.delta",
                    "signature": "delta-signed",
                    "length": 5,
                }
            ],
        }
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            delta_directory = root / "deltas"
            delta_directory.mkdir()
            (delta_directory / "Metagraf42-41.delta").write_bytes(b"delta")
            generated_appcast = root / "generated-appcast.xml"
            build_appcast([entry], generated_appcast)

            deltas = extract_deltas(
                generated_appcast,
                42,
                delta_directory,
                "https://example.test/releases/v1.2.3",
            )

        self.assertEqual(deltas[0]["fromBuild"], 41)
        self.assertEqual(deltas[0]["url"], "https://example.test/releases/v1.2.3/Metagraf42-41.delta")
        self.assertEqual(deltas[0]["length"], 5)


if __name__ == "__main__":
    unittest.main()
