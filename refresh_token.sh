#!/usr/bin/env bash
# Mint a short-lived (60 min) Horizon access token for the TRANSFORMER role and
# export it as HORIZON_TOKEN. DuckDB's own OAuth2 flow hits the wrong endpoint
# (singular /v1/oauth/token -> 404 on Snowflake Polaris), so we do the exchange
# ourselves and hand DuckDB a pre-vended bearer token.
#
# Usage:   source refresh_token.sh
# then launch the notebook in the SAME shell:   duckdb -ui
# NOTE: meant to be `source`d, so no `set -e` (it would kill your interactive shell).
# Find .env by walking up from the current directory (works in bash and zsh, sourced or run).
_dir="$PWD"
while [ "$_dir" != "/" ] && [ ! -f "$_dir/.env" ]; do _dir="$(dirname "$_dir")"; done
if [ ! -f "$_dir/.env" ]; then echo "could not find .env (run from inside the project)"; return 1 2>/dev/null || exit 1; fi

PAT="$(grep -E '^HORIZON_PAT=' "$_dir/.env" | cut -d= -f2-)"   # TRANSFORMER-restricted PAT
CAT_URI="$(grep -E '^HORIZON_CATALOG_URI=' "$_dir/.env" | cut -d= -f2-)"
URI="${CAT_URI}/v1/oauth/tokens"

HORIZON_TOKEN="$(curl -s -X POST "$URI" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_secret=$PAT" \
  --data-urlencode "scope=session:role:TRANSFORMER" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["access_token"])')"

export HORIZON_TOKEN
echo "HORIZON_TOKEN exported (len ${#HORIZON_TOKEN}, valid ~60 min)."
