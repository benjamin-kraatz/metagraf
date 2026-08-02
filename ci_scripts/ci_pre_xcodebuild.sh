#!/bin/bash
set -euo pipefail

# Only tag-triggered release archives need CI-owned versions. Branch/PR builds
# retain the checked-in development version.
if [[ -z "${CI_TAG:-}" ]]; then
    exit 0
fi

if [[ ! "$CI_TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-beta\.[0-9]+)?$ ]]; then
    echo "error: unsupported release tag $CI_TAG" >&2
    exit 1
fi

: "${CI_BUILD_NUMBER:?CI_BUILD_NUMBER is required for release builds}"
: "${CI_PRIMARY_REPOSITORY_PATH:?CI_PRIMARY_REPOSITORY_PATH is required}"
: "${SPARKLE_PUBLIC_ED_KEY:?SPARKLE_PUBLIC_ED_KEY must be configured in Xcode Cloud}"

version="${CI_TAG#v}"
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcrun agvtool new-marketing-version "$version"
xcrun agvtool new-version -all "$CI_BUILD_NUMBER"
