#!/usr/bin/env bash
#
# Probes SmartAirKey mobile-API request signing (SAS-TOKEN).
#
# The mobile API does NOT accept the raw "KeyId:Secret" token — it expects a
# per-request signature (HMAC-SHA256) computed with the Secret. The exact
# "string to sign" is deployment-specific, so this script tries the most likely
# variants and reports which one the server accepts (HTTP 200).
#
# Usage:
#   scripts/probe_sas_signature.sh 'KEYID' 'SECRET'
#   scripts/probe_sas_signature.sh 'KEYID' 'SECRET' --dry-run   # print, don't send
#
# Requires: bash, openssl, curl. Once a variant returns 200, tell which STS#
# (and sig encoding / timestamp format) worked and it'll be baked into
# SmartAirKeyBackendClient.
set -u

KEYID="${1:-}"
SECRET="${2:-}"
MODE="${3:-send}"
if [[ -z "$KEYID" || -z "$SECRET" ]]; then
  echo "usage: $0 'KEYID' 'SECRET' [--dry-run]" >&2
  exit 2
fi

HOST="api.smartairkey.com"
METHOD="GET"
PATH_ONLY="/api/mobile"
QUERY="Action=GetUserProfileV2"
PATHQ="${PATH_ONLY}?${QUERY}"
URL="https://${HOST}${PATHQ}"

# Two timestamp formats seen in the wild (with/without trailing Z).
TS_Z="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
TS_NOZ="$(date -u +%Y-%m-%dT%H:%M:%S.000)"

hmac_b64() { printf '%b' "$1" | openssl dgst -sha256 -hmac "$SECRET" -binary | openssl base64 -A; }
hmac_hex() { printf '%b' "$1" | openssl dgst -sha256 -hmac "$SECRET" -r | awk '{print $1}'; }

# Candidate "string to sign" formulas. \n are real newlines via printf %b.
declare -a LABELS=(
  "V1 METHOD\\nPATHQ\\nTS"
  "V2 TS\\nMETHOD\\nPATHQ"
  "V3 TS"
  "V4 METHOD+PATHQ+TS"
  "V5 KEYID\\nTS\\nMETHOD\\nPATHQ"
  "V6 METHOD\\nPATH\\nTS"
  "V7 TS+PATHQ"
  "V8 PATHQ\\nTS"
)
build_sts() { # $1 = variant index, $2 = timestamp
  local ts="$2"
  case "$1" in
    0) printf '%s\n%s\n%s' "$METHOD" "$PATHQ" "$ts" ;;
    1) printf '%s\n%s\n%s' "$ts" "$METHOD" "$PATHQ" ;;
    2) printf '%s' "$ts" ;;
    3) printf '%s%s%s' "$METHOD" "$PATHQ" "$ts" ;;
    4) printf '%s\n%s\n%s\n%s' "$KEYID" "$ts" "$METHOD" "$PATHQ" ;;
    5) printf '%s\n%s\n%s' "$METHOD" "$PATH_ONLY" "$ts" ;;
    6) printf '%s%s' "$ts" "$PATHQ" ;;
    7) printf '%s\n%s' "$PATHQ" "$ts" ;;
  esac
}

echo "URL: $URL"
echo "KeyId: ${KEYID:0:6}… (len ${#KEYID})   Secret: len ${#SECRET}"
echo

try() { # $1 label, $2 sts, $3 sig, $4 ts, $5 enc
  local hdr="SAS-TOKEN ${KEYID}:${3}"
  if [[ "$MODE" == "--dry-run" ]]; then
    printf '%-28s enc=%-4s ts=%s\n    STS=%q\n    sig=%s\n' "$1" "$5" "$4" "$2" "$3"
    return
  fi
  local code
  code=$(curl -s -o /tmp/sas_body.$$ -w '%{http_code}' "$URL" \
    -H "Authorization: ${hdr}" \
    -H "Content-Type: application/json" \
    -H "Timestamp: ${4}")
  if [[ "$code" == "200" ]]; then
    printf '  >>> HTTP 200  %-28s enc=%-4s ts=%s   <<< WORKS\n' "$1" "$5" "$4"
  else
    printf '      HTTP %-4s %-28s enc=%-4s ts=%s\n' "$code" "$1" "$5" "$4"
  fi
}

for i in "${!LABELS[@]}"; do
  for ts in "$TS_Z" "$TS_NOZ"; do
    sts="$(build_sts "$i" "$ts")"
    try "${LABELS[$i]}" "$sts" "$(hmac_b64 "$sts")" "$ts" "b64"
    try "${LABELS[$i]}" "$sts" "$(hmac_hex "$sts")" "$ts" "hex"
  done
done

echo
echo "If nothing returned 200: the header format or key encoding differs."
echo "Best source of truth — open the SmartAirKey web app in a browser,"
echo "DevTools ▸ Network ▸ a real request ▸ copy the 'Authorization' and"
echo "'Timestamp' headers, and share them so the exact scheme can be matched."
rm -f /tmp/sas_body.$$ 2>/dev/null || true
