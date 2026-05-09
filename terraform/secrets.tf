variable "github_token" {
  description = "GitHub PAT (GH_TOKEN) for ArgoCD Image Updater git write-back"
  type        = string
  sensitive   = true
}

variable "grafana_github_client_id" {
  description = "GitHub OAuth App client ID for Grafana"
  type        = string
  sensitive   = true
}

variable "grafana_github_client_secret" {
  description = "GitHub OAuth App client secret for Grafana"
  type        = string
  sensitive   = true
}

variable "resend_api_key" {
  description = "Resend API key for Alertmanager SMTP"
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

resource "aws_secretsmanager_secret" "grafana_oauth" {
  name                    = "detailsnap/grafana-oauth"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "grafana_oauth" {
  secret_id = aws_secretsmanager_secret.grafana_oauth.id
  secret_string = jsonencode({
    client_id     = var.grafana_github_client_id
    client_secret = var.grafana_github_client_secret
  })
}

resource "aws_secretsmanager_secret" "resend" {
  name                    = "detailsnap/resend"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "resend" {
  secret_id = aws_secretsmanager_secret.resend.id
  secret_string = jsonencode({
    api_key = var.resend_api_key
  })
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    secret = random_password.jwt_secret.result
  })
}
