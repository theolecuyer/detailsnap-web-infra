locals {
  gateway_envs = {
    qa   = "qa.tlecuyer.codes"
    uat  = "uat.tlecuyer.codes"
    prod = "prod.tlecuyer.codes"
  }
}

resource "null_resource" "gateway_cert_patch" {
  triggers = {
    cert_arn = module.acm.acm_certificate_arn
  }

  provisioner "local-exec" {
    command = templatefile("${path.module}/templates/gateway-cert-patch.sh.tftpl", {
      cert_arn  = module.acm.acm_certificate_arn
      repo_root = "${path.module}/.."
      hostnames = local.gateway_envs
    })
  }

  depends_on = [null_resource.argocd_apps]
}
