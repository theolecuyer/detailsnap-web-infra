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
