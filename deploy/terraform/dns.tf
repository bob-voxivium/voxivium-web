# =============================================================================
# Cloudflare DNS records
# =============================================================================
# Prerequisite: voxivium.com is added to Cloudflare and its nameservers are
# changed at the registrar (Route 53 in your case) to Cloudflare's.
#
# The apex record (voxivium.com) is created by the static_site module in
# website.tf. The www record is created here because the module only takes
# a single hostname; both point at the same CloudFront distribution.
#
# Records are PROXIED (orange cloud) so traffic flows through Cloudflare's
# edge — that's what gives you DDoS, WAF, and (now) valid end-to-end TLS
# when the zone is set to "Full (strict)".
# =============================================================================

resource "cloudflare_record" "www" {
  zone_id = var.cloudflare_zone_id
  name    = "www"
  type    = "CNAME"
  content = module.site.cloudfront_domain
  proxied = true
  ttl     = 1 # 1 = automatic when proxied
  comment = "www subdomain fronted by same CloudFront distribution as the apex"
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
