"""Generate German GitHub release notes via the Cursor SDK."""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable
from urllib.parse import quote

from cursor_sdk import Agent, AgentOptions, CursorAgentError, LocalAgentOptions, RunResult

DEFAULT_MODEL = "cursor-grok-4.5-low"
PR_REF = re.compile(r"\(#(\d+)\)")


@dataclass(frozen=True)
class CommitInfo:
    sha: str
    subject: str
    body: str
    shortstat: str


@dataclass(frozen=True)
class PullRequestInfo:
    number: int
    title: str
    author: str | None
    url: str


def find_previous_tag(current_tag: str, repository: Path = Path(".")) -> str | None:
    result = subprocess.run(
        ["git", "describe", "--tags", "--abbrev=0", f"{current_tag}^"],
        cwd=repository,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    previous = result.stdout.strip()
    return previous or None


def collect_commits(
    current_tag: str,
    previous_tag: str | None,
    repository: Path = Path("."),
) -> list[CommitInfo]:
    revision_range = current_tag if previous_tag is None else f"{previous_tag}..{current_tag}"
    output = subprocess.check_output(
        [
            "git",
            "log",
            revision_range,
            "--no-merges",
            "--format=%H%x1f%s%x1f%b%x1e",
        ],
        cwd=repository,
        text=True,
    )
    commits: list[CommitInfo] = []
    for record in output.split("\x1e"):
        record = record.strip("\n")
        if not record.strip():
            continue
        parts = record.split("\x1f", 2)
        if len(parts) < 2:
            continue
        sha, subject = parts[0].strip(), parts[1].strip()
        body = parts[2].strip() if len(parts) > 2 else ""
        if not sha or not subject:
            continue
        shortstat = subprocess.check_output(
            ["git", "show", "--shortstat", "--format=", sha],
            cwd=repository,
            text=True,
        ).strip()
        commits.append(CommitInfo(sha=sha, subject=subject, body=body, shortstat=shortstat))
    return commits


def _github_json(url: str, token: str) -> Any:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "X-GitHub-Api-Version": "2022-11-28",
            "User-Agent": "metagraf-release-notes",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - GitHub API
        return json.load(response)


def _pr_from_payload(payload: dict[str, Any], repository: str) -> PullRequestInfo | None:
    number = payload.get("number")
    title = str(payload.get("title") or "").strip()
    if not isinstance(number, int) or not title:
        return None
    user = payload.get("user") or {}
    login = str(user.get("login") or "").strip() or None
    user_type = str(user.get("type") or "")
    if login and (user_type == "Bot" or login.endswith("[bot]")):
        login = None
    url = str(payload.get("html_url") or f"https://github.com/{repository}/pull/{number}")
    return PullRequestInfo(number=number, title=title, author=login, url=url)


def collect_pull_requests(
    commits: list[CommitInfo],
    repository: str,
    token: str,
) -> list[PullRequestInfo]:
    found: dict[int, PullRequestInfo] = {}
    for commit in commits:
        url = (
            f"https://api.github.com/repos/{repository}/commits/"
            f"{quote(commit.sha)}/pulls"
        )
        try:
            payload = _github_json(url, token)
        except urllib.error.HTTPError as error:
            if error.code in {404, 422}:
                payload = []
            else:
                raise
        if not isinstance(payload, list):
            continue
        for item in payload:
            if isinstance(item, dict):
                pr = _pr_from_payload(item, repository)
                if pr is not None:
                    found[pr.number] = pr

        for match in PR_REF.finditer(commit.subject):
            number = int(match.group(1))
            if number in found:
                continue
            pr_url = f"https://api.github.com/repos/{repository}/pulls/{number}"
            try:
                item = _github_json(pr_url, token)
            except urllib.error.HTTPError as error:
                if error.code == 404:
                    continue
                raise
            if isinstance(item, dict):
                pr = _pr_from_payload(item, repository)
                if pr is not None:
                    found[pr.number] = pr

    return [found[number] for number in sorted(found)]


def format_reference_footer(
    pull_requests: list[PullRequestInfo],
    commits: list[CommitInfo],
) -> str:
    lines: list[str] = []
    if pull_requests:
        for pr in pull_requests:
            line = f"- {pr.title} (#{pr.number})"
            if pr.author:
                line += f" thanks to @{pr.author}"
            lines.append(line)
    else:
        for commit in commits[:10]:
            lines.append(f"- {commit.subject} ({commit.sha[:7]})")
    if not lines:
        return ""
    return "---\n\n" + "\n".join(lines) + "\n"


def build_notes_prompt(
    *,
    tag: str,
    previous_tag: str | None,
    commits: list[CommitInfo],
) -> str:
    commit_blocks: list[str] = []
    for commit in commits:
        block = f"- {commit.sha[:10]} {commit.subject}"
        if commit.shortstat:
            block += f"\n  stat: {commit.shortstat}"
        if commit.body:
            indented = "\n".join(f"  {line}" for line in commit.body.splitlines())
            block += f"\n{indented}"
        commit_blocks.append(block)

    commit_section = "\n".join(commit_blocks) if commit_blocks else "(no commits in range)"
    previous = previous_tag or "(none — first tagged release)"

    return f"""You are writing GitHub release notes for the macOS app Metagraf.

Release tag: {tag}
Previous release tag: {previous}

Commits since the previous release (newest first unless git order differs):
{commit_section}

Write German release notes for end users. Output Markdown only — no code fences, no preamble, no PR/commit appendix.

Required structure:
1. Start with one short free-text summary paragraph of the overall changes (German).
2. Then list changes under these exact headings when non-empty:
   - ## Features — user-visible, user-notable changes that are not bug fixes
   - ## Bug Fixes — bug fixes
   - ## Weitere Verbesserungen — everything else worth mentioning (performance, internal improvements, localization, etc.)
3. Omit any section that would be empty.
4. Do not mention chore commits, and do not mention CI/build/test/docs/style-only churn unless it has a user-visible effect.
5. Conventional commit prefixes (feat, fix, chore, ci, …) are hints. If a prefix is missing or wrong, infer the category from the subject and, if needed, inspect the commit with `git show <sha>` in this repository.
6. Prefer concise bullet points under each heading. Do not invent changes that are not supported by the commits/diffs.
7. Do not edit files. Do not create commits. Reply with the release notes Markdown only.
"""


def normalize_notes_body(text: str) -> str:
    cleaned = text.strip()
    if cleaned.startswith("```"):
        lines = cleaned.splitlines()
        lines = lines[1:]
        if lines and lines[-1].strip() == "```":
            lines = lines[:-1]
        cleaned = "\n".join(lines).strip()
    return cleaned


def log_run_usage(result: RunResult) -> None:
    model_id = result.model.id if result.model is not None else "unknown"
    print(
        f"cursor-sdk run id={result.id} agent_id={result.agent_id} "
        f"status={result.status} model={model_id} duration_ms={result.duration_ms}",
        flush=True,
    )
    usage = result.usage
    if usage is None:
        print("cursor-sdk usage: not reported", flush=True)
        return
    parts = [
        f"total={usage.total_tokens}",
        f"input={usage.input_tokens}",
        f"output={usage.output_tokens}",
        f"cache_read={usage.cache_read_tokens}",
        f"cache_write={usage.cache_write_tokens}",
    ]
    if usage.reasoning_tokens is not None:
        parts.append(f"reasoning={usage.reasoning_tokens}")
    print("cursor-sdk usage: " + " ".join(parts), flush=True)


PromptRunner = Callable[[str, AgentOptions], RunResult]


def _default_prompt_runner(message: str, options: AgentOptions) -> RunResult:
    return Agent.prompt(message, options)


def generate_release_notes(
    tag: str,
    *,
    repository: Path = Path("."),
    api_key: str | None = None,
    model: str = DEFAULT_MODEL,
    github_repository: str | None = None,
    github_token: str | None = None,
    prompt_runner: PromptRunner | None = None,
) -> str:
    api_key = api_key or os.environ.get("CURSOR_API_KEY")
    if not api_key:
        raise ValueError("CURSOR_API_KEY is required to generate release notes")

    github_repository = github_repository or os.environ.get("GITHUB_REPOSITORY")
    github_token = github_token or os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")

    previous_tag = find_previous_tag(tag, repository)
    commits = collect_commits(tag, previous_tag, repository)
    print(
        f"release-notes: tag={tag} previous={previous_tag or 'none'} commits={len(commits)}",
        flush=True,
    )

    pull_requests: list[PullRequestInfo] = []
    if github_repository and github_token:
        pull_requests = collect_pull_requests(commits, github_repository, github_token)
        print(f"release-notes: pull_requests={len(pull_requests)}", flush=True)
    else:
        print(
            "release-notes: skipping PR lookup (GITHUB_REPOSITORY or GH_TOKEN missing)",
            flush=True,
        )

    prompt = build_notes_prompt(tag=tag, previous_tag=previous_tag, commits=commits)
    options = AgentOptions(
        api_key=api_key,
        model=model,
        local=LocalAgentOptions(cwd=str(repository.resolve())),
    )
    runner = prompt_runner or _default_prompt_runner

    try:
        result = runner(prompt, options)
    except CursorAgentError as error:
        print(
            f"cursor-sdk startup failed: {error} "
            f"retryable={getattr(error, 'is_retryable', None)} "
            f"request_id={getattr(error, 'request_id', None)}",
            file=sys.stderr,
            flush=True,
        )
        raise

    log_run_usage(result)
    if result.status != "finished":
        raise RuntimeError(f"cursor-sdk run did not finish successfully: status={result.status}")
    body = normalize_notes_body(result.result or "")
    if not body:
        raise RuntimeError("cursor-sdk run returned empty release notes")

    footer = format_reference_footer(pull_requests, commits)
    if footer:
        return f"{body.rstrip()}\n\n{footer}"
    return f"{body.rstrip()}\n"
