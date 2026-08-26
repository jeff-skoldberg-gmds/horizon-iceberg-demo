#!/usr/bin/env bash
# Export all vars from .env into the current shell.
# Usage:  source export_env.sh
_root="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
set -a
# shellcheck disable=SC1091
. "$_root/.env"
set +a

# HORIZON_TOKEN isn't in .env -- it's a short-lived OAuth token, minted separately.
if [ -z "${HORIZON_TOKEN:-}" ]; then
  echo "note: HORIZON_TOKEN not set (dbt/DuckDB need it). Mint it with:" >&2
  echo "      source $_root/refresh_token.sh" >&2
fi
