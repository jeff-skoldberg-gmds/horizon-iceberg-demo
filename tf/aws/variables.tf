variable "region" {
  description = "AWS region for the Iceberg bucket."
  type        = string
  default     = "us-east-2"
}

variable "profile" {
  description = "AWS CLI/SDK profile to use."
  type        = string
  default     = "default"
}

variable "bucket_name" {
  description = "Name of the S3 bucket backing the Snowflake Horizon Iceberg tables. Must be globally unique; set in terraform.tfvars."
  type        = string
}

variable "prefix" {
  description = "Key prefix Snowflake is scoped to within the bucket."
  type        = string
  default     = "horizon"
}

variable "role_name" {
  description = "Name of the IAM role Snowflake assumes to access the bucket."
  type        = string
  default     = "snowflake-iceberg-horizon-role"
}

variable "snowflake_external_id" {
  description = <<-EOT
    External ID enforced in the role's trust policy. Start with the placeholder
    and, after CREATE EXTERNAL VOLUME, set this to the value you chose for
    STORAGE_AWS_EXTERNAL_ID (e.g. "iceberg_horizon_ext_id") and re-apply.
  EOT
  type        = string
  default     = "0000"
}

variable "snowflake_iam_user_arn" {
  description = <<-EOT
    Snowflake's IAM principal (STORAGE_AWS_IAM_USER_ARN from DESC EXTERNAL VOLUME).
    Leave empty on the first apply (trust stays scoped to this account); set it
    after Snowflake reports it back, then re-apply to lock the trust policy down.
  EOT
  type        = string
  default     = ""
}
