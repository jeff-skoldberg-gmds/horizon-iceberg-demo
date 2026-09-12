[generated with claude]

# SIGSEGV: MotherDuck extension + Iceberg REST catalog vended-credential scan

## Status (updated 2026-08-26): still open on latest versions

Re-tested end to end on current-as-of-today releases: DuckDB 1.5.5, motherduck
ext `v1.5.5-2026-08-230`, iceberg ext `45163a28`. Two changes from the original
report below, neither of which resolves the issue:

- MotherDuck now loads fine on DuckDB 1.5.5 (it used to refuse above 1.5.3 —
  see the version matrix).
- The crash itself no longer surfaces as a clean SIGSEGV. glibc now catches
  heap corruption a step earlier: `free(): invalid pointer` on one run,
  `free(): invalid size` on an immediate re-run of the identical script (exit
  134 both times). A different abort message on an identical re-run points to
  memory corruption/undefined behavior, not a new, separate, deterministic
  bug — consistent with the original "likely cause" theory below.

`SHOW ALL TABLES` with `md:` attached still lists the table fine, so it's
visible/browsable in MotherDuck — only the actual data scan over vended
credentials crashes. The documented workaround (skip `md:`, read Iceberg in
one process, `COPY` to Parquet, load that into MotherDuck from a second
process) was re-confirmed working unaffected on these same versions.

## Summary

With the MotherDuck extension loaded (`ATTACH 'md:'`), reading data from an
Iceberg REST catalog that uses **vended credentials** crashes the DuckDB process
with `SIGSEGV` (exit 139). The catalog connection and metadata browsing succeed;
only the data scan that consumes catalog-vended S3 credentials crashes.

The same read works perfectly when the MotherDuck extension is **not** loaded, and
also works **with** MotherDuck loaded if we supply the S3 credentials ourselves as
an explicit `TYPE S3` secret (i.e. bypass the catalog's auto-vending). So the fault
is isolated to: **MotherDuck extension + the Iceberg extension's automatic
vended-credential code path.**

## Environment

- OS: Linux x86_64 (WSL2, kernel 5.15)
- DuckDB CLI: reproduced on v1.5.1, v1.5.2, v1.5.3
- MotherDuck extension build: `motherduck_impl.v1.5.1-2026-04-137`
- Iceberg extension: stock `INSTALL iceberg` from the official repo (also reproduces
  with MotherDuck's *bundled* iceberg, i.e. no separate `INSTALL iceberg`)
- Catalog: Snowflake-managed Iceberg via Polaris REST API
  (`https://<account>.snowflakecomputing.com/polaris/api/catalog`), credentials
  vended per-table (`s3.access-key-id` / `s3.secret-access-key` / `s3.session-token`)

## Minimal reproduction

```sql
-- $HORIZON_TOKEN = a valid bearer token for the Iceberg REST catalog
-- $motherduck_token in the environment
INSTALL iceberg; LOAD iceberg;
ATTACH 'md:';
CREATE OR REPLACE SECRET cat (TYPE ICEBERG, TOKEN getenv('HORIZON_TOKEN'));
ATTACH 'ICE_RAW' AS cat (
  TYPE ICEBERG,
  ENDPOINT 'https://<account>.snowflakecomputing.com/polaris/api/catalog',
  SECRET cat
);
SET unsafe_enable_version_guessing = true;

SHOW ALL TABLES;                          -- ✅ works: lists catalog tables
SELECT * FROM cat.LANDING.HELLO_WORLD;    -- 💥 SIGSEGV (exit 139)
```

## Expected vs actual

- **Expected:** the `SELECT` returns the table's rows (it does when md is not loaded).
- **Actual:** process terminates with `SIGSEGV` / exit code 139, no error message.

## Fault isolation

All rows below run with `ATTACH 'md:'` active unless noted:

| Operation | Result |
|---|---|
| `ATTACH … TYPE ICEBERG` + `SHOW ALL TABLES` (catalog metadata) | ✅ works |
| Plain httpfs read (`SELECT … FROM 'https://…/x.parquet'`) | ✅ works |
| `SELECT * FROM cat.<ns>.<table>` (catalog scan, **auto-vended** creds) | 💥 SIGSEGV |
| `iceberg_scan('s3://…/metadata…')` with **explicit `TYPE S3`** secret (self-vended creds) | ✅ works |
| Same `SELECT` with the MotherDuck extension **not** loaded | ✅ works |
| Adding `ACCESS_DELEGATION_MODE 'none'` to the catalog `ATTACH` | 💥 still SIGSEGV |

Notes:
- Reproduces with `SET threads=1`, so it is not (only) a multithreading race.
- Reproduces whether MotherDuck is attached before or after the Iceberg catalog.
- `ACCESS_DELEGATION_MODE 'none'` (which should make DuckDB use a separately
  configured S3 secret instead of vended creds) is accepted without error but does
  **not** avoid the crash via the catalog-`SELECT` path.

## Working workaround

Vend the credentials ourselves (one REST `GET .../v1/<cat>/namespaces/<ns>/tables/<t>`
with `X-Iceberg-Access-Delegation: vended-credentials`), pass them as an explicit
`TYPE S3` secret, and read with `iceberg_scan` pointed at the metadata location:

```sql
ATTACH 'md:';
CREATE OR REPLACE SECRET s3vended (
  TYPE S3,
  KEY_ID '<s3.access-key-id>',
  SECRET '<s3.secret-access-key>',
  SESSION_TOKEN '<s3.session-token>',
  REGION '<client.region>'
);
SET unsafe_enable_version_guessing = true;
SELECT * FROM iceberg_scan('s3://<bucket>/<path>/<table>…');   -- ✅ exit 0, rows returned
```

This confirms the crash is specifically in the **automatic vended-credential**
handling when the MotherDuck extension is co-loaded — not in iceberg, httpfs, or
the S3 read itself.

## Version matrix

| DuckDB | MotherDuck ext loads? | Catalog-`SELECT` (auto-vended) |
|---|---|---|
| 1.4.5 LTS | ❌ refuses ("not yet supported") | n/a |
| 1.5.1 | ✅ | 💥 SIGSEGV |
| 1.5.2 | ✅ | 💥 SIGSEGV |
| 1.5.3 | ✅ | 💥 SIGSEGV |
| 1.5.4 | ❌ refuses ("latest supported is v1.5.3") | n/a |
| 1.5.5 | ✅ (`v1.5.5-2026-08-230`) | 💥 `free(): invalid pointer` / `free(): invalid size` (SIGABRT, exit 134) — see Status above |

## Likely cause (speculative)

A symbol/library collision between the MotherDuck extension's bundled
httpfs/AWS-SDK and the Iceberg extension's vended-credential handler — the crash
only manifests on the code path that ingests catalog-vended temporary S3
credentials and immediately uses them for the data-file read.
</content>
