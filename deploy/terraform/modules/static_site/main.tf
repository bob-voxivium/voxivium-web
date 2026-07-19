# Static site hosting — S3 (private origin) + CloudFront (CDN +
# HTTPS termination at the AWS edge) + Cloudflare CNAME at the
# customer-facing hostname. Reusable for KMP-web (Week 2) and the
# politician portal (Week 4+).
#
# Why both Cloudflare AND CloudFront? Cloudflare gives DNS + DDoS +
# WAF + analytics at the edge. CloudFront gives a stable origin that
# Cloudflare can target, plus AWS-side caching that survives a
# Cloudflare misconfiguration. The double-layer adds ~$0.40/GB at low
# volume; trivial.
#
# If/when we decide to drop CloudFront, swap the Cloudflare CNAME to
# point at the S3 website endpoint and tear down the distribution.

# ── S3 bucket (private origin) ────────────────────────────────────────
resource "aws_s3_bucket" "this" {
  bucket = "${var.name_prefix}-${replace(var.hostname, ".", "-")}"

  tags = {
    Name    = var.hostname
    Purpose = "static-site-origin"
  }
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  # Bucket is private; CloudFront reads via an OAC, not via public ACL.
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── CloudFront Origin Access Control ──────────────────────────────────
# OAC is the modern replacement for OAI — uses AWS Signature v4 to
# authenticate CloudFront → S3 requests. Required for CloudFront to
# read from a fully private bucket.
resource "aws_cloudfront_origin_access_control" "this" {
  name                              = "${var.name_prefix}-${replace(var.hostname, ".", "-")}-oac"
  description                       = "OAC for ${var.hostname}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ── CloudFront Function: append index.html for directory-style URIs ──
# Only created (and attached below) when resolve_directory_index = true.
# See functions/resolve-directory-index.js for the rewrite rules.
resource "aws_cloudfront_function" "resolve_directory_index" {
  count   = var.resolve_directory_index ? 1 : 0
  name    = "${var.name_prefix}-${replace(var.hostname, ".", "-")}-dir-index"
  runtime = "cloudfront-js-2.0"
  comment = "Append index.html for directory-style URIs on ${var.hostname}"
  publish = true
  code    = file("${path.module}/functions/resolve-directory-index.js")
}

# ── CloudFront distribution ───────────────────────────────────────────
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = var.hostname
  default_root_object = var.default_root_object
  price_class         = var.price_class
  aliases             = var.aliases

  origin {
    domain_name              = aws_s3_bucket.this.bucket_regional_domain_name
    origin_id                = "s3-${aws_s3_bucket.this.id}"
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id       = "s3-${aws_s3_bucket.this.id}"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    # AWS-managed cache policy "CachingOptimized" — TTL min 1s, default
    # 86400s (1d), max 31536000s (1y). Combined with content-hashed
    # asset filenames (composeApp.js is hashed by webpack), this gives
    # immutable-for-a-year caching of bundles.
    cache_policy_id = "658327ea-f89d-4fab-a63d-7e88639e58f6"

    dynamic "function_association" {
      for_each = var.resolve_directory_index ? [1] : []
      content {
        event_type   = "viewer-request"
        function_arn = aws_cloudfront_function.resolve_directory_index[0].arn
      }
    }
  }

  # SPA fallback — when CloudFront gets a 404 from S3 (the bundle's
  # routing path /subscribe/complete doesn't exist as an object),
  # serve index.html and let the SPA route client-side.
  dynamic "custom_error_response" {
    for_each = var.spa_fallback ? [403, 404] : []
    content {
      error_code            = custom_error_response.value
      response_code         = 200
      response_page_path    = "/index.html"
      error_caching_min_ttl = 0
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # When aliases is empty, use the built-in *.cloudfront.net cert (distribution
  # only answers at xxx.cloudfront.net). When aliases is set, use the caller-
  # supplied ACM cert (must live in us-east-1) so CloudFront can present a
  # valid cert AND accept requests whose Host header matches an alias.
  #
  # Even with Cloudflare fronting the distribution, the alias list matters:
  # Cloudflare forwards the original Host header to origin, and CloudFront
  # returns 403 for any Host it doesn't recognize as an alias — regardless
  # of what TLS cert terminated the outer connection.
  viewer_certificate {
    cloudfront_default_certificate = var.acm_certificate_arn == ""
    acm_certificate_arn            = var.acm_certificate_arn == "" ? null : var.acm_certificate_arn
    ssl_support_method             = var.acm_certificate_arn == "" ? null : "sni-only"
    minimum_protocol_version       = var.acm_certificate_arn == "" ? null : "TLSv1.2_2021"
  }

  tags = {
    Name = var.hostname
  }
}

# ── S3 bucket policy granting OAC read ────────────────────────────────
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AllowCloudFrontServicePrincipal"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.this.arn}/*"
        Condition = {
          StringEquals = {
            "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
          }
        }
      },
    ]
  })
}

# ── Cloudflare CNAME (optional) ───────────────────────────────────────
# When cloudflare_zone_id is empty, the operator manages DNS manually
# (or hasn't yet wired the Cloudflare API token). Skipping this resource
# leaves the CloudFront distribution functional at its xxx.cloudfront.net
# domain — operator can CNAME the public hostname there manually.
resource "cloudflare_record" "this" {
  count = var.cloudflare_zone_id == "" ? 0 : 1

  zone_id = var.cloudflare_zone_id
  name    = var.hostname
  type    = "CNAME"
  content = aws_cloudfront_distribution.this.domain_name
  proxied = true
  ttl     = 1 # automatic when proxied
}
