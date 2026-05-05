locals {
  cluster_version = "1.32"
}

data "aws_iam_role" "lab" {
  name = "LabRole"
}

# Tracks the latest AL2023 AMI for the cluster version.
# To demo security patching: run terraform plan after AWS releases a new AMI —
# this parameter updates automatically and Terraform will show a node group diff,
# triggering a rolling replacement of all nodes.
data "aws_ssm_parameter" "eks_ami_release_version" {
  name = "/aws/service/eks/optimized-ami/${local.cluster_version}/amazon-linux-2023/x86_64/standard/recommended/release_version"
}

resource "aws_eks_cluster" "main" {
  name     = "detailsnap"
  role_arn = data.aws_iam_role.lab.arn
  version  = local.cluster_version

  vpc_config {
    subnet_ids              = module.vpc.private_subnets
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    authentication_mode                         = "API"
    bootstrap_cluster_creator_admin_permissions = true
  }
}

resource "aws_eks_node_group" "envs" {
  for_each = {
    qa   = { desired = 1, min = 1, max = 2 }
    uat  = { desired = 1, min = 1, max = 2 }
    prod = { desired = 2, min = 2, max = 3 }
  }

  cluster_name    = aws_eks_cluster.main.name
  node_group_name = each.key
  node_role_arn   = data.aws_iam_role.lab.arn
  subnet_ids      = module.vpc.private_subnets

  ami_type        = "AL2023_x86_64_STANDARD"
  instance_types  = ["t3.micro"]
  release_version = data.aws_ssm_parameter.eks_ami_release_version.value

  scaling_config {
    desired_size = each.value.desired
    min_size     = each.value.min
    max_size     = each.value.max
  }

  update_config {
    max_unavailable = 1
  }

  labels = {
    env = each.key
  }
}
