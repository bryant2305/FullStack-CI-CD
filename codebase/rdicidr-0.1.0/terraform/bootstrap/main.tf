# Run once, locally, with admin credentials:
#   terraform init && terraform apply
#
# Prepares what the CD pipeline needs before it can run:
#   - hardens the Terraform state bucket (created beforehand in the console)
#   - one deploy IAM user per environment, with least-privilege permissions
#
# Why IAM users and not GitHub OIDC roles: this AWS account belongs to an
# organization whose service control policy denies
# iam:CreateOpenIDConnectProvider. Each environment therefore gets its own
# user; its access keys are created in the console and stored as secrets of
# the matching GitHub Environment (they never end up in Terraform state).

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}

provider "aws" {
  # The account's policies only allow creating S3 buckets in us-east-2.
  region = "us-east-2"

  default_tags {
    tags = {
      Project   = "rdicidr"
      ManagedBy = "terraform-bootstrap"
    }
  }
}

variable "state_bucket" {
  type        = string
  description = "Existing S3 bucket that stores the Terraform state of every environment."
  default     = "state-fullstack"
}

locals {
  environments = toset(["devel", "stage"])
}

# ---------- Terraform state bucket ----------
# Shared by all environments; each one writes its own key (rdicidr/<env>/...).

data "aws_s3_bucket" "state" {
  bucket = var.state_bucket
}

# Versioning = you can recover a previous state file if one gets corrupted.
resource "aws_s3_bucket_versioning" "state" {
  bucket = data.aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = data.aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ---------- One deploy user per environment ----------

resource "aws_iam_user" "deploy" {
  for_each = local.environments
  name     = "rdicidr-${each.key}-deploy"
}

# Least privilege: each user only touches its own state file and its own
# rdicidr-<env>-* buckets. cloudfront:* uses "*" because CloudFront barely
# supports resource-level permissions for create operations.
resource "aws_iam_user_policy" "deploy" {
  for_each = local.environments
  name     = "deploy"
  user     = aws_iam_user.deploy[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TerraformState"
        Effect   = "Allow"
        Action   = ["s3:ListBucket", "s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = [data.aws_s3_bucket.state.arn, "${data.aws_s3_bucket.state.arn}/rdicidr/${each.key}/*"]
      },
      {
        Sid      = "EnvironmentBuckets"
        Effect   = "Allow"
        Action   = "s3:*"
        Resource = ["arn:aws:s3:::rdicidr-${each.key}-*", "arn:aws:s3:::rdicidr-${each.key}-*/*"]
      },
      {
        Sid      = "CloudFront"
        Effect   = "Allow"
        Action   = "cloudfront:*"
        Resource = "*"
      }
    ]
  })
}

output "deploy_users" {
  description = "Create an access key for each user in the IAM console and store it in the matching GitHub Environment."
  value       = { for env, user in aws_iam_user.deploy : env => user.name }
}
