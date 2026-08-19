# ==============================================================================
# Route 53 Public Hosted Zone
# ==============================================================================

resource "aws_route53_zone" "main" {
  name          = var.domain_name
  comment       = "Managed by Terraform - Production DNS Zone for ${var.domain_name}"
  force_destroy = false

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-hosted-zone"
    }
  )
}

# ==============================================================================
# AWS Certificate Manager (ACM) - Free Public TLS 1.3 Wildcard Certificate
# ==============================================================================

resource "aws_acm_certificate" "wildcard" {
  domain_name               = var.domain_name
  subject_alternative_names = ["*.${var.domain_name}"]
  validation_method         = "DNS"

  key_algorithm = "RSA_2048"

  tags = merge(
    var.tags,
    {
      Name = "${var.project_name}-${var.environment}-wildcard-cert"
    }
  )

  lifecycle {
    create_before_destroy = true
  }
}

# ==============================================================================
# Route 53 DNS Validation Record (Auto-created in Route 53)
# ==============================================================================

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.wildcard.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 60
  type            = each.value.type
  zone_id         = aws_route53_zone.main.zone_id
}

# ==============================================================================
# Route 53 Subdomain Routing Records (gitea, grafana, argocd)
# ==============================================================================

resource "aws_route53_record" "subdomains" {
  for_each = var.alb_dns_name != "" ? toset(var.subdomains) : toset([])

  zone_id = aws_route53_zone.main.zone_id
  name    = "${each.key}.${var.domain_name}"
  type    = "CNAME"
  ttl     = 300
  records = [var.alb_dns_name]
}
