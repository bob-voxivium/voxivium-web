# =============================================================================
# ACM certificate for the CloudFront distribution
# =============================================================================
# CloudFront requires ACM certs to be issued in us-east-1 regardless of where
# the distribution's edge locations serve traffic. The stack-wide AWS provider
# is already pinned to us-east-1 (see variables.tf and providers.tf), so no
# provider alias is needed.
#
# The cert covers voxivium.com (primary) + www.voxivium.com (SAN) so a single
# distribution can serve both hostnames as CloudFront aliases.
# =============================================================================

resource "aws_acm_certificate" "site" {
  domain_name               = var.domain_name
  subject_alternative_names = [var.site_subdomain]
  validation_method         = "DNS"

  # ACM cert replacement (e.g. bumping SANs) is safer as create-then-destroy
  # so the distribution never sees a moment without a valid cert.
  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name = var.domain_name
  }
}

# ACM emits one DNS validation record per name. Each is a CNAME that must
# exist as a DNS-only record (unproxied) — Cloudflare's proxy would rewrite
# the response and validation would fail.
#
# for_each must have plan-known keys, but ACM's domain_validation_options set
# isn't populated until apply. Trick: key off the static domain list (known
# from vars), and look up the validation record for each domain via one().
resource "cloudflare_record" "acm_validation" {
  for_each = toset([var.domain_name, var.site_subdomain])

  zone_id = var.cloudflare_zone_id
  name    = one([for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_name if dvo.domain_name == each.value])
  content = one([for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_value if dvo.domain_name == each.value])
  type    = one([for dvo in aws_acm_certificate.site.domain_validation_options : dvo.resource_record_type if dvo.domain_name == each.value])
  ttl     = 60
  proxied = false # ACM validation must not go through the CF proxy
}

# Blocks the apply on cert issuance so downstream resources (the CloudFront
# distribution's viewer_certificate) can safely reference the ARN.
resource "aws_acm_certificate_validation" "site" {
  certificate_arn         = aws_acm_certificate.site.arn
  validation_record_fqdns = [for r in cloudflare_record.acm_validation : r.hostname]
}
