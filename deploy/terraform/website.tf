# =============================================================================
# S3 website hosting
# =============================================================================
# The bucket uses the S3 *website* endpoint (not the REST endpoint) because
# we want index.html / error.html routing. The bucket policy restricts access
# to Cloudflare's edge IPs, so the bucket is not directly readable from the
# public internet — visitors only ever reach it through Cloudflare's CDN.
# =============================================================================

resource "aws_s3_bucket" "site" {
  bucket = var.domain_name
}

# Static website hosting config. With this enabled, the bucket exposes a
# website endpoint like voxivium.com.s3-website-us-east-1.amazonaws.com.
resource "aws_s3_bucket_website_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    # Astro builds src/pages/404.astro into dist/404.html when output is static.
    key = "404.html"
  }
}

# We need the website endpoint to be reachable from Cloudflare, so we have
# to allow some level of public access. Block ACLs/policies we don't control,
# but allow the bucket policy itself.
resource "aws_s3_bucket_public_access_block" "site" {
  bucket = aws_s3_bucket.site.id

  block_public_acls       = true
  block_public_policy     = false # we DO want our restrictive policy to apply
  ignore_public_acls      = true
  restrict_public_buckets = false
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Bucket policy: anonymous GetObject is allowed ONLY when the request comes
# from a Cloudflare edge IP. Direct hits to the S3 website URL from anywhere
# else get a 403.
data "aws_iam_policy_document" "site" {
  statement {
    sid       = "AllowCloudflareReadOnly"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }

    condition {
      test     = "IpAddress"
      variable = "aws:SourceIp"
      values   = var.cloudflare_ip_ranges
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site.json

  # The public access block must allow the policy before we attach it
  depends_on = [aws_s3_bucket_public_access_block.site]
}

output "site_website_endpoint" {
  value       = aws_s3_bucket_website_configuration.site.website_endpoint
  description = "Point Cloudflare CNAME at this hostname"
}
