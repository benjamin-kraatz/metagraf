#!/bin/bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    echo "usage: $0 <xcode-cloud-artifact-directory> <output-directory>" >&2
    exit 64
fi

input_dir="$1"
output_dir="$2"
manifest="$input_dir/manifest.json"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
work_dir="${RUNNER_TEMP:-$repo_root/build}/sparkle-release"
extract_dir="$work_dir/extracted"
history_dir="$work_dir/history"

[[ -f "$manifest" ]] || { echo "error: missing handoff manifest" >&2; exit 1; }
: "${SPARKLE_PRIVATE_KEY:?SPARKLE_PRIVATE_KEY is required}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY is required}"
: "${APPCAST_URL:?APPCAST_URL is required}"

tag="$(jq -r '.tag' "$manifest")"
version="$(jq -r '.version' "$manifest")"
expected_build="$(jq -r '.build' "$manifest")"
artifact_file="$(jq -r '.artifactFile' "$manifest")"
archive="$input_dir/$artifact_file"

mkdir -p "$extract_dir" "$history_dir" "$output_dir"
[[ -e "$archive" ]] || { echo "error: missing Xcode Cloud artifact $artifact_file" >&2; exit 1; }

if [[ -d "$archive" ]]; then
    cp -R "$archive" "$extract_dir/"
else
    ditto -x -k "$archive" "$extract_dir" 2>/dev/null || ditto -x "$archive" "$extract_dir"
fi

app="$(find "$extract_dir" -type d -name 'Metagraf.app' -print -quit)"
[[ -n "$app" ]] || { echo "error: Metagraf.app not found in notarized artifact" >&2; exit 1; }
info="$app/Contents/Info.plist"
executable="$app/Contents/MacOS/Metagraf"

assert_plist() {
    local key="$1" expected="$2" actual
    actual="$(/usr/libexec/PlistBuddy -c "Print :$key" "$info")"
    [[ "$actual" == "$expected" ]] || {
        echo "error: $key is '$actual', expected '$expected'" >&2
        exit 1
    }
}

assert_plist CFBundleIdentifier de.dzwei.apps.metagraf
assert_plist CFBundleShortVersionString "$version"
assert_plist CFBundleVersion "$expected_build"
assert_plist SUFeedURL "$APPCAST_URL"
assert_plist SURequireSignedFeed true
assert_plist SUVerifyUpdateBeforeExtraction true
public_key="$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' "$info")"
[[ -n "$public_key" && "$public_key" != *'$('* ]] || { echo "error: SUPublicEDKey is missing" >&2; exit 1; }

codesign --verify --deep --strict --verbose=2 "$app"
codesign -d --verbose=2 "$app" 2>&1 | grep -q 'flags=.*runtime' || { echo "error: hardened runtime is absent" >&2; exit 1; }
architectures="$(lipo -archs "$executable")"
grep -qw arm64 <<<"$architectures" && grep -qw x86_64 <<<"$architectures" || {
    echo "error: expected arm64 and x86_64, found $architectures" >&2
    exit 1
}
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"

zip_name="Metagraf-$version.zip"
zip_path="$history_dir/$zip_name"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

xcodebuild -resolvePackageDependencies \
    -project "$repo_root/Metagraf.xcodeproj" \
    -scheme Metagraf \
    -clonedSourcePackagesDirPath "$work_dir/SourcePackages" >/dev/null
sign_tool="$(find "$work_dir/SourcePackages/artifacts" -type f -path '*/Sparkle/bin/sign_update' -print -quit)"
[[ -x "$sign_tool" ]] || { echo "error: Sparkle sign_update tool not found" >&2; exit 1; }

gh api --paginate --slurp "repos/$GITHUB_REPOSITORY/releases?per_page=100" > "$work_dir/releases-raw.json"
jq '[flatten[] | {
    tagName: .tag_name,
    isDraft: .draft,
    isPrerelease: .prerelease,
    publishedAt: (.published_at // .created_at),
    notes: .body
}]' "$work_dir/releases-raw.json" > "$work_dir/releases.json"
python3 "$repo_root/Scripts/release/release_tools.py" select-history \
    --releases "$work_dir/releases.json" \
    --current-tag "$tag" \
    --output "$work_dir/selected-releases.json"

