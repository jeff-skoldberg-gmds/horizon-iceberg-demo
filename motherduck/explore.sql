-- MotherDuck + Snowflake Horizon Iceberg (TRANSFORMER read path)
-- Run LOCALLY, not in the MotherDuck web notebook: the web UI executes in
-- browser WASM, and Snowflake's Polaris catalog sends no CORS headers, so the
-- catalog fetch is blocked and surfaces as a 404/CORS error. The local CLI
-- issues the request from the process, so there is no CORS sandbox.
--
-- !! DO NOT `ATTACH 'md:'` (or otherwise LOAD the motherduck extension) in this
-- !! session. Loading the MotherDuck extension in the same process as an Iceberg
-- !! data scan SEGFAULTS (SIGSEGV) on the vended-credential S3 read — the catalog
-- !! ATTACH and SHOW ALL TABLES (metadata) succeed, but the actual SELECT crashes
-- !! the process. Bug is in the motherduck extension build (v1.5.1-2026-04-137),
-- !! reproducible 100%. This script reads Iceberg ONLY and exports to Parquet;
-- !! load that Parquet into MotherDuck from a SEPARATE process via
-- !! load_to_motherduck.sql.
--
-- Prereqs (run once in your shell, then launch from it):
--   source refresh_token.sh   # exports HORIZON_TOKEN (~60 min)
-- Then run it headless:
--   duckdb -c ".read motherduck/explore.sql"
-- NOTE: do NOT do `duckdb explore.sql` — the positional arg is the DB file, not a script.

-- 1. Iceberg REST catalog support
INSTALL iceberg;

LOAD iceberg;

-- 2. Pre-exchanged bearer token (minted by refresh_token.sh). We inject the token
--    directly so DuckDB never runs its own OAuth2 flow against the wrong endpoint.
CREATE OR REPLACE SECRET horizon (
    TYPE ICEBERG,
    TOKEN getenv('HORIZON_TOKEN')
);

-- 3. Attach the Snowflake-managed Iceberg catalog. warehouse = database name (ICE_RAW).
ATTACH 'ICE_RAW' AS horizon (
    TYPE ICEBERG,
    ENDPOINT 'https://myorg-myacct.snowflakecomputing.com/polaris/api/catalog',
    SECRET horizon
);

-- 4. Snowflake doesn't write a version-hint file, so DuckDB must glob S3 for the
--    latest metadata version. (Vended S3 creds from the bearer token make the read work.)
SET unsafe_enable_version_guessing = true;

-- 5. Browse what the catalog exposes
SHOW ALL TABLES;

-- 6. The table dlt landed (LOADER half of the demo)
SELECT * FROM horizon.LANDING.HELLO_WORLD;

-- 7. Export to Parquet so a separate MotherDuck session can load it without
--    crashing (see the header note). Adjust the path/table as needed.
COPY (SELECT * FROM horizon.LANDING.HELLO_WORLD)
    TO '/tmp/hello_world.parquet' (FORMAT parquet);
