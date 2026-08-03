# Metagraf — Agent Notes

Local-first dictation app for **macOS** and **iOS** (Swift / SwiftUI). Shared logic lives in `Packages/MetagrafCore`; platform UI in `Metagraf/`, iOS keyboard in `MetagrafKeyboard/`.

**Primary target is macOS.** iOS code exists, but do not integrate iOS into the release pipeline yet.

## Layout

| Path | Purpose |
|------|---------|
| `Metagraf/` | App targets (macOS + iOS) |
| `MetagrafKeyboard/` | iOS keyboard extension (links `MetagrafCore` only — not WhisperKit) |
| `Packages/MetagrafCore/` | Shared package: `MetagrafCore` + `Whisper`-backed `MetagrafWhisper` |
| `MetagrafSmokeTests/` | Smoke tests |
| `Scripts/` | Release / Sparkle tooling (Python + shell) |
| `Docs/` | Release setup & workflow |
| `Config/` | Entitlements / Info.plist |

Open `Metagraf.xcodeproj`. Test plan: `Metagraf.xctestplan`.

## Tooling

- **Xcode MCP first**: Prefer Xcode MCP tools over `xcodebuild` / `xcrun` / other CLI whenever the MCP can do the job (build, test, navigate, etc.). Fall back to CLI only when MCP is unavailable or insufficient.
- Swift tools version **6.2**; platforms target macOS/iOS 26.
- Releases (macOS only for now): tag → Xcode Cloud → Sparkle; see `Docs/ReleaseWorkflow.md` and `Docs/ReleaseSetup.md`. Do not invent release steps — follow those docs.

## Git & commits

- **ALWAYS use [Conventional Commits](https://www.conventionalcommits.org/)**: prepend with `feat`, `fix`, `chore`, `ci`, `docs`, `refactor`, `test`, etc.
  - Examples: `feat: add hold-to-talk timeout`, `fix: correct pasteboard restore on cancel`, `chore: bump WhisperKit`
- Only commit when the user asks. Never commit secrets (`.env`, keys, credentials).

## Code guidance

- Organize new files into folders by feature/area; avoid dumping everything into a flat directory.
- Prefer smaller, focused files over a few giant ones.
- Add SwiftUI `#Preview`s whenever there is no good reason not to.
- Keep keyboard extension lean: no WhisperKit / heavy ML in `MetagrafKeyboard` or the `MetagrafCore` target it links.
- Match existing Swift style; prefer small, focused changes.
- Prefer package unit tests under `Packages/MetagrafCore/Tests` for shared logic.
