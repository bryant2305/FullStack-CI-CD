# -----------------------------------------------------------------------------
# Terraform + provider versions and remote state.
# Pinning versions makes every run (your laptop, CI) behave the same.
# -----------------------------------------------------------------------------
terraform {
  # >= 1.10 is required for S3-native state locking (use_lockfile).
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80" # any 5.x >= 5.80, never a breaking 6.x
    }
  }

  # Remote state in S3 (bucket "state-fullstack", hardened by terraform/bootstrap).
  # "bucket" and "key" are NOT hardcoded: the CD pipeline passes them with
  # -backend-config, so each environment gets its own state file:
  #   rdicidr/devel/terraform.tfstate   and   rdicidr/stage/terraform.tfstate
  backend "s3" {
    region       = "us-east-2"
    encrypt      = true # state can contain sensitive data
    use_lockfile = true # prevents two applies running at the same time
  }
}
