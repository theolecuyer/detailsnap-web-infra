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

resource "null_resource" "resend_secret" {
  triggers = {
    api_key = var.resend_api_key
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws secretsmanager describe-secret --secret-id detailsnap/resend --region us-east-1 2>/dev/null \
        || aws secretsmanager create-secret --name detailsnap/resend --region us-east-1
      aws secretsmanager put-secret-value \
        --secret-id detailsnap/resend \
        --secret-string "{\"api_key\":\"$RESEND_API_KEY\"}" \
        --region us-east-1
    EOT
    environment = {
      RESEND_API_KEY = var.resend_api_key
    }
  }
}

resource "aws_secretsmanager_secret_version" "jwt" {
  secret_id = aws_secretsmanager_secret.jwt.id
  secret_string = jsonencode({
    secret = random_password.jwt_secret.result
  })
}

resource "aws_secretsmanager_secret" "mysql_exporter" {
  name                    = "detailsnap/mysql-exporter"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "mysql_exporter" {
  secret_id = aws_secretsmanager_secret.mysql_exporter.id
  secret_string = jsonencode({
    mycnf = "[client]\nuser = ${aws_db_instance.main.username}\npassword = ${random_password.db_master.result}\nhost = ${aws_db_instance.main.address}\nport = 3306\n"
  })
}
