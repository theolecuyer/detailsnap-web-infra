output "cluster_endpoint" {
  value = aws_eks_cluster.main.endpoint
}

output "rds_host" {
  value = aws_db_instance.main.address
}

output "media_bucket" {
  value = module.media_bucket.s3_bucket_id
}

output "ecr_registry" {
  value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.us-east-1.amazonaws.com"
}

output "certificate_arn" {
  value = module.acm.acm_certificate_arn
}
