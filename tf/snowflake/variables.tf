variable "organization_name" {
  description = "Snowflake organization name (the part before the dash in the account identifier). Set in terraform.tfvars."
  type        = string
}

variable "account_name" {
  description = "Snowflake account name (the part after the dash in the account identifier). Set in terraform.tfvars."
  type        = string
}

variable "snowflake_user" {
  description = "Snowflake user for key-pair auth. Set in terraform.tfvars."
  type        = string
}

variable "private_key_file" {
  description = "Path to the PEM/.p8 private key used for JWT auth. Set in terraform.tfvars."
  type        = string
}

variable "warehouse" {
  description = "Warehouse used for the session."
  type        = string
  default     = "ETL_XS"
}

variable "provider_role" {
  description = "Role used to run Terraform. CREATE DATABASE / CREATE EXTERNAL VOLUME need ACCOUNTADMIN (or equivalent global privileges)."
  type        = string
  default     = "ACCOUNTADMIN"
}

# Identifiers are UPPERCASE with only [A-Z0-9_] so they never need quoting:
# the provider quotes identifiers, and "ICE_RAW" matches what unquoted ice_raw
# resolves to. Lowercase/hyphenated names would force quoting everywhere.

variable "database_name" {
  description = "Database that will hold the Iceberg tables."
  type        = string
  default     = "ICE_RAW"
}

variable "schema_name" {
  description = "Schema within the database for landing Iceberg tables."
  type        = string
  default     = "LANDING"
}

variable "transformed_database_name" {
  description = "Database dbt-duckdb writes transformed Iceberg tables into."
  type        = string
  default     = "ICE_TRANSFORMED"
}

variable "external_volume_name" {
  description = "Name of the Snowflake external volume."
  type        = string
  default     = "HORIZON_EXT_VOL"
}

variable "storage_location_name" {
  description = "Name of the storage location within the external volume."
  type        = string
  default     = "HORIZON_S3_US"
}

variable "bucket_name" {
  description = "S3 bucket backing the Iceberg tables (must match the AWS stack). Set in terraform.tfvars."
  type        = string
}

variable "prefix" {
  description = "Key prefix within the bucket (must match the AWS stack)."
  type        = string
  default     = "horizon"
}

variable "aws_account_id" {
  description = "AWS account ID that owns the IAM role. Set in terraform.tfvars."
  type        = string
}

variable "aws_role_name" {
  description = "Name of the IAM role Snowflake assumes (from the AWS stack)."
  type        = string
  default     = "snowflake-iceberg-horizon-role"
}

variable "storage_aws_external_id" {
  description = "External ID Snowflake presents when assuming the role. You choose this value; it must match the role's trust policy."
  type        = string
  default     = "iceberg_horizon_ext_id"
}
