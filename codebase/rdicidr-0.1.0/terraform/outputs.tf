# Read by the CD pipeline (terraform output -raw ...) after apply.

output "site_url" {
  description = "Public URL of the application."
  value       = "https://${aws_cloudfront_distribution.site.domain_name}"
}

output "bucket" {
  description = "S3 bucket where the build is uploaded."
  value       = aws_s3_bucket.site.id
}

output "distribution_id" {
  description = "Used to invalidate the CloudFront cache after each deploy."
  value       = aws_cloudfront_distribution.site.id
}

output "logs_bucket" {
  description = "Bucket that stores the CloudFront access logs (prefix cloudfront/)."
  value       = aws_s3_bucket.logs.id
}
