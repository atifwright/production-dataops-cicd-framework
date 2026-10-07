locals {
  name = "${var.project_name}-${var.environment}"

  common_tags = merge(
    {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
      Repository  = var.github_repository
    },
    var.tags
  )
}

data "aws_caller_identity" "current" {}

data "aws_partition" "current" {}

locals {
  github_oidc_provider_arn = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/token.actions.githubusercontent.com"
}

resource "aws_s3_bucket" "pipeline_artifacts" {
  bucket = var.artifact_bucket_name
}

resource "aws_s3_bucket_ownership_controls" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }

    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "pipeline_artifacts" {
  bucket = aws_s3_bucket.pipeline_artifacts.id

  rule {
    id     = "abort-incomplete-uploads"
    status = "Enabled"

    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_iam_role" "github_deployer" {
  name                 = "${local.name}-github-deployer"
  max_session_duration = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.github_oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repository}:environment:${var.github_environment}"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "github_deployer" {
  name = "${local.name}-pipeline-artifacts"
  role = aws_iam_role.github_deployer.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "ManagePipelineArtifactBucket"
        Effect = "Allow"
        Action = [
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:GetBucketLocation",
          "s3:GetEncryptionConfiguration",
          "s3:GetLifecycleConfiguration",
          "s3:GetOwnershipControls",
          "s3:GetPublicAccessBlock",
          "s3:GetBucketTagging",
          "s3:GetVersioning",
          "s3:ListBucket",
          "s3:PutEncryptionConfiguration",
          "s3:PutLifecycleConfiguration",
          "s3:PutOwnershipControls",
          "s3:PutPublicAccessBlock",
          "s3:PutBucketTagging",
          "s3:PutBucketVersioning"
        ]
        Resource = aws_s3_bucket.pipeline_artifacts.arn
      },
      {
        Sid    = "ManagePipelineArtifactObjects"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:AbortMultipartUpload"
        ]
        Resource = "${aws_s3_bucket.pipeline_artifacts.arn}/*"
      },
      {
        Sid      = "LocateEnvironmentTerraformStateBucket"
        Effect   = "Allow"
        Action   = ["s3:GetBucketLocation"]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket_name}"
      },
      {
        Sid      = "ListEnvironmentTerraformState"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket_name}"
        Condition = {
          StringLike = {
            "s3:prefix" = [
              var.terraform_state_key,
              "${var.terraform_state_key}*"
            ]
          }
        }
      },
      {
        Sid    = "ManageEnvironmentTerraformState"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [
          "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket_name}/${var.terraform_state_key}",
          "arn:${data.aws_partition.current.partition}:s3:::${var.terraform_state_bucket_name}/${var.terraform_state_key}.tflock"
        ]
      },
      {
        Sid      = "ReadDeployerRoleForTerraformRefresh"
        Effect   = "Allow"
        Action   = ["iam:GetRole", "iam:GetRolePolicy", "iam:ListRolePolicies"]
        Resource = "arn:${data.aws_partition.current.partition}:iam::${data.aws_caller_identity.current.account_id}:role/${local.name}-github-deployer"
      }
    ]
  })
}
