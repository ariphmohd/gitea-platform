# ==============================================================================
# Outputs for Custom Domain & Route 53 Module
# ==============================================================================

output "route53_zone_id" {
  description = "The Route 53 Public Hosted Zone ID"
  value       = aws_route53_zone.main.zone_id
}

output "route53_name_servers" {
  description = "The 4 Route 53 Name Servers to configure in your GoDaddy DNS settings"
  value       = aws_route53_zone.main.name_servers
}

output "acm_certificate_arn" {
  description = "The Amazon Resource Name (ARN) of the Wildcard TLS 1.3 certificate"
  value       = aws_acm_certificate.wildcard.arn
}

output "domain_name" {
  description = "The root domain name"
  value       = var.domain_name
}

output "gitea_https_url" {
  description = "Production HTTPS URL for Gitea"
  value       = "https://gitea.${var.domain_name}"
}

output "grafana_https_url" {
  description = "Production HTTPS URL for Grafana Dashboards"
  value       = "https://grafana.${var.domain_name}"
}

output "argocd_https_url" {
  description = "Production HTTPS URL for ArgoCD GitOps UI"
  value       = "https://argocd.${var.domain_name}"
}
