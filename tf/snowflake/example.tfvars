# Copy to terraform.tfvars and fill in your values:
#   cp example.tfvars terraform.tfvars
# terraform.tfvars is gitignored so your real values are never committed.

# Snowflake account identifier, split into its two halves.
# e.g. account "MYORG-MYACCT" -> organization_name = "MYORG", account_name = "MYACCT"
organization_name = "MYORG"
account_name      = "MYACCT"

# Snowflake user for key-pair (JWT) auth, and the path to its private key.
snowflake_user   = "MY_USER"
private_key_file = "/path/to/snowflake_rsa_key.p8"

# Warehouse for the Terraform session.
warehouse = "ETL_XS"

# Must match the AWS stack: the S3 bucket and the AWS account that owns the role.
bucket_name    = "my-org-iceberg"
aws_account_id = "123456789012"
