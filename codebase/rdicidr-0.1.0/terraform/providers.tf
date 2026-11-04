provider "aws" {
  region = var.aws_region

  # Every resource gets these tags automatically: you can see in the AWS
  # console (and in billing) which project/environment owns each resource.
  default_tags {
    tags = {
      Project     = "rdicidr"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}
