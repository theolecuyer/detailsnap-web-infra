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
  timeout          = 900

  set {
    name  = "clusterName"
    value = aws_eks_cluster.main.name
  }

  set {
    name  = "awsRegion"
    value = "us-east-1"
  }

  set {
    name  = "awsVpcID"
    value = module.vpc.vpc_id
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
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1 && kubectl apply -f ../k8s/gateway/gateway-class.yaml"
  }

  depends_on = [helm_release.aws_lbc]
}

resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  namespace        = "argocd"
  create_namespace = true
  wait             = true
  timeout          = 600

  set {
    name  = "server.insecure"
    value = "true"
  }

  depends_on = [helm_release.aws_lbc]
}

resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  repository       = "https://charts.external-secrets.io"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true
  wait             = true
  timeout          = 300

  depends_on = [aws_eks_node_group.envs]
}

resource "null_resource" "cluster_secret_store" {
  triggers = {
    eso_version = helm_release.external_secrets.version
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1 && kubectl wait --for condition=established crd/clustersecretstores.external-secrets.io --timeout=120s && kubectl apply -f ../k8s/cluster-secret-store.yaml"
  }

  depends_on = [helm_release.external_secrets]
}

resource "helm_release" "external_dns" {
  name             = "external-dns"
  repository       = "https://kubernetes-sigs.github.io/external-dns/"
  chart            = "external-dns"
  namespace        = "external-dns"
  create_namespace = true
  wait             = true
  timeout          = 300

  set {
    name  = "provider.name"
    value = "aws"
  }

  set {
    name  = "sources[0]"
    value = "service"
  }

  set {
    name  = "sources[1]"
    value = "gateway-httproute"
  }

  set {
    name  = "txtOwnerId"
    value = "detailsnap"
  }

  depends_on = [null_resource.gateway_api_crds, aws_eks_node_group.envs]
}
