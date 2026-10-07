output "artifact_bucket_name" {
  description = "Name of the encrypted, versioned pipeline artifact bucket."
  value       = aws_s3_bucket.pipeline_artifacts.id
}

output "artifact_bucket_arn" {
  description = "ARN of the pipeline artifact bucket."
  value       = aws_s3_bucket.pipeline_artifacts.arn
}

output "github_deployer_role_arn" {
  description = "IAM role ARN to configure as the GitHub environment variable AWS_DEPLOY_ROLE_ARN."
  value       = aws_iam_role.github_deployer.arn
}
