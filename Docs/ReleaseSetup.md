# One-time release setup

Complete this checklist before pushing the first release tag.

## Apple accounts and identifiers

- [ ] The Apple Developer membership for team `U7H5KA9MG4` is active and agreements are current.
- [ ] The operator has App Manager or Admin access in App Store Connect.
- [ ] Bundle IDs `de.dzwei.apps.metagraf` and `de.dzwei.apps.metagraf.keyboard` exist.
- [ ] App Group `group.de.dzwei.apps.metagraf` exists and is attached where required.
- [ ] An App Store Connect record named Metagraf exists for `de.dzwei.apps.metagraf`.

## App Store Connect API key

1. In **Users and Access → Integrations → App Store Connect API**, create a team key for release automation with the Developer role.
2. Download the `.p8` once and back it up in the team password manager.
3. Record its issuer ID and key ID.
4. Add GitHub encrypted secrets:
   - `ASC_ISSUER_ID`
   - `ASC_KEY_ID`
   - `ASC_PRIVATE_KEY` containing the full PEM `.p8` text

The same key reads Xcode Cloud build status and short-lived artifact download URLs. Do not commit or base64-wrap the PEM unless the workflow is changed accordingly.

## Sparkle signing key

After resolving the Sparkle package, locate `generate_keys` in the package artifact’s `Sparkle/bin` directory.

1. Run `generate_keys` on a trusted Mac.
2. Export the private key with its supported `-x` option and back it up securely.
3. Add the exported base64 key as GitHub secret `SPARKLE_PRIVATE_KEY`.
4. Add the printed public key to the Xcode Cloud `Mac Release` environment as `SPARKLE_PUBLIC_ED_KEY`.
5. Mark the private value secret/redacted. The public key does not need secrecy.

Losing the Sparkle key complicates feed signing and key rotation. Keep at least one encrypted offline backup.

## Xcode Cloud

1. Connect the Metagraf App Store Connect product to `benjamin-kraatz/metagraf`.
2. Create or edit **Mac Release**:
   - Start condition: **Tag Changes**, matching `v*`.
   - Auto-cancel: off.
   - Editing: restricted.
   - Environment: clean build with the stable Xcode version used by the project.
   - Action: Archive, platform macOS, scheme Metagraf, destination Any Mac.
   - Post-action: Notarize the macOS archive produced by the Archive action.
3. Do not configure a manual-only tag condition and do not add a second tag workflow.
4. Add `SPARKLE_PUBLIC_ED_KEY` to the workflow environment.
5. Copy the workflow, product, and app IDs from App Store Connect/API for the repository variables below.

The App Store Connect API cannot choose a tag when starting a build. For that reason, **Tag Changes `v*` is the one and only Xcode Cloud trigger**; GitHub correlates and reuses that build instead of starting a second one.

The checked-in `ci_pre_xcodebuild.sh` validates the tag and uses `agvtool` to set the marketing/build versions before Xcode archives.

## GitHub repository

- [ ] Under **Settings → Pages**, select **GitHub Actions** as the deployment source.
- [ ] Under **Settings → Actions → General**, allow GitHub Actions to create and update Releases.
- [ ] Add repository variables:
  - `XCODE_CLOUD_WORKFLOW_ID`: opaque ID of **Mac Release**.
  - `XCODE_CLOUD_PRODUCT_ID`: opaque Xcode Cloud product ID.
  - `APP_STORE_CONNECT_APP_ID`: numeric App Store Connect app ID.
  - `REPOSITORY_IDENTITY`: exactly `benjamin-kraatz/metagraf`.
  - `APPCAST_URL`: exactly `https://benjamin-kraatz.github.io/metagraf/appcast.xml`.
- [ ] Add encrypted secrets `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_PRIVATE_KEY`, and `SPARKLE_PRIVATE_KEY`.
- [ ] Ensure the `github-pages` environment permits the release workflow to deploy without a manual approval, because releases publish automatically.
- [ ] Keep workflow permissions at `contents: write`, `pages: write`, `id-token: write`, and `actions: read`.
- [ ] Protect `main` with the normal macOS CI check before enabling production releases.

## First release rehearsal

1. Push a disposable beta tag such as `v0.0.2-beta.1` from a commit on `main`.
2. Confirm Xcode Cloud and GitHub Actions select the same full commit SHA.
3. Confirm the draft remains private until the notarized artifact and Sparkle files are ready.
4. Download the public ZIP on a clean Mac, extract it, and verify Gatekeeper accepts Metagraf.
5. Install an older signed build and test both stable-only and beta-enabled Sparkle updates.
6. Confirm the public appcast exactly matches the `appcast.xml` attached to the Release.

Review API-key expiry, Sparkle-key backups, Xcode Cloud access, GitHub environment access, and maintainer membership at least twice a year and whenever someone joins or leaves the release team.
