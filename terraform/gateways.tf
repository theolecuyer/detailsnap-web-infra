locals {
  gateway_envs = {
    qa   = "qa.tlecuyer.codes"
    uat  = "uat.tlecuyer.codes"
    prod = "prod.tlecuyer.codes"
  }
}

resource "null_resource" "gateways" {
  for_each = local.gateway_envs

  triggers = {
    cert_arn = module.acm.acm_certificate_arn
    hostname  = each.value
  }

  provisioner "local-exec" {
    command = templatefile("${path.module}/templates/apply-gateway.sh.tftpl", {
      cluster_name = aws_eks_cluster.main.name
      namespace    = each.key
      hostname     = each.value
      cert_arn     = module.acm.acm_certificate_arn
    })
  }

  depends_on = [null_resource.argocd_apps]
}
