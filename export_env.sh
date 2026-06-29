#!/usr/bin/env bash
# Export all vars from .env into the current shell.
# Usage:  source export_env.sh
_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
set -a
# shellcheck disable=SC1091
. "$_root/.env"
set +a

# HORIZON_TOKEN is NOT in .env: it's a ~60-min OAuth bearer exchanged from
# HORIZON_PAT (DuckDB/dbt need the vended token, not the raw PAT). Remind loudly
# so `dbt build` doesn't fail later with a cryptic "env var HORIZON_TOKEN not found".
if [ -z "${HORIZON_TOKEN:-}" ]; then
  echo "note: HORIZON_TOKEN not set (dbt/DuckDB need it). Mint it with:" >&2
  echo "      source $_root/refresh_token.sh" >&2
fi
