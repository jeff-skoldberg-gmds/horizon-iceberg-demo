# dbt (Fusion) — TRANSFORMER half

dbt **Fusion** (dbt Core v2) + its bundled DuckDB as the TRANSFORMER: read the dlt-landed
Iceberg data from `ICE_RAW.LANDING` and **persist a staging model into `ICE_TRANSFORMED`**
via the Snowflake Horizon Iceberg REST catalog — **no Snowflake compute, fully native**.

- **Read** — Fusion attaches the Horizon REST catalog (`ice_raw`, catalogs.yml) and runs the staging SQL.
- **Write** — a stock `+materialized: table` bound via `+catalog_name: ice_transformed` writes the
  result as a Snowflake-managed Iceberg table — **DuckDB itself commits to Horizon**. No pyiceberg,
  no parquet round-trip, no custom materialization. Needs Fusion **preview.194+** (which exposes the
  four [duckdb-iceberg#1017](https://github.com/duckdb/duckdb-iceberg/pull/1017) Horizon write-compat
  ATTACH options in catalogs.yml v2). See [NOTES_horizon_write_path.md](NOTES_horizon_write_path.md).

## Layout

| Path | Purpose |
| --- | --- |
| `catalogs.yml` | catalogs.yml v2 — `ice_raw` (read) + `ice_transformed` (write, with the four write-compat options). |
| `dbt_project.yml` | `flags: use_catalogs_v2: true`; per-folder `+catalog_name: ice_transformed` + `+schema:` (`staging`, `marts`). |
| `profiles.yml` | DuckDB target: `iceberg` extension + the `horizon` ICEBERG secret (pre-minted bearer) the catalogs reference. Default `schema: STAGING`. |
| `macros/generate_schema_name.sql` | Override so `+schema:` is used **verbatim** — no `<profile_schema>_<custom>` prefixing (see Schemas below). |
| `models/staging/stg_hello_world.sql` | The staging model — thin transform over `ice_raw.LANDING.HELLO_WORLD`. |
| `models/staging/_staging__sources.yml` | Source definition for the raw landing table. |
| `NOTES_horizon_write_path.md` | How DuckDB writes Iceberg to Horizon natively, the four options, version history, and the fallback. |
| `*.duckdb.yml`, `macros-duckdb/` | **Fallback** for stock dbt-core (no Fusion) — see NOTES. |

## Schemas (Iceberg namespaces)

Models are split across two Iceberg namespaces in `ICE_TRANSFORMED`:

- `STAGING` → `stg_hello_world` (Iceberg table)
- `MARTS`   → `hello` (Iceberg table reading staging back)

set per folder in `dbt_project.yml`:

```yaml
models:
  horizon_iceberg:
    staging:
      +catalog_name: ice_transformed
      +schema: STAGING
    marts:
      +catalog_name: ice_transformed
      +schema: MARTS
```

> **Why UPPERCASE?** Snowflake folds unquoted identifiers to uppercase, so naming the
> namespaces `STAGING`/`MARTS` lets you address the tables from Snowflake SQL as
> `ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD` without quoting. A lowercase `+schema: staging`
> creates a lowercase namespace that Snowflake can only reach as `"staging"` (quoted).

**These namespaces are created on the fly — you do NOT pre-create them.** dbt issues
`create schema if not exists ice_transformed.<schema>` before each model, DuckDB-iceberg
turns that into a namespace-create call against the Horizon REST catalog, and the
`TRANSFORMER` role owns whatever it creates. The only requirement is the grant (already in
[`sql/horizon_access.sql`](../sql/horizon_access.sql)):

```sql
GRANT USAGE         ON DATABASE ICE_TRANSFORMED TO ROLE TRANSFORMER;
GRANT CREATE SCHEMA ON DATABASE ICE_TRANSFORMED TO ROLE TRANSFORMER;  -- lets dbt make namespaces
GRANT USAGE ON EXTERNAL VOLUME HORIZON_EXT_VOL  TO ROLE TRANSFORMER;  -- required to own Iceberg tables
```

**Gotcha — schema-name prefixing.** dbt's stock `generate_schema_name` macro returns
`<profile_schema>_<custom_schema>`, so with `schema: STAGING` in `profiles.yml` and
`+schema: STAGING` on a model you get the namespace `STAGING_STAGING`. dbt then *creates*
that mangled namespace but later compiles `ref()` SQL against the name you wrote, and the
read fails with (this is the error that started this whole thread, before the macro):

```
Catalog Error: Table ... does not exist because schema "STAGING_staging" does not exist.
```

The fix is [`macros/generate_schema_name.sql`](macros/generate_schema_name.sql), which
returns the `+schema:` value verbatim (falling back to `target.schema` when a model sets
none). With it, `+schema: STAGING` → namespace `STAGING`, full stop.

## Run

Prereqs: dbt Fusion ≥ preview.194 (`dbt system update`), the gitignored root `.env`.

```bash
cd dbt
set -a; source ../.env; set +a
source ../refresh_token.sh         # mints HORIZON_TOKEN (TRANSFORMER, ~60 min)
dbt build                                      # reads ICE_RAW; creates ICE_TRANSFORMED.STAGING + .MARTS; writes both natively
dbt show --inline "select * from {{ ref('stg_hello_world') }} order by created_at"
```

Verify cross-engine (independent pyiceberg client, or query `ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD` from Snowflake):

```bash
uv run python - <<'PY'
import os
from pyiceberg.catalog.rest import RestCatalog
uri=os.environ["HORIZON_CATALOG_URI"]; pat=os.environ["HORIZON_PAT"]
cat=RestCatalog("h", **{"uri":uri,"warehouse":"ICE_TRANSFORMED","credential":pat,
  "scope":"session:role:TRANSFORMER","oauth2-server-uri":uri+"/v1/oauth/tokens",
  "header.X-Iceberg-Access-Delegation":"vended-credentials"})
print(cat.load_table("STAGING.stg_hello_world").scan().to_arrow().num_rows, "rows")
PY
```

## Status

- ✅ Read `ICE_RAW.LANDING.HELLO_WORLD` via Fusion + Horizon REST catalog.
- ✅ Write `ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD` + `ICE_TRANSFORMED.MARTS.HELLO` (Snowflake-managed Iceberg) **natively** — no pyiceberg, no parquet round-trip, no custom materialization.
- ✅ Namespaces (`STAGING`, `MARTS`) created on the fly by dbt — only `CREATE SCHEMA ON DATABASE ICE_TRANSFORMED` is granted, nothing pre-created.
- ✅ Idempotent; cross-engine verified; `dbt show` reads the model back.
- ✅ Also works on **stock dbt-core 1.11 + dbt-duckdb** as a fallback (see NOTES).

Persisted as an Iceberg **table** (REST catalogs can't hold a cross-engine DuckDB view);
the model still behaves as a staging view locally. Details in
[NOTES_horizon_write_path.md](NOTES_horizon_write_path.md).
