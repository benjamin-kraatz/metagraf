#!/bin/bash
set -euo pipefail
set +x

if [[ $# -ne 1 ]]; then
    echo "usage: $0 <App Store Connect Apple ID>" >&2
    exit 64
fi

app_id="$1"
[[ "$app_id" =~ ^[0-9]+$ ]] || { echo "error: Apple ID must be numeric" >&2; exit 64; }

: "${ASC_ISSUER_ID:?ASC_ISSUER_ID is required}"
: "${ASC_KEY_ID:?ASC_KEY_ID is required}"
: "${ASC_PRIVATE_KEY:?ASC_PRIVATE_KEY is required}"

for command in curl jq openssl xxd; do
    command -v "$command" >/dev/null || { echo "error: $command is required" >&2; exit 1; }
done

base64url() {
    openssl base64 -A | tr '+/' '-_' | tr -d '='
}

pad_integer() {
    local value="$1"
    while (( ${#value} > 64 )); do
        value="${value:2}"
    done
    printf '%064s' "$value" | tr ' ' 0
}

now="$(date +%s)"
expires="$((now + 900))"
header="$(jq -cn --arg kid "$ASC_KEY_ID" '{alg:"ES256",kid:$kid,typ:"JWT"}' | base64url)"
payload="$(jq -cn --arg issuer "$ASC_ISSUER_ID" --argjson issued "$now" --argjson expires "$expires" \
    '{iss:$issuer,iat:$issued,exp:$expires,aud:"appstoreconnect-v1"}' | base64url)"
signing_input="$header.$payload"
private_key="${ASC_PRIVATE_KEY//\\n/$'\n'}"

integers="$(
    printf '%s' "$signing_input" \
        | openssl dgst -sha256 -sign <(printf '%s\n' "$private_key") \
        | openssl asn1parse -inform DER -in /dev/stdin 2>/dev/null \
        | awk -F: '/prim: INTEGER/{gsub(/[[:space:]]/, "", $NF); print $NF}'
)"
r="$(printf '%s\n' "$integers" | sed -n '1p')"
s="$(printf '%s\n' "$integers" | sed -n '2p')"
[[ -n "$r" && -n "$s" ]] || { echo "error: failed to create App Store Connect JWT" >&2; exit 1; }
signature="$(printf '%s%s' "$(pad_integer "$r")" "$(pad_integer "$s")" | xxd -r -p | base64url)"
jwt="$signing_input.$signature"

api="https://api.appstoreconnect.apple.com/v1"
product="$(curl --fail --silent --show-error \
    -H "Authorization: Bearer $jwt" -H 'Accept: application/json' \
    "$api/apps/$app_id/ciProduct")"
product_id="$(jq -er '.data.id' <<<"$product")"

workflows="$(curl --fail --silent --show-error \
    -H "Authorization: Bearer $jwt" -H 'Accept: application/json' \
    "$api/ciProducts/$product_id/workflows?limit=200&fields%5BciWorkflows%5D=name")"

printf 'APP_STORE_CONNECT_APP_ID=%s\n' "$app_id"
printf 'XCODE_CLOUD_PRODUCT_ID=%s\n' "$product_id"
jq -r '.data[] | "XCODE_CLOUD_WORKFLOW_ID=\(.id)  # \(.attributes.name // "unnamed")"' <<<"$workflows"
