output "database_name" {
  value = snowflake_database.ice_raw.name
}

output "transformed_database_name" {
  value = snowflake_database.ice_transformed.name
}

output "schema_name" {
  value = "${snowflake_database.ice_raw.name}.${snowflake_schema.landing.name}"
}

output "external_volume_name" {
  value = snowflake_external_volume.horizon.name
}

# The full DESC EXTERNAL VOLUME output. After apply, find the STORAGE_LOCATIONS
# row and read STORAGE_AWS_IAM_USER_ARN and STORAGE_AWS_EXTERNAL_ID from its
# JSON — those are Snowflake's real principal. Feed STORAGE_AWS_IAM_USER_ARN
# back into the AWS stack's snowflake_iam_user_arn variable and re-apply to
# lock down the role's trust policy.
output "describe_output" {
  description = "Raw DESC EXTERNAL VOLUME rows; contains STORAGE_AWS_IAM_USER_ARN."
  value       = snowflake_external_volume.horizon.describe_output
}
