terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Backend values are intentionally omitted here and passed via -backend-config
  # flags at init time (see .github/workflows). This keeps the bucket name out
  # of source control and avoids hardcoding account-specific values.
  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
}
