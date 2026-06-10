# =============================================================================
# Provider versions and requirements
# =============================================================================
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }
    # Cloudflare provider is OPTIONAL — only used if you want DNS records
    # managed in Terraform. Comment out if you'd rather click around in the
    # Cloudflare dashboard for DNS.
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.0"
    }
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "voxivium"
      ManagedBy   = "terraform"
      Environment = var.environment
    }
  }
}

provider "cloudflare" {
  # Authenticates via the CLOUDFLARE_API_TOKEN env var — no provider arguments needed.
  # Create the token in the Cloudflare dashboard with Zone:DNS:Edit + Zone:Zone:Read
  # scoped to voxivium.com only. Do NOT put the token in Terraform files or commit it.
}
