# =============================================================================
# Static site hosting — voxivium.com apex + www
# =============================================================================
# Private S3 bucket + CloudFront (edge cache + valid TLS at the AWS edge) +
# Cloudflare (DNS + WAF + client TLS). Because CloudFront terminates with a
# valid *.cloudfront.net cert, the zone can safely run in Cloudflare's
# "Full (strict)" SSL mode — matching what api.voxivium.com (ALB) requires.
#
# Prior setup: S3 website endpoint + Cloudflare-IP-allowlist bucket policy,
# which only worked in "Flexible" SSL mode. Adding api.voxivium.com forced
# the zone to Full (strict), which broke the apex origin (S3 website
# endpoints do not speak TLS).
# =============================================================================

module "site" {
  source = "./modules/static_site"

  name_prefix         = "voxivium-${var.environment}"
  hostname            = var.domain_name
  cloudflare_zone_id  = var.cloudflare_zone_id
  spa_fallback        = false # Astro pre-renders every route; no SPA fallback needed
  price_class         = "PriceClass_100"
  default_root_object = "index.html"

  # Astro's directory build writes /donate/index.html, /about/index.html, etc.
  # CloudFront's default_root_object only rewrites "/"; every other subdirectory
  # request needs the edge function to append "index.html" or S3 (private, OAC)
  # returns 403 AccessDenied.
  resolve_directory_index = true

  # Cloudflare forwards the original Host header to CloudFront, so the
  # distribution must recognize both hostnames as aliases (else CloudFront
  # returns 403 before reaching the origin). The ACM cert covers both.
  aliases             = [var.domain_name, var.site_subdomain]
  acm_certificate_arn = aws_acm_certificate_validation.site.certificate_arn
}

output "site_bucket_name" {
  description = "S3 bucket that deploy.sh syncs the built site into."
  value       = module.site.bucket_name
}

output "site_cloudfront_distribution_id" {
  description = "CloudFront distribution id. deploy.sh uses this to invalidate the edge cache after a sync."
  value       = module.site.cloudfront_distribution_id
}

output "site_cloudfront_domain" {
  description = "CloudFront distribution hostname (xxx.cloudfront.net). Cloudflare CNAMEs for voxivium.com and www.voxivium.com point here."
  value       = module.site.cloudfront_domain
}
