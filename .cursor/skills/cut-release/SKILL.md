---
name: cut-release
description: Propose a MarketVer marketing version from commits since the last release, confirm with the user (beta only if explicitly requested; otherwise stable), then bump macOS MARKETING_VERSION, commit, annotate-tag, and push to trigger the Metagraf release pipeline. After push, ask whether to babysit GitHub Actions and Xcode Cloud until publication. Use when cutting a release, tagging a version, or when the user invokes /cut-release.
disable-model-invocation: true
---

# Cut Release (MarketVer)

Cut a **macOS-only** Metagraf release. Do **not** touch iOS / `MetagrafKeyboard` versions. Do **not** change `CURRENT_PROJECT_VERSION` (build number is owned by Xcode Cloud).

Follow `Docs/ReleaseWorkflow.md` for tag/channel contracts.

## Hard gates (deny immediately)

Abort with a short refusal and **make no changes** if any of these fail:

1. Current branch is not `main`
2. Working tree is not clean (`git status --porcelain` non-empty)
3. User does **not** confirm the proposal (see below)

## MarketVer (shifted SemVer)

Map conventional-commit SemVer intent → **MarketVer** bump:

| SemVer intent | MarketVer bump |
|---------------|----------------|
| major (breaking / `!` / `BREAKING CHANGE:`) | **minor** |
| minor (`feat`) | **patch** |
| patch (`fix`, and most other releasable changes) | **patch** |

There is **no MarketVer major** bump from commits. Highest possible bump is **minor**.

Non-conventional messages: infer SemVer intent from message + diff (API/behavior breaks → major intent → MarketVer minor; new user-facing capability → minor intent → MarketVer patch; fixes/chores that ship → patch). Pure docs/ci/test with no product change → no bump from that commit.

If nothing warrants a bump but a release is still being cut, default to a **patch** bump so the tag/version advances.

## Phase 1 — Propose only (no mutations)

1. Confirm gates: on `main`, clean tree.
2. Resolve **baseline** from the latest release tag matching `v*` (`vX.Y.Z` or `vX.Y.Z-beta.N`). Use the tag’s numeric `X.Y.Z` as baseline. Prefer version-sort, not commit date alone.
3. Determine commits **since that tag** on `main`.
4. **Batch scan oldest → newest** (e.g. 20–50 commits per batch). Track the highest MarketVer bump seen. **Stop early** once a MarketVer **minor** is found (that is the ceiling; later commits cannot raise it further). Skip loading further batches when that happens.
5. Apply the highest bump to the baseline → proposed numeric marketing version `X.Y.Z` (**never** include `-beta` here; **never** invent a build number).
6. Present the proposal: baseline tag, proposed version, bump reason (which commit/intent drove it), and a short commit summary. **Pause.**
7. Explicitly ask:
   - Confirm this version (or give a different numeric `X.Y.Z`)?
   - Should this be a **beta** release?

**Until the user confirms: no file edits, no commit, no tag, no push.** If they decline or say no → abort entirely.

**Beta default:** confirmation without an explicit beta yes (`beta`, `yes beta`, `make it beta`, etc.) is a **stable** (non-beta) release. Only treat as beta when they clearly opt in.

## Phase 2 — After confirmation

Use the confirmed numeric version (proposed, or the override they gave). Apply the beta default above.

### Beta vs stable

- **Stable (default):** tag `vX.Y.Z`
- **Beta (explicit only):** tag `vX.Y.Z-beta.N` where `N` is one greater than the highest existing `vX.Y.Z-beta.*` tag for that same `X.Y.Z`, or `1` if none. `MARKETING_VERSION` stays **numeric** `X.Y.Z` only — beta lives on the **tag** (and Sparkle channel), not in the plist marketing string.

### Update macOS marketing version only

In `Metagraf.xcodeproj/project.pbxproj`, set `MARKETING_VERSION` on the **Metagraf** target Debug + Release configs only (configs that include macOS / `de.dzwei.apps.metagraf`).

**Never** change:

- `MetagrafKeyboard` configs / `de.dzwei.apps.metagraf.keyboard`
- `CURRENT_PROJECT_VERSION`
- iOS-only packaging beyond what sharing the Metagraf target already implies for the release path

### Commit, tag, push together

1. Commit with Conventional Commits, e.g. `chore: bump marketing version to X.Y.Z` (beta note optional in body).
2. Create an **annotated** tag on that commit:
   - Stable: `git tag -a "vX.Y.Z" -m "Metagraf X.Y.Z"`
   - Beta: `git tag -a "vX.Y.Z-beta.N" -m "Metagraf X.Y.Z-beta.N"`
3. Push **commit and tag together** (do not push the commit alone first):
   - `git push origin main` and `git push origin <tag>` in the same step sequence, or equivalent that publishes both without leaving a tag-less push as the only action.

That push triggers the full release pipeline (Xcode Cloud + GitHub Actions). Do not invent extra release steps.

## Phase 3 — Offer pipeline babysitting

After a successful push, ask at the **very end**:

> Should I babysit the release pipeline?

- If **no** / silence / anything other than a clear yes → stop. Do not monitor further.
- If **yes** → babysit until published or clearly blocked (see below). Do not start babysitting before they answer.

### Babysit checklist

Monitor both **GitHub Actions → Release Metagraf** (for the pushed tag) and **Xcode Cloud → Mac Release**. Report concise status updates; dig into logs on failure.

Success criteria (`Docs/ReleaseWorkflow.md`):

1. GitHub creates a draft Release, then publishes after notarization / Sparkle / upload succeed
2. Release ZIP + checksum exist on the GitHub Release
3. `https://benjamin-kraatz.github.io/metagraf/appcast.xml` includes the new release

On failure, summarize the failing job/step and the recovery hint from the workflow doc (rerun vs fix-on-main vs Xcode Cloud). **Never** move or recreate the tag.

Use `gh` for Actions/release status; check the appcast URL for publication. Prefer Xcode MCP / App Store Connect tooling when available for Xcode Cloud; otherwise report what you can see and what needs a human look.

## Abort rules

- Not on `main` → deny
- Dirty working tree → deny
- User does not confirm → abort, zero changes
- Never move/recreate an existing published tag
- Never force-push
