variable "github_token" {
  description = "GitHub PAT (GH_TOKEN) for ArgoCD Image Updater git write-back"
  type        = string
  sensitive   = true
}

resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "aws_secretsmanager_secret" "jwt" {
  name                    = "detailsnap/jwt"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    secret = random_password.jwt_secret.result
  })
}
