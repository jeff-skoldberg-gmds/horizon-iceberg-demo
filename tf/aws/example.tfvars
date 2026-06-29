# Copy to terraform.tfvars and fill in your values:
#   cp example.tfvars terraform.tfvars
# terraform.tfvars is gitignored so your real values are never committed.

# AWS CLI/SDK profile to authenticate with.
profile = "default"

# Globally-unique S3 bucket name to back the Iceberg tables.
bucket_name = "my-org-iceberg"

# --- Set these AFTER the first apply + CREATE EXTERNAL VOLUME ---
# From DESC EXTERNAL VOLUME (STORAGE_AWS_IAM_USER_ARN). Leave the defaults
# (empty / "0000") on the first apply, then fill in and re-apply to lock the
# trust policy down to Snowflake's real principal.
snowflake_iam_user_arn = "arn:aws:iam::123456789012:user/abcd0000-s"
snowflake_external_id  = "iceberg_horizon_ext_id"
