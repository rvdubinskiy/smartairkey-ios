#!/usr/bin/env bash
#
# Exchanges the COMPANY SAS-TOKEN for a per-SUBSCRIBER mobile token.
#
# Per the SmartAirKey SDK docs the mobile API (/api/mobile) is authorized with
# the subscriber's `apiKeyId:token` — NOT the company SAS-TOKEN. You obtain the
# subscriber token from the company token + the subscriber's phone number:
#
#   GET /api/service/company/GetUserToken   body {"PhoneNumber":"+7..."}
#   Authorization: SAS-TOKEN <companyKeyId:companySecret>
#   -> { "apiKeyId": "...", "token": "..." }
#
# The printed "apiKeyId:token" is what you paste into SAK_SAS_TOKEN (or
# AppConfig.developerAccessToken) to test the app on device.
#
# Usage:
#   scripts/get_user_token.sh 'COMPANY_KEYID:COMPANY_SECRET' '+7XXXXXXXXXX' [baseURL]
#
# Env: METHOD=GET|POST (default GET, per docs). Requires curl.
set -euo pipefail

SAS="${1:?usage: $0 'COMPANY_KEYID:COMPANY_SECRET' '+7XXXXXXXXXX' [baseURL]}"
PHONE="${2:?subscriber phone, e.g. +79161500159}"
BASE="${3:-https://apidev.smartairkey.com}"
METHOD="${METHOD:-GET}"

# UTC timestamp with milliseconds + Z, matching the docs.
TS="$(date -u +%Y-%m-%dT%H:%M:%S).000Z"
URL="${BASE}/api/service/company/GetUserToken"

echo "→ $METHOD $URL  phone=$PHONE  ts=$TS" >&2
resp="$(curl -sS -X "$METHOD" "$URL" \
  -H "Authorization: SAS-TOKEN ${SAS}" \
  -H "Content-Type: application/json" \
  -H "Timestamp: ${TS}" \
  --data "{\"PhoneNumber\":\"${PHONE}\"}")"

echo "← $resp" >&2

api="$(printf '%s' "$resp" | sed -n 's/.*"apiKeyId"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
tok="$(printf '%s' "$resp" | sed -n 's/.*"token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [[ -n "$api" && -n "$tok" ]]; then
  echo >&2
  echo "Subscriber SAS-TOKEN (use as SAK_SAS_TOKEN / developerAccessToken):" >&2
  echo "${api}:${tok}"
else
  echo "!! Could not parse apiKeyId/token — see response above." >&2
  echo "   If it's a 401/method error, try METHOD=POST or check the base URL/env." >&2
  exit 1
fi
