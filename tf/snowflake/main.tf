# ---------------------------------------------------------------------------
# Database + schema that will hold the Iceberg tables
# ---------------------------------------------------------------------------

resource "snowflake_database" "ice_raw" {
  name = var.database_name

  # Database-level Iceberg defaults so any schema (pre-made LANDING or one dlt
  # creates) lands tables as Snowflake-managed Iceberg on the external volume.
  external_volume = snowflake_external_volume.horizon.name
  catalog         = "SNOWFLAKE"
}

# Transformed layer — dbt-duckdb (as TRANSFORMER) writes here via the REST catalog.
resource "snowflake_database" "ice_transformed" {
  name = var.transformed_database_name

  external_volume = snowflake_external_volume.horizon.name
  catalog         = "SNOWFLAKE"
}

resource "snowflake_schema" "landing" {
  database = snowflake_database.ice_raw.name
  name     = var.schema_name

  # Defaults so tables created here (by dlt/LOADER) land as Snowflake-managed
  # Iceberg without naming the volume/catalog each time.
  external_volume = snowflake_external_volume.horizon.name
  catalog         = "SNOWFLAKE"
}

# ---------------------------------------------------------------------------
# Grants — TRANSFORMER reads everything in ICE_RAW (dbt-duckdb / MotherDuck source).
#
# The Iceberg REST catalog filters table listings by privilege: without SELECT,
# the catalog returns an EMPTY table list to TRANSFORMER (not a 403), so external
# engines silently see no tables. The FUTURE grants ensure tables dlt creates
# later are covered automatically.
# ---------------------------------------------------------------------------

resource "snowflake_grant_privileges_to_account_role" "transformer_ice_raw_usage" {
  account_role_name = "TRANSFORMER"
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = snowflake_database.ice_raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_ice_raw_schemas_all" {
  account_role_name = "TRANSFORMER"
  privileges        = ["USAGE"]

  on_schema {
    all_schemas_in_database = snowflake_database.ice_raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_ice_raw_schemas_future" {
  account_role_name = "TRANSFORMER"
  privileges        = ["USAGE"]

  on_schema {
    future_schemas_in_database = snowflake_database.ice_raw.name
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_ice_raw_tables_all" {
  account_role_name = "TRANSFORMER"
  privileges        = ["SELECT"]

  on_schema_object {
    all {
      object_type_plural = "ICEBERG TABLES"
      in_database        = snowflake_database.ice_raw.name
    }
  }
}

resource "snowflake_grant_privileges_to_account_role" "transformer_ice_raw_tables_future" {
  account_role_name = "TRANSFORMER"
  privileges        = ["SELECT"]

  on_schema_object {
    future {
      object_type_plural = "ICEBERG TABLES"
      in_database        = snowflake_database.ice_raw.name
    }
  }
}

# ---------------------------------------------------------------------------
# External volume — Snowflake Horizon Iceberg
#
# Terraform equivalent of:
#   CREATE OR REPLACE EXTERNAL VOLUME horizon_ext_vol
#     STORAGE_LOCATIONS = ((
#       NAME = 'horizon-s3-us'
#       STORAGE_PROVIDER = 'S3'
#       STORAGE_BASE_URL = 's3://<bucket_name>/<prefix>/'
#       STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::<aws_account_id>:role/<aws_role_name>'
#       STORAGE_AWS_EXTERNAL_ID = 'iceberg_horizon_ext_id'
#     ))
#     ALLOW_WRITES = TRUE;
# ---------------------------------------------------------------------------

resource "snowflake_external_volume" "horizon" {
  name = var.external_volume_name

  # Required because Snowflake writes data + metadata, not just reads.
  allow_writes = "true"

  storage_location {
    storage_location_name   = var.storage_location_name
    storage_provider        = "S3"
    storage_base_url        = "s3://${var.bucket_name}/${var.prefix}/"
    storage_aws_role_arn    = "arn:aws:iam::${var.aws_account_id}:role/${var.aws_role_name}"
    storage_aws_external_id = var.storage_aws_external_id
  }
}
