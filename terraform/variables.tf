variable "aws_region" {
  description = "AWS region in which the data pipeline artifact bucket is provisioned."
  type        = string
}

variable "project_name" {
  description = "Short, lowercase project identifier used in resource names."
  type        = string
  default     = "dataops"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must be 2-21 lowercase letters, numbers, or hyphens and start with a letter."
  }
}

variable "environment" {
  description = "Deployment environment name."
  type        = string

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be dev, staging, or prod."
  }
}

variable "artifact_bucket_name" {
  description = "Globally unique S3 bucket name for data pipeline artifacts."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.artifact_bucket_name))
    error_message = "artifact_bucket_name must be a valid 3-63 character lowercase S3 bucket name."
  }
}

variable "github_repository" {
  description = "GitHub owner/repository allowed to assume the deployment role."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be in owner/repository format."
  }
}

variable "github_environment" {
  description = "GitHub Actions environment whose OIDC subject can deploy this environment."
  type        = string
}

variable "terraform_state_bucket_name" {
  description = "Pre-existing S3 bucket used for Terraform state."
  type        = string
}

variable "terraform_state_key" {
  description = "Environment-specific Terraform state key in the state bucket."
  type        = string
}

variable "tags" {
  description = "Additional resource tags."
  type        = map(string)
  default     = {}
}
