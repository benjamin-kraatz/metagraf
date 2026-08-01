#!/bin/bash
#
# Builds, signs, notarizes, and staples a distributable Metagraf.app.
#
# Metagraf runs unsandboxed — Accessibility is unavailable to sandboxed apps —
# so it ships outside the Mac App Store and must be notarized, or Gatekeeper
# will refuse to open it on anyone else's Mac.
#
# Requires a notarytool keychain profile. Create one once with:
#
#   xcrun notarytool store-credentials Metagraf \
#       --apple-id "you@example.com" \
#       --team-id U7H5KA9MG4 \
#       --password "app-specific-password"
#
# Usage: Scripts/release.sh [notary-profile]

set -euo pipefail

PROFILE="${1:-Metagraf}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/build/release"
ARCHIVE="$BUILD/Metagraf.xcarchive"
EXPORT="$BUILD/export"
IDENTITY="Developer ID Application"

cd "$ROOT"
rm -rf "$BUILD"
mkdir -p "$BUILD"

echo "==> Archiving"
xcodebuild archive \
    -scheme Metagraf \
    -destination 'generic/platform=macOS' \
    -archivePath "$ARCHIVE" \
    -derivedDataPath "$BUILD/DerivedData" \
    CODE_SIGN_IDENTITY="$IDENTITY" \
    CODE_SIGN_STYLE=Manual \
    | grep -E "error:|warning:.*\.swift|BUILD" || true

cat > "$BUILD/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>U7H5KA9MG4</string>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
PLIST

echo "==> Exporting"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT" \
    -exportOptionsPlist "$BUILD/ExportOptions.plist"

APP="$EXPORT/Metagraf.app"

echo "==> Verifying signature and hardened runtime"
codesign --verify --deep --strict --verbose=2 "$APP"
# Notarization is rejected without the hardened runtime, so fail early and
# clearly rather than after the upload.
codesign -d --verbose=2 "$APP" 2>&1 | grep -q "flags=.*runtime" \
    || { echo "error: hardened runtime is not enabled"; exit 1; }

echo "==> Notarizing (this uploads the app to Apple)"
ZIP="$BUILD/Metagraf.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --keychain-profile "$PROFILE" --wait

echo "==> Stapling"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"

echo "==> Packaging"
DMG="$BUILD/Metagraf.dmg"
hdiutil create -volname Metagraf -srcfolder "$APP" -ov -format UDZO "$DMG"

echo
echo "Done: $DMG"
echo "Gatekeeper check:"
spctl --assess --type execute --verbose=2 "$APP"
