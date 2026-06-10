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

# Cloudflare's published list of edge IPs. We pin the bucket policy to these
# so the S3 website endpoint can only be reached through Cloudflare.
# Source: https://www.cloudflare.com/ips/
# Update this list periodically (Cloudflare announces changes).
variable "cloudflare_ip_ranges" {
  description = "Cloudflare edge IP ranges (IPv4). Update from https://www.cloudflare.com/ips/"
  type        = list(string)
  default = [
    "173.245.48.0/20",
    "103.21.244.0/22",
    "103.22.200.0/22",
    "103.31.4.0/22",
    "141.101.64.0/18",
    "108.162.192.0/18",
    "190.93.240.0/20",
    "188.114.96.0/20",
    "197.234.240.0/22",
    "198.41.128.0/17",
    "162.158.0.0/15",
    "104.16.0.0/13",
    "104.24.0.0/14",
    "172.64.0.0/13",
    "131.0.72.0/22",
  ]
}
