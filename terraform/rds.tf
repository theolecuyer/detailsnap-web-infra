resource "random_password" "db_master" {
  length           = 24
  special          = true
  override_special = "!#%&*()-_=+[]{}<>:?"
}

resource "aws_db_subnet_group" "main" {
  name       = "detailsnap"
  subnet_ids = module.vpc.private_subnets
}

resource "aws_security_group" "rds" {
  name        = "detailsnap-rds"
  description = "RDS MySQL"
  vpc_id      = module.vpc.vpc_id

  ingress {
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_eks_cluster.main.vpc_config[0].cluster_security_group_id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_db_instance" "main" {
  identifier        = "detailsnap"
  engine            = "mysql"
  engine_version    = "8.0"
  instance_class    = "db.t3.micro"
  allocated_storage = 20
  storage_type      = "gp2"

  db_name  = "detailsnap"
  username = "admin"
  password = random_password.db_master.result

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = false
  skip_final_snapshot = true
  deletion_protection = false
}

resource "null_resource" "db_init" {
  triggers = {
    db_instance = aws_db_instance.main.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1
      kubectl run db-init --rm --wait --image=mysql:8.0 --restart=Never \
        --env="MYSQL_PWD=${random_password.db_master.result}" \
        -- mysql -h ${aws_db_instance.main.address} -u admin \
        -e "CREATE DATABASE IF NOT EXISTS detailsnap_qa; CREATE DATABASE IF NOT EXISTS detailsnap_uat; CREATE DATABASE IF NOT EXISTS detailsnap_prod;"
    EOT
  }

  depends_on = [aws_eks_node_group.envs]
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "detailsnap/db"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    username = aws_db_instance.main.username
    password = random_password.db_master.result
  })
}
