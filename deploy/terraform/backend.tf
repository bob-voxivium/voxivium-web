# =============================================================================
# Remote state backend
# =============================================================================
# After running the bootstrap config, fill in the bucket name below
# (it will look like voxivium-tf-state-123456789012) and run:
#   terraform init -migrate-state
# =============================================================================

terraform {
  backend "s3" {
    bucket         = "voxivium-tf-state-071273296373"
    key            = "website/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "voxivium-tf-locks"
    encrypt        = true
  }
}
