# =============================================================================
# Cloudflare DNS records
# =============================================================================
# Prerequisite: voxivium.com is added to Cloudflare and its nameservers are
# changed at the registrar (Route 53 in your case) to Cloudflare's.
#
# These records are PROXIED (orange cloud) so traffic flows through
# Cloudflare's edge — that's what gives you DDoS, WAF, and the IP-range
# bucket policy match.
#
# If you'd rather manage DNS by hand in the Cloudflare dashboard, comment
# this whole file out and skip the cloudflare provider in providers.tf.
# =============================================================================

resource "cloudflare_record" "apex" {
  zone_id = var.cloudflare_zone_id
  name    = "@"
  type    = "CNAME" # Cloudflare flattens CNAME-on-apex automatically
  content = aws_s3_bucket_website_configuration.site.website_endpoint
  proxied = true
  ttl     = 1 # 1 = automatic when proxied
  comment = "Apex pointing at S3 website endpoint, proxied through Cloudflare"
}

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  content = aws_s3_bucket_website_configuration.site.website_endpoint
  proxied = true
  ttl     = 1
  comment = "www subdomain pointing at S3 website endpoint, proxied through Cloudflare"
}

# SES domain verification: TXT record. After `terraform apply`, get the
# verification token from the SES console (Verified identities → voxivium.com)
# and store it in terraform.tfvars as `ses_verification_token`. Or skip this
# resource if you've already verified the domain via a different method.

# DKIM CNAMEs for SES — three of them. Get the values from the SES console
# (Verified identities → voxivium.com → DKIM tab) once you create the
# domain identity, then add them here. Leaving these as a TODO for now —
# you mentioned SES is already set up and verified, but the DKIM CNAMEs
# need to be in Cloudflare specifically (not Route 53) since Cloudflare
# is now authoritative.
