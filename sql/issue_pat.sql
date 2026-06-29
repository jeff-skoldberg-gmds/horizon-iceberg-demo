-- Re-issue the HORIZON_SVC PATs (each secret is returned ONCE in the output).
--
-- This Snowflake account ENFORCES a role restriction on every PAT, so we issue
-- TWO role-restricted tokens for the one service user (HORIZON_SVC holds both
-- LOADER + TRANSFORMER, see sql/horizon_access.sql):
--   HORIZON_LOAD_PAT  ROLE_RESTRICTION='LOADER'       -> dlt writes ICE_RAW.LANDING (REST, no compute)
--   HORIZON_PAT       ROLE_RESTRICTION='TRANSFORMER'  -> dbt-duckdb reads ICE_RAW / writes ICE_TRANSFORMED
-- The OAuth scope at token-exchange must match the restriction (session:role:LOADER
-- / session:role:TRANSFORMER).
--
-- Run (capture each token_secret straight into the gitignored .env, never echoing
-- it to a terminal/log) -- .env keys: HORIZON_LOAD_PAT and HORIZON_PAT:
--   snow sql -q "ALTER USER HORIZON_SVC ADD PAT HORIZON_LOAD_PAT DAYS_TO_EXPIRY=7 \
--     ROLE_RESTRICTION='LOADER'      COMMENT='dlt external Iceberg REST loader'"   --role ACCOUNTADMIN -c my-connection --format json
--   snow sql -q "ALTER USER HORIZON_SVC ADD PAT HORIZON_PAT      DAYS_TO_EXPIRY=7 \
--     ROLE_RESTRICTION='TRANSFORMER' COMMENT='dbt-duckdb external Iceberg REST'"   --role ACCOUNTADMIN -c my-connection --format json
--
-- Remove an existing PAT before re-adding it:
--   ALTER USER HORIZON_SVC REMOVE PAT HORIZON_LOAD_PAT;
--   ALTER USER HORIZON_SVC REMOVE PAT HORIZON_PAT;

ALTER USER HORIZON_SVC ADD PAT HORIZON_LOAD_PAT
  DAYS_TO_EXPIRY   = 7
  ROLE_RESTRICTION = 'LOADER'
  COMMENT          = 'dlt external Iceberg REST loader (writes ICE_RAW.LANDING)';

ALTER USER HORIZON_SVC ADD PAT HORIZON_PAT
  DAYS_TO_EXPIRY   = 7
  ROLE_RESTRICTION = 'TRANSFORMER'
  COMMENT          = 'dbt-duckdb external Iceberg REST (reads ICE_RAW / writes ICE_TRANSFORMED)';
