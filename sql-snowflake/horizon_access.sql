-- Horizon external-engine access layer. Run as ACCOUNTADMIN:
--   snow sql -f sql-snowflake/horizon_access.sql --role ACCOUNTADMIN -c my-connection
--
-- LOADER: dlt writes ICE_RAW as an external engine (no Snowflake compute).
-- TRANSFORMER: dbt-duckdb reads ICE_RAW, writes ICE_TRANSFORMED.
-- Both auth as HORIZON_SVC; role is picked per-session by OAuth scope.
-- PAT is issued separately (sql-snowflake/issue_pat.sql), so its secret never lands here.

USE ROLE ACCOUNTADMIN;

-- required before a SERVICE user can hold/use a PAT. 0.0.0.0/0 is permissive for the demo; restrict for prod.
CREATE NETWORK POLICY IF NOT EXISTS HORIZON_SVC_NETPOL
  ALLOWED_IP_LIST = ('0.0.0.0/0')
  COMMENT = 'Demo policy enabling PAT auth for HORIZON_SVC; restrict IPs for prod';

-- LOADER — dlt loads/creates raw Iceberg tables in ICE_RAW.
GRANT USAGE        ON DATABASE ICE_RAW            TO ROLE LOADER;
GRANT CREATE SCHEMA ON DATABASE ICE_RAW           TO ROLE LOADER;  -- in case dlt creates its own dataset schema
GRANT USAGE        ON EXTERNAL VOLUME HORIZON_EXT_VOL TO ROLE LOADER;
-- Pre-made LANDING schema is owned by ACCOUNTADMIN, so grant explicitly:
GRANT USAGE              ON SCHEMA ICE_RAW.LANDING TO ROLE LOADER;
GRANT CREATE ICEBERG TABLE ON SCHEMA ICE_RAW.LANDING TO ROLE LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON ALL ICEBERG TABLES    IN SCHEMA ICE_RAW.LANDING TO ROLE LOADER;
GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE
  ON FUTURE ICEBERG TABLES IN SCHEMA ICE_RAW.LANDING TO ROLE LOADER;

-- TRANSFORMER — READ everything in ICE_RAW (dbt source).
GRANT USAGE  ON DATABASE ICE_RAW               TO ROLE TRANSFORMER;
GRANT USAGE  ON ALL SCHEMAS    IN DATABASE ICE_RAW TO ROLE TRANSFORMER;
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE ICE_RAW TO ROLE TRANSFORMER;
GRANT SELECT ON ALL ICEBERG TABLES    IN DATABASE ICE_RAW TO ROLE TRANSFORMER;
GRANT SELECT ON FUTURE ICEBERG TABLES IN DATABASE ICE_RAW TO ROLE TRANSFORMER;

-- TRANSFORMER — WRITE ICE_TRANSFORMED. dbt owns what it creates, so only
-- USAGE + CREATE SCHEMA + external-volume USAGE are needed here.
GRANT USAGE         ON DATABASE ICE_TRANSFORMED       TO ROLE TRANSFORMER;
GRANT CREATE SCHEMA ON DATABASE ICE_TRANSFORMED       TO ROLE TRANSFORMER;
GRANT USAGE         ON EXTERNAL VOLUME HORIZON_EXT_VOL TO ROLE TRANSFORMER;

-- Service user DuckDB/dbt authenticate as (PAT issued separately).
CREATE USER IF NOT EXISTS HORIZON_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = TRANSFORMER
  COMMENT = 'Machine identity for external Iceberg REST engines (dlt loader + dbt-duckdb)';
-- One identity holds both roles, but the account enforces a role restriction per
-- PAT, so we issue two (sql-snowflake/issue_pat.sql): HORIZON_LOAD_PAT for LOADER,
-- HORIZON_PAT for TRANSFORMER.
GRANT ROLE TRANSFORMER TO USER HORIZON_SVC;
GRANT ROLE LOADER      TO USER HORIZON_SVC;
ALTER USER HORIZON_SVC SET NETWORK_POLICY = HORIZON_SVC_NETPOL;
