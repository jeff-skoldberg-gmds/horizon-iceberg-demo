#!/usr/bin/env bash
# Mint a short-lived Horizon access token for the TRANSFORMER role and export it
# as HORIZON_TOKEN. DuckDB's own OAuth2 flow hits the wrong endpoint, so we do
# the exchange ourselves.
#
# Usage: source refresh_token.sh, then launch in the SAME shell: duckdb -ui
# No `set -e` -- this is meant to be sourced into an interactive shell.
_dir="$PWD"
while [ "$_dir" != "/" ] && [ ! -f "$_dir/.env" ]; do _dir="$(dirname "$_dir")"; done
if [ ! -f "$_dir/.env" ]; then echo "could not find .env (run from inside the project)"; return 1 2>/dev/null || exit 1; fi

PAT="$(grep -E '^HORIZON_PAT=' "$_dir/.env" | cut -d= -f2-)"   # TRANSFORMER-restricted PAT
CAT_URI="$(grep -E '^HORIZON_CATALOG_URI=' "$_dir/.env" | cut -d= -f2-)"
URI="${CAT_URI}/v1/oauth/tokens"

_resp="$(curl -s -X POST "$URI" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_secret=$PAT" \
  --data-urlencode "scope=session:role:TRANSFORMER")"

_token="$(printf '%s' "$_resp" | python3 -c 'import sys,json
try:
    print(json.load(sys.stdin)["access_token"])
except Exception:
    sys.exit(1)' 2>/dev/null)"

if [ -z "$_token" ]; then
  echo "HORIZON_TOKEN NOT set -- token exchange failed. Response from $URI:" >&2
  echo "  $_resp" >&2
  echo "This almost always means HORIZON_PAT has expired or been removed." >&2
  echo "Check with: snow sql -q \"SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER HORIZON_SVC;\" --format json" >&2
  echo "An empty [] result means both PATs are gone, not just expired -- see token_refresh.md step 1." >&2
  unset HORIZON_TOKEN
  unset _resp _token
  return 1 2>/dev/null || exit 1
fi

HORIZON_TOKEN="$_token"
export HORIZON_TOKEN
unset _resp _token
echo "HORIZON_TOKEN exported (len ${#HORIZON_TOKEN}, valid ~60 min)."
