# =============================================================================
# Terraform State Backend Bootstrap
# =============================================================================
# Run this ONCE before anything else. It creates:
#   - An S3 bucket to store Terraform state files (versioned, encrypted)
#   - A DynamoDB table for state locking (prevents concurrent edits)
#
# Usage:
#   cd terraform/bootstrap
#   terraform init
#   terraform apply
#
# After this runs, copy the bucket name into ../backend.tf and run
# `terraform init` in the parent directory to migrate state.
# =============================================================================

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
  # No backend block here — this config uses local state on purpose.
  # It bootstraps the remote backend that everything else will use.
}

provider "aws" {
  region = "us-east-1"
}

# Globally unique bucket name. AWS account ID is added as a suffix to
# guarantee uniqueness across AWS.
data "aws_caller_identity" "current" {}

locals {
  state_bucket_name = "voxivium-tf-state-${data.aws_caller_identity.current.account_id}"
  lock_table_name   = "voxivium-tf-locks"
}

resource "aws_s3_bucket" "tf_state" {
  bucket = local.state_bucket_name

  # Safety: prevent accidental destruction of state history
  lifecycle {
    prevent_destroy = true
  }
}

# Versioning lets you roll back state if something goes sideways
resource "aws_s3_bucket_versioning" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration {
    status = "Enabled"
  }
}

# Always encrypt state at rest — it can contain secrets
resource "aws_s3_bucket_server_side_encryption_configuration" "tf_state" {
  bucket = aws_s3_bucket.tf_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Block ALL public access. State files must never be public.
resource "aws_s3_bucket_public_access_block" "tf_state" {
  bucket                  = aws_s3_bucket.tf_state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# DynamoDB table used for state locking. PAY_PER_REQUEST = no idle cost.
resource "aws_dynamodb_table" "tf_locks" {
  name         = local.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }
}

output "state_bucket" {
  value       = aws_s3_bucket.tf_state.id
  description = "Copy this into ../backend.tf"
}

output "lock_table" {
  value       = aws_dynamodb_table.tf_locks.name
  description = "Copy this into ../backend.tf"
}
