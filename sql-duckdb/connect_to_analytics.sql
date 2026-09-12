
INSTALL iceberg;
LOAD iceberg;

-- same TRANSFORMER token as connect_to_raw.sql -- TRANSFORMER owns ICE_TRANSFORMED outright
CREATE OR REPLACE SECRET horizon_secret (
    TYPE ICEBERG,
    TOKEN getenv('HORIZON_TOKEN')
);

ATTACH 'ICE_TRANSFORMED' AS SNOW_HORIZON (
    TYPE ICEBERG,
    ENDPOINT getenv('HORIZON_CATALOG_URI'),
    SECRET horizon_secret
);

-- Snowflake doesn't write a version-hint file; DuckDB must glob S3 for the latest metadata version.
SET unsafe_enable_version_guessing = true;

-- what tables did dbt build?
SHOW ALL TABLES;

select * from SNOW_HORIZON.STAGING.STG_HELLO_WORLD limit 100;
select * from SNOW_HORIZON.MARTS.HELLO limit 100;
select * from SNOW_HORIZON.MARTS.WORLD limit 100;

create or replace table my_local_table as select * from SNOW_HORIZON.MARTS.HELLO limit 10000;
select * from my_local_table;

select 
created_at::date as created_date,
count(*) as total_rows,
from 
my_local_table
group by all
;