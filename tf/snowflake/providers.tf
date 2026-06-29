terraform {
  required_version = ">= 1.5.0"

  required_providers {
    snowflake = {
      source  = "snowflakedb/snowflake"
      version = "~> 2.0"
    }
  }
}

# Key-pair (JWT) auth, using the same RSA key your snow CLI uses.
# Configured directly because the snow CLI's config.toml format
# ([connections.*] + default_connection_name) isn't what the TF provider's
# TOML loader expects. Values come from terraform.tfvars (see example.tfvars).
#
# Role is pinned to ACCOUNTADMIN because CREATE DATABASE / CREATE EXTERNAL
# VOLUME need privileges above the connection's default LOADER role.
provider "snowflake" {
  organization_name = var.organization_name
  account_name      = var.account_name
  user              = var.snowflake_user
  authenticator     = "SNOWFLAKE_JWT"
  private_key       = file(var.private_key_file)
  role              = var.provider_role
  warehouse         = var.warehouse

  preview_features_enabled = ["snowflake_external_volume_resource"]
}
