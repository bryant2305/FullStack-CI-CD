data "aws_caller_identity" "current" {}

# AWS-managed CloudFront policies, looked up by name (no hardcoded IDs).
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_response_headers_policy" "security_headers" {
  name = "Managed-SecurityHeadersPolicy" # HSTS, X-Frame-Options, nosniff, ...
}

locals {
  name       = "rdicidr-${var.environment}"
  account_id = data.aws_caller_identity.current.account_id

  # devel is disposable (terraform destroy deletes everything);
  # stage refuses to delete buckets that still contain files.
  force_destroy = var.environment == "devel"
}

# =============================================================================
# Site bucket: holds the built app. Private, only CloudFront can read it.
# =============================================================================

resource "aws_s3_bucket" "site" {
  # Bucket names are global in AWS: the account ID makes them unique.
  bucket        = "${local.name}-site-${local.account_id}"
  force_destroy = local.force_destroy
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Keeps previous versions of every file: a bad deploy can be rolled back.
resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ...but old versions are deleted after 30 days so storage does not grow forever.
resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id

  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Only THIS CloudFront distribution may read the files (OAC).
        Sid       = "AllowCloudFrontRead"
        Effect    = "Allow"
        Principal = { Service = "cloudfront.amazonaws.com" }
        Action    = "s3:GetObject"
        Resource  = "${aws_s3_bucket.site.arn}/*"
        Condition = { StringEquals = { "AWS:SourceArn" = aws_cloudfront_distribution.site.arn } }
      },
      {
        # Reject any request that is not over HTTPS.
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.site.arn, "${aws_s3_bucket.site.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      }
    ]
  })

  # The public access block must exist before a bucket policy is attached.
  depends_on = [aws_s3_bucket_public_access_block.site]
}

# =============================================================================
# Logs bucket: CloudFront access logs (requirement of the challenge).
# =============================================================================

resource "aws_s3_bucket" "logs" {
  bucket        = "${local.name}-logs-${local.account_id}"
  force_destroy = local.force_destroy
}

resource "aws_s3_bucket_public_access_block" "logs" {
  bucket                  = aws_s3_bucket.logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# CloudFront standard logging writes through bucket ACLs, so ACLs must be
# enabled on this bucket (BucketOwnerPreferred). CloudFront grants itself
# write access automatically when logging is turned on.
resource "aws_s3_bucket_ownership_controls" "logs" {
  bucket = aws_s3_bucket.logs.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

# Logs are not kept forever: cheaper storage after 30 days, deleted after N days.
resource "aws_s3_bucket_lifecycle_configuration" "logs" {
  bucket = aws_s3_bucket.logs.id

  rule {
    id     = "log-retention"
    status = "Enabled"
    filter {}

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "logs" {
  bucket = aws_s3_bucket.logs.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "DenyInsecureTransport"
      Effect    = "Deny"
      Principal = "*"
      Action    = "s3:*"
      Resource  = [aws_s3_bucket.logs.arn, "${aws_s3_bucket.logs.arn}/*"]
      Condition = { Bool = { "aws:SecureTransport" = "false" } }
    }]
  })

  depends_on = [aws_s3_bucket_public_access_block.logs]
}

# =============================================================================
# CloudFront: the public entry point (HTTPS, cache, logs, access window).
# =============================================================================

# Origin Access Control: CloudFront signs its requests to S3, which is how
# the bucket can stay 100% private.
resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# "Accessible only during the challenge recording period":
# runs on every request at the edge; outside the window it answers 403.
# The window closes by itself, no redeploy needed.
resource "aws_cloudfront_function" "access_window" {
  name    = "${local.name}-access-window"
  runtime = "cloudfront-js-2.0"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var now = Date.now();
      if (now >= Date.parse('${var.access_window_start}') && now <= Date.parse('${var.access_window_end}')) {
        return event.request;
      }
      return { statusCode: 403, statusDescription: 'Forbidden' };
    }
  EOT
}

resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = local.name
  default_root_object = "index.html"
  price_class         = "PriceClass_100" # US/Canada/Europe edges only: cheapest

  origin {
    origin_id                = "s3"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  default_cache_behavior {
    target_origin_id           = "s3"
    viewer_protocol_policy     = "redirect-to-https" # HTTP -> HTTPS
    allowed_methods            = ["GET", "HEAD"]     # static site: read only
    cached_methods             = ["GET", "HEAD"]
    compress                   = true # gzip/brotli
    cache_policy_id            = data.aws_cloudfront_cache_policy.caching_optimized.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.security_headers.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.access_window.arn
    }
  }

  # Access logs -> logs bucket, under the cloudfront/ prefix.
  logging_config {
    bucket          = aws_s3_bucket.logs.bucket_domain_name
    prefix          = "cloudfront/"
    include_cookies = false
  }

  restrictions {
    geo_restriction {
      restriction_type = "none" # "anyone with Internet access"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true # *.cloudfront.net HTTPS certificate
  }

  # Logging fails if the logs bucket does not accept ACLs yet.
  depends_on = [aws_s3_bucket_ownership_controls.logs]
}
