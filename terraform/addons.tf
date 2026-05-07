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

resource "null_resource" "argocd_apps" {
  triggers = {
    applicationset = filesha256("${path.module}/../k8s/apps/applicationset.yaml")
    cluster_app    = filesha256("${path.module}/../k8s/apps/cluster.yaml")
  }

  provisioner "local-exec" {
    command = "aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1 && kubectl create namespace qa --dry-run=client -o yaml | kubectl apply -f - && kubectl create namespace uat --dry-run=client -o yaml | kubectl apply -f - && kubectl create namespace prod --dry-run=client -o yaml | kubectl apply -f - && kubectl wait --for condition=established crd/applicationsets.argoproj.io --timeout=120s && kubectl apply -f ../k8s/apps/"
  }

  depends_on = [helm_release.argocd]
}

resource "null_resource" "pre_destroy_eso" {
  triggers = {
    eso_version = helm_release.external_secrets.version
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      aws eks update-kubeconfig --name detailsnap --region us-east-1 || true
      kubectl delete externalsecret --all -A --ignore-not-found=true 2>/dev/null || true
      kubectl delete clustersecretstore --all --ignore-not-found=true 2>/dev/null || true
    EOT
  }

  depends_on = [helm_release.external_secrets]
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

  set {
    name  = "env[0].name"
    value = "AWS_DEFAULT_REGION"
  }

  set {
    name  = "env[0].value"
    value = "us-east-1"
  }

  depends_on = [null_resource.gateway_api_crds, aws_eks_node_group.envs]
}
