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

variable "support_recipient" {
  description = "Where /support form submissions are emailed immediately (App Store support channel)"
  type        = string
  default     = "support@voxivium.com"
}

variable "privacy_recipient" {
  description = "Where account-deletion and data-rights requests from /support are emailed (kept separate from general support — the Privacy Policy designates this address)"
  type        = string
  default     = "privacy@voxivium.com"
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

# ── Email authentication (see dns.tf) ────────────────────────────────────

variable "ses_dkim_tokens" {
  description = <<-EOT
    The three Easy DKIM tokens from SES console → Verified identities →
    voxivium.com → Authentication. Each becomes a CNAME at
    <token>._domainkey.voxivium.com. Empty list creates no records.

    DKIM is what makes SES mail pass DMARC: SES signs as voxivium.com
    while its default envelope sender is amazonses.com, so SPF alone does
    not align. Verify these resolve before tightening dmarc_policy.
  EOT
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.ses_dkim_tokens) == 0 || length(var.ses_dkim_tokens) == 3
    error_message = "SES Easy DKIM issues exactly three tokens — supply all three or none."
  }
}

variable "spf_record" {
  description = <<-EOT
    Full SPF TXT value for the apex. Empty string publishes no SPF record.

    Must name every service that sends mail as @voxivium.com. The default
    covers Google Workspace (zone MX is smtp.google.com) and Amazon SES.
    Confirm the list before applying — an omitted sender starts failing
    SPF the moment this is published.
  EOT
  type        = string
  default     = "v=spf1 include:_spf.google.com include:amazonses.com ~all"

  validation {
    condition     = var.spf_record == "" || startswith(var.spf_record, "v=spf1 ")
    error_message = "An SPF record must begin with \"v=spf1 \"."
  }
}

variable "dmarc_policy" {
  description = <<-EOT
    DMARC policy: none, quarantine, or reject.

    Start at none. It changes nothing about how receivers handle your mail
    but makes them send aggregate reports, which is how you discover what
    actually sends as this domain. Ramp to quarantine, then reject, only
    after reports come back clean — publishing reject before SPF and DKIM
    are correct makes receivers discard your own receipts.
  EOT
  type        = string
  default     = "none"

  validation {
    condition     = contains(["none", "quarantine", "reject"], var.dmarc_policy)
    error_message = "dmarc_policy must be one of: none, quarantine, reject."
  }
}

variable "dmarc_report_email" {
  description = <<-EOT
    Mailbox for DMARC aggregate reports. Keep it on voxivium.com —
    reporting to an address on another domain requires an authorization
    record in that domain's DNS, which is a common silent failure.

    Expect daily XML attachments from many providers. A dedicated alias
    is better than a personal inbox.
  EOT
  type        = string
  default     = "dmarc-reports@voxivium.com"
}
