data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# S3 bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "iceberg" {
  bucket = var.bucket_name
}

# Versioning is enabled because the access policy grants GetObjectVersion /
# DeleteObjectVersion — Snowflake Iceberg works against a versioned bucket.
resource "aws_s3_bucket_versioning" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "iceberg" {
  bucket = aws_s3_bucket.iceberg.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------------------------------------------------------------------------
# IAM policy — Snowflake Horizon Iceberg read/write, scoped to <prefix>/*
# ---------------------------------------------------------------------------

resource "aws_iam_policy" "snowflake_horizon_iceberg" {
  name        = "snowflake-iceberg-horizon-policy"
  description = "Read/write access for Snowflake Horizon Iceberg tables under s3://${var.bucket_name}/${var.prefix}/"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SnowflakeIcebergRW"
        Effect = "Allow"
        Action = [
          "s3:PutObject",
          "s3:GetObject",
          "s3:GetObjectVersion",
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = "${aws_s3_bucket.iceberg.arn}/${var.prefix}/*"
      },
      {
        Sid    = "SnowflakeListBucket"
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation"
        ]
        Resource = aws_s3_bucket.iceberg.arn
        Condition = {
          StringLike = {
            "s3:prefix" = ["${var.prefix}/*"]
          }
        }
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# IAM role Snowflake assumes (chicken-and-egg trust policy)
#
# First apply: snowflake_iam_user_arn = "" so the principal is this AWS account
# (placeholder, per step 3). After CREATE EXTERNAL VOLUME, set
# snowflake_iam_user_arn + snowflake_external_id from DESC EXTERNAL VOLUME and
# re-apply to lock the trust down to Snowflake's real principal (step 5).
# ---------------------------------------------------------------------------

locals {
  trust_principal = var.snowflake_iam_user_arn != "" ? var.snowflake_iam_user_arn : "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
}

resource "aws_iam_role" "snowflake_horizon_iceberg" {
  name        = var.role_name
  description = "Role Snowflake assumes for Horizon Iceberg external volume."

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SnowflakeAssumeRole"
        Effect = "Allow"
        Principal = {
          AWS = local.trust_principal
        }
        Action = "sts:AssumeRole"
        Condition = {
          StringEquals = {
            "sts:ExternalId" = var.snowflake_external_id
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "snowflake_horizon_iceberg" {
  role       = aws_iam_role.snowflake_horizon_iceberg.name
  policy_arn = aws_iam_policy.snowflake_horizon_iceberg.arn
}
