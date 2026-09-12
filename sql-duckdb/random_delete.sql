-- Randomly delete ~65% of ICE_RAW.LANDING.HELLO_WORLD, as the LOADER role
-- (the only role with write access to ICE_RAW -- connect.sql attaches as
-- TRANSFORMER, which is read-only there). UNTESTED: nobody has run a DELETE
-- against a Horizon Iceberg REST table yet, only CREATE/INSERT into
-- ICE_TRANSFORMED, so this is the first try.
--
-- Prereqs: source refresh_load_token.sh (mints HORIZON_LOAD_TOKEN), then:
--   duckdb -c ".read sql-duckdb/random_delete.sql"

INSTALL iceberg;
LOAD iceberg;

CREATE OR REPLACE SECRET horizon_load_secret (
    TYPE ICEBERG,
    TOKEN getenv('HORIZON_LOAD_TOKEN')
);

-- Write-compat options proven for ICE_TRANSFORMED (dbt/catalogs.yml) --
-- Horizon-catalog quirks, not role-specific: no client-supplied location,
-- single-table commits only, and vended creds can't DELETE S3 objects so
-- DuckDB must not try to on rollback.
ATTACH 'ICE_RAW' AS SNOW_HORIZON_LOAD (
    TYPE ICEBERG,
    ENDPOINT getenv('HORIZON_CATALOG_URI'),
    SECRET horizon_load_secret,
    STAGE_CREATE_TABLES false,
    DISABLE_MULTI_TABLE_COMMIT true,
    SKIP_CREATE_TABLE_METADATA_UPDATES true,
    REMOVE_FILES_ON_DELETE false
);

SET unsafe_enable_version_guessing = true;

select count(*) as rows_before from SNOW_HORIZON_LOAD.LANDING.HELLO_WORLD;

DELETE FROM SNOW_HORIZON_LOAD.LANDING.HELLO_WORLD
WHERE random() < 0.65;

select count(*) as rows_after from SNOW_HORIZON_LOAD.LANDING.HELLO_WORLD;
