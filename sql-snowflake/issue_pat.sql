-- Re-issue HORIZON_SVC's two role-restricted PATs. Secrets are shown ONCE --
-- paste into .env (HORIZON_LOAD_PAT / HORIZON_PAT), never log them.
--
-- If a PAT of this name already exists, remove it first:
--   ALTER USER HORIZON_SVC REMOVE PAT HORIZON_LOAD_PAT;
--   ALTER USER HORIZON_SVC REMOVE PAT HORIZON_PAT;
--
-- Run: snow sql -f sql-snowflake/issue_pat.sql --role ACCOUNTADMIN -c <connection> --format json
-- expiries under 360 days have lapsed silently before -- see token_refresh.md step 1.

ALTER USER HORIZON_SVC ADD PAT HORIZON_LOAD_PAT
  DAYS_TO_EXPIRY   = 360
  ROLE_RESTRICTION = 'LOADER'
  COMMENT          = 'dlt external Iceberg REST loader (writes ICE_RAW.LANDING)';

ALTER USER HORIZON_SVC ADD PAT HORIZON_PAT
  DAYS_TO_EXPIRY   = 360
  ROLE_RESTRICTION = 'TRANSFORMER'
  COMMENT          = 'dbt-duckdb external Iceberg REST (reads ICE_RAW / writes ICE_TRANSFORMED)';
