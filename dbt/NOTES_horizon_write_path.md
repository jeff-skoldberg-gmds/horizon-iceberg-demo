# How the TRANSFORMER writes to Horizon (design note)

**Status: THE DREAM, REALIZED ON dbt FUSION.** `dbt run` (dbt Fusion, Core v2) reads
`ICE_RAW.LANDING.HELLO_WORLD` and persists `ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD` as a
Snowflake-managed Iceberg table — written by **Fusion's bundled DuckDB**, natively, straight
through the Horizon Iceberg REST catalog. A stock `+materialized: table` bound to the catalog;
no custom materialization, no pyiceberg, no parquet round-trip, no Snowflake compute. Verified
cross-engine 2026-06-26 (an independent pyiceberg client reads back 8 rows / 1 data snapshot).

## The primary path — dbt Fusion + catalogs.yml v2 (preview.194+)

DuckDB **1.5.4** shipped the [duckdb-iceberg#1017](https://github.com/duckdb/duckdb-iceberg/pull/1017)
write-compat ATTACH options, and **dbt Fusion preview.194** exposes them in `catalogs.yml` v2.
That's the whole trick — Fusion attaches the write catalog with these four options and emits a
`CREATE TABLE` straight into Horizon (and commits the data append itself).

| Step | Engine | Mechanism |
| --- | --- | --- |
| Read `ICE_RAW` | Fusion/DuckDB | `ice_raw` catalog (catalogs.yml), scanned with vended S3 creds. |
| Persist to `ICE_TRANSFORMED` | Fusion/DuckDB | stock `table` materialization bound via `+catalog_name: ice_transformed`. |

Wiring:
- [catalogs.yml](catalogs.yml) — `ice_raw` (read) + `ice_transformed` (write, with the four options).
- [dbt_project.yml](dbt_project.yml) — `flags: use_catalogs_v2: true`; staging model `+materialized: table` + `+catalog_name: ice_transformed`.
- [profiles.yml](profiles.yml) — DuckDB target + the `horizon` ICEBERG secret (pre-minted bearer) the catalogs reference.

### The four write-compat ATTACH options (on the `ice_transformed` catalog)

Snowflake Horizon rejects DuckDB's default REST-write path. These four
([catalogs.yml](catalogs.yml) → `config.duckdb`) fix every failure; **all four are required**:

| Option | Value | Why |
| --- | --- | --- |
| `stage_create_tables` | `false` | Horizon assigns the table location under its external volume and rejects a client-supplied location (`400 "Setting table location is not allowed"`). Direct (non-staged) create avoids it. |
| `disable_multi_table_commit` | `true` | Horizon doesn't implement the multi-table `POST /v1/{db}/transactions/commit` endpoint DuckDB uses by default. Per-table `updateTable` instead. |
| `skip_create_table_metadata_updates` | `true` | **Required when `stage_create_tables false`** — without it the post-create metadata update again tries to set the location → `400`. |
| `remove_files_on_delete` | `false` | The vended S3 creds are Put/Get/List only. On any rollback DuckDB would DELETE the data file → `403 Forbidden` (the masked error we used to see). Don't delete; let the catalog GC. |

> Note on the doubled schema: don't set `+schema: STAGING` on the model — the profile's
> `schema: STAGING` already applies, and the two concatenate into `STAGING_STAGING`. The
> `+catalog_name` plus the profile schema are enough.

### Run

```bash
cd dbt
set -a; source ../.env; set +a
source ../refresh_token.sh         # mints HORIZON_TOKEN (TRANSFORMER, ~60 min)
dbt run                                        # Fusion: reads ICE_RAW, writes ICE_TRANSFORMED.STAGING.STG_HELLO_WORLD natively
dbt show --inline "select message, count(*) n from {{ ref('stg_hello_world') }} group by 1 order by 1"
```

(The only output is an `[NotYetSupportedOption (dbt1701)]` warning — catalogs.yml v2 schema
validation is flagged experimental. Harmless.)

## Version history — how we got here

- **DuckDB < 1.5.4 / Fusion ≤ preview.193:** DuckDB could read Horizon but not commit
  (multi-table `transactions/commit` 400 + forbidden rollback DELETE). preview.193 also forwarded
  only `support_stage_create` under the *old* DuckDB option name (`SUPPORT_STAGE_CREATE`, which
  1.5.4 rejects) and exposed none of the other three. The bridge then was a dbt-duckdb plugin
  that committed via pyiceberg.
- **preview.194:** exposes all four #1017 options in catalogs.yml v2 → the native Fusion write
  above. The plugin is gone.

## Fallback — dbt-duckdb (dbt-core, no Fusion)

If you can't run Fusion, the same native write works on **stock dbt-core 1.11 + dbt-duckdb**
(DuckDB ≥ 1.5.4), via attach options in the profile + a small custom materialization. Files:
[profiles.duckdb.yml](profiles.duckdb.yml), [dbt_project.duckdb.yml](dbt_project.duckdb.yml),
[macros-duckdb/materialization_iceberg_table.sql](macros-duckdb/materialization_iceberg_table.sql).
Activate by copying those over `profiles.yml`/`dbt_project.yml` and moving `catalogs.yml` aside
(dbt-core parses `catalogs.yml` with an incompatible schema), then `uv run dbt run --profiles-dir .`.

Two gotchas the dbt-duckdb path hit that **Fusion handles for you**:

1. **dbt-duckdb DROPS false booleans.** `Attachment.to_sql()` only emits a boolean ATTACH option
   if it's True — a plain `stage_create_tables: false` silently vanishes. Workaround: pass the
   false-valued options as **quoted strings** (`"false"`) → `STAGE_CREATE_TABLES 'false'`, which
   DuckDB parses as boolean false. (Fusion's catalogs.yml takes real `false`.)
2. **The data append needs an explicit commit.** With `stage_create_tables false`, DuckDB commits
   the *empty* table eagerly but the data-file append is bound to the DuckDB transaction; dbt-core
   doesn't auto-commit a custom materialization, so without `{% do adapter.commit() %}` after the
   `CREATE TABLE AS` the table lands with the right schema and **zero rows**. (Fusion commits the
   append itself.) The macro also runs `drop table if exists` via `run_query` because iceberg-REST
   forbids re-creating a table dropped in the *same* transaction.

## "View" vs table

The request was a staging *view* persisted in `ICE_TRANSFORMED`. An Iceberg REST catalog can't
hold a cross-engine DuckDB view, so the persisted object is an Iceberg **table** (the faithful
realization). Locally, the `hello` mart is still a DuckDB view over the staging table.
