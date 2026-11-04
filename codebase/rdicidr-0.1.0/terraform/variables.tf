variable "environment" {
  type        = string
  description = "Environment to deploy. One configuration, several isolated environments."

  validation {
    condition     = contains(["devel", "stage"], var.environment)
    error_message = "environment must be devel or stage."
  }
}

variable "aws_region" {
  type        = string
  description = "AWS region for the S3 buckets (CloudFront itself is global). The account only allows us-east-2."
  default     = "us-east-2"
}

# The app must be public only during the challenge recording period.
# A CloudFront Function compares the current time against these two values.
variable "access_window_start" {
  type        = string
  description = "UTC start of the public access window, e.g. 2026-11-04T00:00:00Z"

  validation {
    # formatdate() fails on anything that is not a valid RFC 3339 timestamp
    condition     = can(formatdate("YYYY", var.access_window_start))
    error_message = "Use RFC 3339 format, e.g. 2026-11-04T00:00:00Z."
  }
}

variable "access_window_end" {
  type        = string
  description = "UTC end of the public access window, e.g. 2026-11-18T23:59:59Z"

  validation {
    condition     = can(formatdate("YYYY", var.access_window_end))
    error_message = "Use RFC 3339 format, e.g. 2026-11-18T23:59:59Z."
  }
}

variable "log_retention_days" {
  type        = number
  description = "Days to keep CloudFront access logs before they are deleted."
  default     = 90
}
