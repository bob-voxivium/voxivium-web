output "bucket_name" {
  description = "S3 bucket holding the static bundle. CI uploads via `aws s3 sync`."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "S3 bucket ARN — for IAM grants to CI deploy roles."
  value       = aws_s3_bucket.this.arn
}

output "cloudfront_domain" {
  description = "CloudFront distribution domain (xxx.cloudfront.net). CNAME the public hostname here when not using the auto-wired Cloudflare resource."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution id. CI uses this for `aws cloudfront create-invalidation` after a deploy."
  value       = aws_cloudfront_distribution.this.id
}
