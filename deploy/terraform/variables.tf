# =============================================================================
# Variables
# =============================================================================

variable "aws_region" {
  description = "AWS region for all resources"
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Environment name (prod, staging, dev)"
  type        = string
  default     = "prod"
}

variable "domain_name" {
  description = "Apex domain"
  type        = string
  default     = "voxivium.com"
}

variable "site_subdomain" {
  description = "Subdomain for www (the apex will redirect to this)"
  type        = string
  default     = "www.voxivium.com"
}

variable "ses_from_address" {
  description = "Verified SES sender for outbound digest emails"
  type        = string
  default     = "no-reply@voxivium.com"
}

variable "digest_recipient" {
  description = "Where the daily contact-form digest is sent"
  type        = string
  default     = "contact@voxivium.com"
}

variable "sms_recipient_number" {
  description = "Phone number that receives the daily SMS via Textbelt"
  type        = string
  default     = "8569796633"
}

variable "sms_admin_email" {
  description = "Email address mentioned in the SMS body (just text, not a destination)"
  type        = string
  default     = "bob.seamon@voxivium.com"
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for voxivium.com (find in Cloudflare dashboard, right sidebar of the zone)"
  type        = string
  # No default — set in terraform.tfvars
}
