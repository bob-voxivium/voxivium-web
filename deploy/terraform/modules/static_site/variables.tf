variable "name_prefix" {
  description = "Prefix for resource names + tagging (e.g. voxivium-prod-kmp-web)."
  type        = string
}

variable "hostname" {
  description = "Fully-qualified hostname (e.g. app.voxivium.com). The S3 bucket name is derived from this; CloudFront serves at this hostname via the Cloudflare CNAME."
  type        = string
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone id that owns the apex domain. Empty string skips the Cloudflare CNAME — useful when Terraform is run before Cloudflare credentials are wired, or when DNS is being managed manually."
  type        = string
  default     = ""
}

variable "default_root_object" {
  description = "Root document served at /. KMP-web serves index.html; SPA-only sites may want something else."
  type        = string
  default     = "index.html"
}

variable "spa_fallback" {
  description = "Whether to return index.html (with HTTP 200) for 404s. True for SPA routing where the JS bundle handles client-side routes. KMP-web ships a single index.html that boots the Compose app — fallback should be on."
  type        = bool
  default     = true
}

# Astro's default "directory" build format writes /donate/index.html rather
# than /donate.html. CloudFront's default_root_object only rewrites the bare
# "/" — for every other subdirectory it asks S3 for the literal object key
# ("donate"), which doesn't exist, and OAC-backed S3 returns 403 AccessDenied
# without leaking existence. A viewer-request CloudFront Function fixes this
# at the edge by appending "index.html" for URIs that look like directories.
# SPA distributions don't need it (spa_fallback already routes everything to
# index.html), so it's opt-in.
variable "resolve_directory_index" {
  description = "Attach a CloudFront Function that rewrites /foo and /foo/ to /foo/index.html so multi-page static builds (e.g. Astro directory format) serve subdirectory pages behind a private S3 origin."
  type        = bool
  default     = false
}

variable "price_class" {
  description = "CloudFront price class. PriceClass_100 = US/EU/Israel only (cheapest, ~$0.085/GB). PriceClass_200 adds Asia/Pacific. PriceClass_All is global."
  type        = string
  default     = "PriceClass_100"
}

# CloudFront Host-matches every incoming request against its aliases list. If
# a request's Host header isn't in aliases (and the request didn't arrive on
# the *.cloudfront.net domain), CloudFront returns 403 before even hitting
# the origin. When a proxy like Cloudflare fronts the distribution, aliases
# must include every hostname Cloudflare forwards with.
variable "aliases" {
  description = "Alternate domain names (CNAMEs) the distribution should accept. Must be covered by acm_certificate_arn's SANs. Empty list = distribution only answers at its xxx.cloudfront.net domain."
  type        = list(string)
  default     = []
}

# When aliases is non-empty, CloudFront requires a matching ACM cert issued
# in us-east-1 (regardless of the distribution's edge locations). The
# default *.cloudfront.net cert can't serve custom aliases.
variable "acm_certificate_arn" {
  description = "ARN of an ACM certificate (in us-east-1) whose SANs cover every alias. Empty string uses the default *.cloudfront.net cert — only valid when aliases is empty."
  type        = string
  default     = ""
}
