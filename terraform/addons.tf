resource "null_resource" "gateway_api_crds" {
  triggers = {
    cluster_id = aws_eks_cluster.main.id
    version    = "v1.2.0"
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1
      kubectl apply -f https://github.com/kubernetes-sigs/gateway-api/releases/download/v1.2.0/standard-install.yaml
    EOT
  }

  depends_on = [aws_eks_node_group.envs]
}

resource "helm_release" "aws_lbc" {
  name             = "aws-load-balancer-controller"
  repository       = "https://aws.github.io/eks-charts"
  chart            = "aws-load-balancer-controller"
  namespace        = "kube-system"
  create_namespace = false
  wait             = true

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "enableGatewayAPI"
    value = "true"
  }

  depends_on = [null_resource.gateway_api_crds, aws_eks_node_group.envs]
}

resource "null_resource" "gateway_class" {
  triggers = {
    lbc_version = helm_release.aws_lbc.version
  }

  provisioner "local-exec" {
    command = "kubectl apply -f ../k8s/gateway/gateway-class.yaml"
  }

  depends_on = [helm_release.aws_lbc]
}
