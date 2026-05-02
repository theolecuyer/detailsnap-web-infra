terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Backend values passed via -backend-config at init time (see .github/workflows)
}

provider "aws" {
  region = "us-east-1"
}
