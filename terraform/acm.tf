data "aws_route53_zone" "main" {
  name         = "tlecuyer.codes"
  private_zone = false
}

module "acm" {
  source  = "terraform-aws-modules/acm/aws"
  version = "~> 4.0"

  domain_name               = "tlecuyer.codes"
  subject_alternative_names = ["*.tlecuyer.codes"]
  zone_id                   = data.aws_route53_zone.main.zone_id

  validation_method   = "DNS"
  wait_for_validation = true
}
