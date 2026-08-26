-- MotherDuck + Snowflake Horizon Iceberg (TRANSFORMER read path)
-- Run LOCALLY, not in the MotherDuck web notebook -- the browser WASM build
-- can't get past Snowflake Polaris's missing CORS headers.
--
-- !! DO NOT `ATTACH 'md:'` in this session. Loading the motherduck extension
-- !! alongside an Iceberg scan SEGFAULTS on the vended-credential S3 read.
-- !! This script reads Iceberg only and exports to Parquet; load that into
-- !! MotherDuck from a separate process via load_to_motherduck.sql.
--
-- Prereqs: source refresh_token.sh, then run headless:
--   duckdb -c ".read motherduck/explore.sql"
-- (not `duckdb explore.sql` -- that arg is the DB file, not a script)

INSTALL iceberg;
LOAD iceberg;

-- pre-exchanged bearer token from refresh_token.sh -- DuckDB's own OAuth2 flow hits the wrong endpoint
CREATE OR REPLACE SECRET horizon (
    TYPE ICEBERG,
    TOKEN getenv('HORIZON_TOKEN')
);

ATTACH 'ICE_RAW' AS horizon (
    TYPE ICEBERG,
    ENDPOINT 'https://myorg-myacct.snowflakecomputing.com/polaris/api/catalog',
    SECRET horizon
);

-- Snowflake doesn't write a version-hint file, so DuckDB must glob S3 for the latest metadata version
SET unsafe_enable_version_guessing = true;

SHOW ALL TABLES;

-- the table dlt landed (LOADER half of the demo)
SELECT * FROM horizon.LANDING.HELLO_WORLD;

-- export so a separate MotherDuck session can load it without crashing (see header note)
COPY (SELECT * FROM horizon.LANDING.HELLO_WORLD)
    TO '/tmp/hello_world.parquet' (FORMAT parquet);