: > "$work_dir/entries.ndjson"
while IFS= read -r release; do
    release_tag="$(jq -r '.tagName' <<<"$release")"
    release_version="${release_tag#v}"
    release_channel="stable"
    jq -e '.isPrerelease' >/dev/null <<<"$release" && release_channel="beta"
    release_zip="$history_dir/Metagraf-$release_version.zip"

    if [[ "$release_tag" != "$tag" ]]; then
        gh release download "$release_tag" --repo "$GITHUB_REPOSITORY" \
            --pattern "Metagraf-$release_version.zip" --dir "$history_dir"
    fi
    [[ -f "$release_zip" ]] || { echo "error: missing ZIP for $release_tag" >&2; exit 1; }

    previous_extract="$work_dir/inspect-$release_version"
    mkdir -p "$previous_extract"
    ditto -x -k "$release_zip" "$previous_extract"
    release_app="$(find "$previous_extract" -type d -name 'Metagraf.app' -print -quit)"
    [[ -n "$release_app" ]] || { echo "error: $release_zip contains no Metagraf.app" >&2; exit 1; }
    release_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$release_app/Contents/Info.plist")"

    signature_output="$(printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sign_tool" --ed-key-file - "$release_zip")"
    signature="$(python3 -c 'import re,sys; m=re.search(r"sparkle:edSignature=\"([^\"]+)\"", sys.stdin.read()); print(m.group(1) if m else "")' <<<"$signature_output")"
    length="$(stat -f '%z' "$release_zip")"
    [[ -n "$signature" ]] || { echo "error: Sparkle did not sign $release_zip" >&2; exit 1; }

    jq -cn \
        --arg version "$release_version" \
        --arg build "$release_build" \
        --arg channel "$release_channel" \
        --arg publishedAt "$(jq -r '.publishedAt' <<<"$release")" \
        --arg notes "$(jq -r '.notes // "Keine Versionshinweise."' <<<"$release")" \
        --arg url "https://github.com/$GITHUB_REPOSITORY/releases/download/$release_tag/Metagraf-$release_version.zip" \
        --arg signature "$signature" \
        --arg length "$length" \
        '{version:$version,build:($build|tonumber),channel:$channel,publishedAt:$publishedAt,notes:$notes,url:$url,signature:$signature,length:($length|tonumber)}' \
        >> "$work_dir/entries.ndjson"
done < <(jq -c '.[]' "$work_dir/selected-releases.json")

jq -s 'sort_by(.build) | reverse' "$work_dir/entries.ndjson" > "$work_dir/entries.json"
python3 "$repo_root/Scripts/release/release_tools.py" build-appcast \
    --entries "$work_dir/entries.json" \
    --output "$output_dir/appcast.xml"
python3 "$repo_root/Scripts/release/release_tools.py" validate-appcast \
    --entries "$work_dir/entries.json" --appcast "$output_dir/appcast.xml"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sign_tool" --ed-key-file - "$output_dir/appcast.xml"
printf '%s\n' "$SPARKLE_PRIVATE_KEY" | "$sign_tool" --ed-key-file - --verify "$output_dir/appcast.xml"
python3 "$repo_root/Scripts/release/release_tools.py" validate-appcast \
    --entries "$work_dir/entries.json" --appcast "$output_dir/appcast.xml"

cp "$zip_path" "$output_dir/$zip_name"
(cd "$output_dir" && shasum -a 256 "$zip_name" > "$zip_name.sha256")
appcast_sha="$(shasum -a 256 "$output_dir/appcast.xml" | awk '{print $1}')"
jq \
    --arg zipFile "$zip_name" \
    --arg checksumFile "$zip_name.sha256" \
    --arg appcastSha256 "$appcast_sha" \
    '. + {zipFile:$zipFile,checksumFile:$checksumFile,appcastFile:"appcast.xml",appcastSha256:$appcastSha256}' \
    "$manifest" > "$output_dir/manifest.json"
