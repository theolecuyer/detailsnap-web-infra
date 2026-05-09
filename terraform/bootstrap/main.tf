terraform {
  required_version = ">= 1.9"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # After first apply, run: terraform init -backend-config=../backend-bootstrap.hcl
  backend "s3" {}
}

provider "aws" {
  region = "us-east-1"
}

data "aws_caller_identity" "current" {}

locals {
  bucket_name = "detailsnap-tfstate-${data.aws_caller_identity.current.account_id}"
  table_name  = "detailsnap-tfstate-locks"
}

resource "aws_s3_bucket" "state" {
  bucket = local.bucket_name

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "locks" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}

locals {
  ecr_repositories = ["frontend", "auth-service", "core-service", "media-service"]
}

resource "aws_ecr_repository" "services" {
  for_each = toset(local.ecr_repositories)

  name                 = "detailsnap/${each.key}"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }
}

output "state_bucket" {
  value       = aws_s3_bucket.state.bucket
  description = "Set as TF_STATE_BUCKET in GitHub Actions variables"
}

output "lock_table" {
  value       = aws_dynamodb_table.locks.name
  description = "Set as TF_LOCK_TABLE in GitHub Actions variables"
}

output "ecr_registry" {
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com"
  description = "ECR registry URL"
}

data "aws_route53_zone" "main" {
  name         = "tlecuyer.codes"
  private_zone = false
}

resource "aws_route53_record" "resend_dkim" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "resend._domainkey.system"
  type    = "TXT"
  ttl     = 300
  records = ["p=MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDYt6bJ0o45vf8BRJ1o4oyOD1UYxrWUpq0vWobBxDfTFGl3cf1A6DiaO4HqVhaOo/Ww9pQqzx75dnBUGmW17LsY57N/y3QDANtAUOw5LsIa1dkCnlfJD2mBM06NisxZviJftdxso6vn/G1Gel3FzuNs+WvwI6z0gMPjRrI+qe1b/QIDAQAB"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "resend_spf_mx" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "send.system"
  type    = "MX"
  ttl     = 300
  records = ["10 feedback-smtp.us-east-1.amazonses.com"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "resend_spf_txt" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "send.system"
  type    = "TXT"
  ttl     = 300
  records = ["v=spf1 include:amazonses.com ~all"]

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_route53_record" "dmarc" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "_dmarc"
  type    = "TXT"
  ttl     = 300
  records = ["v=DMARC1; p=none;"]

  lifecycle {
    prevent_destroy = true
  }
}
