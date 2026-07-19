# Provider source declarations. Terraform requires each module that uses
# a non-hashicorp provider to declare its source explicitly, otherwise
# it defaults to `hashicorp/<name>` (which doesn't exist for cloudflare).
terraform {
  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 4.40"
    }
  }
}
