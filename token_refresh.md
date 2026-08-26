# Token Refresh

Four separate credentials, refreshed on different schedules. Do them in this
order when picking the project back up — each is only needed for certain
follow-on steps.

## 1. Snowflake PATs (`HORIZON_PAT`, `HORIZON_LOAD_PAT`) — rarely, ~monthly

Everything else derives from these. Only touch this if they've actually expired.

Check current status:
```bash
snow sql -c <your-snow-cli-connection> -q "SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER HORIZON_SVC;" --format json
```
or using the default profile:
```bash
snow sql -q "SHOW USER PROGRAMMATIC ACCESS TOKENS FOR USER HORIZON_SVC;" --format json
```

Look at `expires_at` / `status`. `<your-snow-cli-connection>` is whatever connection name
you've defined in your own `~/.snowflake/config.toml` — see `tf/snowflake/providers.tf`
for the related quirks around `default_connection_name`.

**An empty `[]` result is not "nothing to do" — treat it the same as expired.**
Once a PAT's `DAYS_TO_EXPIRY` passes, Snowflake drops it from this list entirely
instead of showing an expired row, so there's nothing to read `expires_at` off
of. This has already happened twice (7-day, then 30-day expiry). `sql/issue_pat.sql`
now issues both with `DAYS_TO_EXPIRY=360` to make this rare going forward — but
that only takes effect once you actually run the `ADD PAT` statements below;
editing the `.sql` file alone doesn't rotate anything.

If expired (or `[]`), re-issue both — see `sql/issue_pat.sql` for the canonical
commands. Each secret is shown **once** — paste it straight into `.env` as
`HORIZON_LOAD_PAT=` / `HORIZON_PAT=`, never into a log or terminal history you'll
keep. If a PAT of the same name somehow still exists server-side, `ADD PAT` will
error — `REMOVE PAT` it first (commands are in the file's header comment).

## 2. `HORIZON_TOKEN` — every session, ~60 min

The actual bearer token dbt/DuckDB use, exchanged from `HORIZON_PAT`. It's
never stored on disk — mint a fresh one at the start of every session, and
again if the session runs past ~60 minutes:

```bash
source refresh_token.sh
```
Run from anywhere inside the repo (it walks up to find `.env`). Must be
`source`d, not executed, so `HORIZON_TOKEN` lands in your current shell.

Needed before: `dbt run` / `dbt build`, anything in `motherduck/explore.sql`.

## 3. AWS SSO (`<your-aws-sso-profile>` profile) — every ~8-12h, only for Terraform or local dlt runs

Not needed for dbt/DuckDB reads — those use Horizon-vended S3 credentials via
the bearer token from step 2. Needed for:
- `terraform` in `tf/aws` or `tf/snowflake`
- running `dlt/hello_world_pipeline.py` locally (dlt's own bookkeeping writes
  use this profile, separate from Horizon's vended creds)

```bash
aws sso login --profile <your-aws-sso-profile>
```
Opens a browser. Check if you still have a session:
```bash
aws sts get-caller-identity --profile <your-aws-sso-profile>
```

## 4. dltHub platform login — only for deploying/scheduling on dltHub SaaS

Unrelated to the Snowflake side — skip this if you're just running things
locally.

```bash
cd dlt
dlthub login            # or: dlthub login --device   (SSH/remote, no local browser)
```
If it fails first with an outdated-CLI error (HTTP 426), upgrade before
logging in:
```bash
uv sync --upgrade-package dlthub-client --upgrade-package dlthub
```

## Typical "coming back after a while" session

```bash
source refresh_token.sh          # always
aws sso login --profile <your-aws-sso-profile>     # only if running dlt or terraform
cd dlt && dlthub login           # only if deploying to dltHub
```
If step 2 itself fails (not just times out later), the PAT has expired —
go back to step 1.

## Troubleshooting: error → cause → fix

| Error | Cause | Fix |
|---|---|---|
| `refresh_token.sh` prints `HORIZON_TOKEN NOT set -- token exchange failed` (with the raw error body, e.g. `unauthorized_client`), or 401 on `/polaris/api/catalog/v1/config` | `HORIZON_PAT` / `HORIZON_LOAD_PAT` itself expired or was removed | Step 1 |
| `refresh_token.sh` traceback (`KeyError: 'access_token'`) and/or `HORIZON_TOKEN exported (len 0, ...)` | Old script version — swallowed the exchange failure and exported an empty token instead of failing. Update to the current script (fails loudly, doesn't export on error) | Step 1, then re-`source` |
| `dbt build` fails with `env var HORIZON_TOKEN not found` | Forgot to `source refresh_token.sh` this session | Step 2 |
| DuckDB/dbt error partway through a long session | `HORIZON_TOKEN` expired mid-session (60 min TTL) | Step 2 (re-source) |
| `aws: Token has expired and refresh failed` | AWS SSO session expired | Step 3 |
| `dlthub` command fails with "Login failed... outdated" (HTTP 426) | CLI version too old | Upgrade, then step 4 |
| `dlthub workspace info` hangs / prints a browser URL and waits | Not logged in to the dltHub platform | Step 4 |
