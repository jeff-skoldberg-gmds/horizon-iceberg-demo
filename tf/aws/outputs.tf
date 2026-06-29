output "bucket_name" {
  value = aws_s3_bucket.iceberg.id
}

output "bucket_arn" {
  value = aws_s3_bucket.iceberg.arn
}

output "policy_arn" {
  value = aws_iam_policy.snowflake_horizon_iceberg.arn
}

output "role_arn" {
  description = "Use this for STORAGE_AWS_ROLE_ARN in CREATE EXTERNAL VOLUME."
  value       = aws_iam_role.snowflake_horizon_iceberg.arn
}
