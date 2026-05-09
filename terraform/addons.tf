resource "null_resource" "wait_for_system_node" {
  triggers = {
    node_group_id = aws_eks_node_group.system.id
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1
      kubectl wait nodes -l node-type=system --for=condition=Ready --timeout=300s
    EOT
  }

  depends_on = [aws_eks_node_group.system]
}

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

resource "null_resource" "pre_destroy_lbc" {
  triggers = {
    cluster_name = aws_eks_cluster.main.name
    vpc_id       = module.vpc.vpc_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = templatefile("${path.module}/templates/pre-destroy-lbc.sh.tftpl", {
      cluster_name = self.triggers.cluster_name
      vpc_id       = self.triggers.vpc_id
    })
  }

  depends_on = [helm_release.aws_lbc]
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

  set {
    name  = "defaultTargetType"
    value = "ip"
  }

  set {
    name  = "defaultLoadBalancerScheme"
    value = "internet-facing"
  }

  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  depends_on = [null_resource.gateway_api_crds, null_resource.wait_for_system_node]
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

  set {
    name  = "global.nodeSelector.node-type"
    value = "system"
  }

  depends_on = [helm_release.aws_lbc, null_resource.wait_for_system_node]
}

resource "null_resource" "argocd_apps" {
  triggers = {
    applicationset = filesha256("${path.module}/../k8s/apps/applicationset.yaml")
    cluster_app    = filesha256("${path.module}/../k8s/apps/cluster.yaml")
  }

  provisioner "local-exec" {
    command = templatefile("${path.module}/templates/argocd-bootstrap.sh.tftpl", {
      cluster_name = aws_eks_cluster.main.name
    })
  }

  depends_on = [helm_release.argocd]
}

resource "null_resource" "pre_destroy_eso" {
  triggers = {
    eso_version  = helm_release.external_secrets.version
    cluster_name = aws_eks_cluster.main.name
  }

  provisioner "local-exec" {
    when    = destroy
    command = templatefile("${path.module}/templates/pre-destroy-eso.sh.tftpl", {
      cluster_name = self.triggers.cluster_name
    })
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

  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  depends_on = [helm_release.aws_lbc, null_resource.wait_for_system_node]
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

  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  depends_on = [helm_release.aws_lbc, null_resource.gateway_api_crds, null_resource.wait_for_system_node]
}

resource "helm_release" "argocd_image_updater" {
  name             = "argocd-image-updater"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argocd-image-updater"
  namespace        = "argocd"
  create_namespace = false
  wait             = true
  timeout          = 300

  set {
    name  = "config.registries[0].name"
    value = "ECR"
  }

  set {
    name  = "config.registries[0].prefix"
    value = "651084712750.dkr.ecr.us-east-1.amazonaws.com"
  }

  set {
    name  = "config.registries[0].api_url"
    value = "https://651084712750.dkr.ecr.us-east-1.amazonaws.com"
  }

  set {
    name  = "config.registries[0].credentials"
    value = "awssdk:"
  }

  set {
    name  = "config.registries[0].credsexpire"
    value = "10h"
  }

  set {
    name  = "nodeSelector.node-type"
    value = "system"
  }

  depends_on = [helm_release.argocd]
}

resource "null_resource" "image_updater_git_creds" {
  triggers = {
    image_updater = helm_release.argocd_image_updater.version
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1
      kubectl create secret generic image-updater-git-creds \
        --namespace argocd \
        --from-literal=username=theolecuyer \
        --from-literal=password=${var.github_token} \
        --dry-run=client -o yaml | kubectl apply -f -
    EOT
  }

  depends_on = [helm_release.argocd_image_updater]
}

resource "helm_release" "argo_rollouts" {
  name             = "argo-rollouts"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-rollouts"
  version          = "2.38.1"
  namespace        = "argo-rollouts"
  create_namespace = true

  # Enable the dashboard so we can see rollout progress in the UI
  set {
    name  = "dashboard.enabled"
    value = "true"
  }

  set {
    name  = "controller.nodeSelector.node-type"
    value = "system"
  }

  depends_on = [null_resource.wait_for_system_node]
}
