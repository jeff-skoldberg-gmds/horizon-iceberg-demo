
INSTALL iceberg;
LOAD iceberg;

CREATE OR REPLACE SECRET horizon_secret (
    TYPE ICEBERG,
    TOKEN getenv('HORIZON_TOKEN')
);

ATTACH 'ICE_RAW' AS SNOW_HORIZON (
    TYPE ICEBERG,
    ENDPOINT getenv('HORIZON_CATALOG_URI'),
    SECRET horizon_secret
);

-- Snowflake doesn't write a version-hint file; DuckDB must glob S3 for the latest metadata version.
SET unsafe_enable_version_guessing = true;

-- what tables are in the catalog?
SHOW ALL TABLES;

select count(*) from SNOW_HORIZON.LANDING.HELLO_WORLD;

create or replace table local_hello_world as select * from SNOW_HORIZON.LANDING.HELLO_WORLD limit 2_000_000;

-- time to select 5000 rows: 1.59s, 0.86s, 1.53s, 2.01s, 1.17s (avg ~1.43s)
SELECT * FROM SNOW_HORIZON.LANDING.HELLO_WORLD limit 20_000_000;
-- time to select ALL the rows (79,410): 0.43s, 0.42s, 0.42s, 0.42s, 0.42s (avg ~0.42s)
select * from local_hello_world limit 20_000_000;
select count(*) from local_hello_world;
select count(*) from SNOW_HORIZON.LANDING.HELLO_WORLD;



DELETE FROM local_hello_world
WHERE lower(left(id, 1)) IN ('e', '1', '2', '3', 'a');

table SNOW_HORIZON.LANDING.HELLO_WORLD;