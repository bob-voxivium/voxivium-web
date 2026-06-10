# =============================================================================
# Secrets: SSM Parameter Store (SecureString)
# =============================================================================
# We use SSM SecureString instead of Secrets Manager — it's free for standard
# parameters and sufficient for these low-volume secrets. Secrets Manager is
# overkill here and costs $0.40/secret/month.
#
# IMPORTANT: We declare these parameters but DO NOT set their values in
# Terraform. Setting secrets in Terraform puts them in state files (encrypted,
# but still). Instead, set them once with the AWS CLI after `terraform apply`:
#
#   aws ssm put-parameter --name /voxivium/textbelt-api-key \
#     --value 'YOUR_REAL_KEY' --type SecureString --overwrite
#
#   aws ssm put-parameter --name /voxivium/turnstile-secret-key \
#     --value 'YOUR_REAL_SECRET' --type SecureString --overwrite
#
# The `lifecycle.ignore_changes = [value]` block prevents Terraform from
# wiping out the real value on subsequent applies.
# =============================================================================

resource "aws_ssm_parameter" "textbelt_api_key" {
  name        = "/voxivium/textbelt-api-key"
  description = "Paid Textbelt API key for SMS sending"
  type        = "SecureString"
  value       = "PLACEHOLDER_SET_VIA_CLI" # overwritten manually after first apply

  lifecycle {
    ignore_changes = [value]
  }
}

resource "aws_ssm_parameter" "turnstile_secret_key" {
  name        = "/voxivium/turnstile-secret-key"
  description = "Cloudflare Turnstile server-side secret for token verification"
  type        = "SecureString"
  value       = "PLACEHOLDER_SET_VIA_CLI"

  lifecycle {
    ignore_changes = [value]
  }
}
