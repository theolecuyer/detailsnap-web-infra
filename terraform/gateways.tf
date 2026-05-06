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
    cert_arn = aws_acm_certificate_validation.main.certificate_arn
    hostname = each.value
  }

  provisioner "local-exec" {
    command = <<-EOT
      aws eks update-kubeconfig --name ${aws_eks_cluster.main.name} --region us-east-1
      cat > /tmp/detailsnap-gateway-${each.key}.yaml <<YAML
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main
  namespace: ${each.key}
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/certificate-arn: ${aws_acm_certificate_validation.main.certificate_arn}
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    external-dns.alpha.kubernetes.io/hostname: ${each.value}
spec:
  gatewayClassName: alb
  listeners:
    - name: http
      port: 80
      protocol: HTTP
      allowedRoutes:
        namespaces:
          from: Same
    - name: https
      port: 443
      protocol: HTTPS
      allowedRoutes:
        namespaces:
          from: Same
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: tls-placeholder
YAML
      kubectl apply -f /tmp/detailsnap-gateway-${each.key}.yaml
    EOT
  }

  depends_on = [null_resource.argocd_apps]
}
