-- ===========================================================================
-- Horizon external-engine access layer
-- Run as ACCOUNTADMIN:
--   snow sql -f sql/horizon_access.sql --role ACCOUNTADMIN -c my-connection
--
-- Roles:
--   LOADER      -> dlt loads/creates raw Iceberg tables in ICE_RAW via the Horizon
--                  Iceberg REST Catalog as an EXTERNAL engine (no Snowflake compute)
--   TRANSFORMER -> dbt-duckdb reads ICE_RAW, writes ICE_TRANSFORMED, no Snowflake compute
--   Both authenticate to the Horizon Iceberg REST Catalog as HORIZON_SVC via one PAT;
--   the role is chosen per-session by the OAuth scope (session:role:<role>).
--
-- NOTE: the PAT itself is issued separately (see sql/issue_pat.sql) so its
-- secret never lands in version control.
-- ===========================================================================

USE ROLE ACCOUNTADMIN;

-- 1. Network policy — REQUIRED before a TYPE=SERVICE user can hold/use a PAT.
--    Applied to HORIZON_SVC only (not the account). 0.0.0.0/0 is permissive for
--    the demo; restrict ALLOWED_IP_LIST to your egress IP(s) for production.
CREATE NETWORK POLICY IF NOT EXISTS HORIZON_SVC_NETPOL
  ALLOWED_IP_LIST = ('0.0.0.0/0')
  COMMENT = 'Demo policy enabling PAT auth for HORIZON_SVC; restrict IPs for prod';

-- 2. LOADER — dlt loads/creates raw Iceberg tables in ICE_RAW.
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

-- 3a. TRANSFORMER — READ everything in ICE_RAW (dbt source).
GRANT USAGE  ON DATABASE ICE_RAW               TO ROLE TRANSFORMER;
GRANT USAGE  ON ALL SCHEMAS    IN DATABASE ICE_RAW TO ROLE TRANSFORMER;
GRANT USAGE  ON FUTURE SCHEMAS IN DATABASE ICE_RAW TO ROLE TRANSFORMER;
GRANT SELECT ON ALL ICEBERG TABLES    IN DATABASE ICE_RAW TO ROLE TRANSFORMER;
GRANT SELECT ON FUTURE ICEBERG TABLES IN DATABASE ICE_RAW TO ROLE TRANSFORMER;

-- 3b. TRANSFORMER — WRITE ICE_TRANSFORMED. dbt creates schemas + tables and thus
--     OWNS them, which confers full table privileges automatically. So we only
--     need USAGE + CREATE SCHEMA on the database, plus external-volume USAGE
--     (required to own Iceberg tables).
GRANT USAGE         ON DATABASE ICE_TRANSFORMED       TO ROLE TRANSFORMER;
GRANT CREATE SCHEMA ON DATABASE ICE_TRANSFORMED       TO ROLE TRANSFORMER;
GRANT USAGE         ON EXTERNAL VOLUME HORIZON_EXT_VOL TO ROLE TRANSFORMER;

-- 4. Service user DuckDB/dbt authenticate as (PAT issued separately).
CREATE USER IF NOT EXISTS HORIZON_SVC
  TYPE = SERVICE
  DEFAULT_ROLE = TRANSFORMER
  COMMENT = 'Machine identity for external Iceberg REST engines (dlt loader + dbt-duckdb)';
-- One service identity holds BOTH roles. This account ENFORCES a role restriction
-- on every PAT, so a single unrestricted token can't cover both — we issue TWO
-- role-restricted PATs (sql/issue_pat.sql): HORIZON_LOAD_PAT (LOADER, for dlt) and
-- HORIZON_PAT (TRANSFORMER, for dbt). Each engine's OAuth scope matches its PAT's
-- restriction (session:role:LOADER / session:role:TRANSFORMER).
GRANT ROLE TRANSFORMER TO USER HORIZON_SVC;  -- read ICE_RAW / write ICE_TRANSFORMED (dbt-duckdb)
GRANT ROLE LOADER      TO USER HORIZON_SVC;  -- write ICE_RAW.LANDING via REST (dlt)
ALTER USER HORIZON_SVC SET NETWORK_POLICY = HORIZON_SVC_NETPOL;
